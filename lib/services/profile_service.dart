import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_error.dart';
import '../utils/validators.dart';
import 'profile_local_db.dart';
import 'saved_accounts_db.dart';
import 'supabase_service.dart';

class ProfileService {
  final SupabaseClient _client = SupabaseService.client;

  Future<Map<String, dynamic>> getProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AppError(
        'You are signed out. Please log in to continue.',
        type: AppErrorType.auth,
      );
    }

    try {
      final profile = await _client
          .from('profiles')
          .select()
          .eq('supabase_user_id', user.id)
          .single();
      return profile;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') {
        throw const AppError(
          'Your profile could not be found. Please contact support.',
          type: AppErrorType.notFound,
        );
      }
      throw mapError(e, stackTrace: StackTrace.current);
    } catch (e) {
      if (e is AppError) rethrow;
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  Future<Map<String, dynamic>> getEmployee(String profileId) async {
    return _client
        .from('employees')
        .select()
        .eq('profile_id', profileId)
        .single();
  }

  Future<void> updateProfile({
    required String firstName,
    required String lastName,
    required String phone,
    String? email,
    String? address,
    String? landmark,
    double? pinLatitude,
    double? pinLongitude,
    bool removePin = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AppError(
        'You are signed out. Please log in to continue.',
        type: AppErrorType.auth,
      );
    }

    final newEmail = email?.trim().toLowerCase();
    final currentEmail = user.email?.trim().toLowerCase();

    // If an email change was requested, validate uniqueness and update Supabase Auth first.
    // Supabase Auth strictly enforces uniqueness across all users (customers, staff, riders).
    if (newEmail != null &&
        newEmail.isNotEmpty &&
        newEmail != currentEmail &&
        user.appMetadata['provider'] != 'google') {
      try {
        await _client.auth.updateUser(UserAttributes(email: newEmail));
      } catch (e) {
        throw mapError(e, stackTrace: StackTrace.current);
      }
    }

    // Pin values to persist: explicit coordinates, or NULL when removePin
    // is set (customer cleared their pin). Omitted entirely when neither is
    // provided so unrelated saves don't touch the pin.
    final pinColumns = <String, dynamic>{
      if (pinLatitude != null) 'pin_latitude': pinLatitude,
      if (pinLongitude != null) 'pin_longitude': pinLongitude,
      if (removePin) ...{'pin_latitude': null, 'pin_longitude': null},
    };

    final cleanPhone = Validators.normalizePhone(phone);
    final cleanFirst = Validators.cleanName(firstName);
    final cleanLast = Validators.cleanName(lastName);

    // Base payload for core fields
    final basePayload = <String, dynamic>{
      'first_name': cleanFirst.isNotEmpty ? cleanFirst : firstName,
      'last_name': cleanLast.isNotEmpty ? cleanLast : lastName,
      'phone': cleanPhone.isNotEmpty ? cleanPhone : phone,
      'email': email,
      'address': address,
      'landmark': landmark,
      'updated_at': DateTime.now().toIso8601String(),
    };

    // Update profiles table (with fallback if pin columns are not yet in the DB)
    try {
      await _client
          .from('profiles')
          .update({
            ...basePayload,
            ...pinColumns,
          })
          .eq('supabase_user_id', user.id);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST204' && pinColumns.isNotEmpty) {
        print('⚠️ profiles table missing pin columns, falling back to base fields: $e');
        await _client
            .from('profiles')
            .update(basePayload)
            .eq('supabase_user_id', user.id);
      } else {
        throw mapError(e, stackTrace: StackTrace.current);
      }
    } catch (e) {
      if (e is AppError) rethrow;
      throw mapError(e, stackTrace: StackTrace.current);
    }

    // Also update customers table if customer record exists
    try {
      // Get profile ID
      final profile = await _client
          .from('profiles')
          .select('id')
          .eq('supabase_user_id', user.id)
          .single();
      
      final profileId = profile['id'] as String;

      // Check if customer exists for this profile
      final customerExists = await _client
          .from('customers')
          .select('id')
          .eq('profile_id', profileId)
          .maybeSingle();

      if (customerExists != null) {
        // Update customer record
        try {
          await _client
              .from('customers')
              .update({
                ...basePayload,
                ...pinColumns,
              })
              .eq('profile_id', profileId);
          print('✅ Updated customer record with new address');
        } on PostgrestException catch (e) {
          if (e.code == 'PGRST204' && pinColumns.isNotEmpty) {
            print('⚠️ customers table missing pin columns, falling back: $e');
            await _client
                .from('customers')
                .update(basePayload)
                .eq('profile_id', profileId);
            print('✅ Updated customer record without pin columns');
          } else {
            rethrow;
          }
        }
      }
    } catch (e) {
      print('⚠️ Could not update customer record: $e');
      // Don't throw - profile was already updated successfully
    }
  }

  Future<void> updateEmployee({
    required String profileId,
    required String name,
    required String phone,
    String? vehicleDetails,
    String? deliveryZones,
  }) async {
    final cleanPhone = Validators.normalizePhone(phone);
    final cleanVehicle = vehicleDetails != null
        ? Validators.cleanVehicleDetails(vehicleDetails)
        : null;
    await _client
        .from('employees')
        .update({
          'name': name,
          'phone': cleanPhone.isNotEmpty ? cleanPhone : phone,
          'vehicle_details': cleanVehicle ?? vehicleDetails,
          'delivery_zones': deliveryZones,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('profile_id', profileId);
  }

  /// Saves the avatar locally in SQLite FIRST, then attempts to upload to Firebase Storage.
  /// If Firebase has an issue, the picture is still preserved locally in SQLite and
  /// can be synced later.
  Future<String?> uploadAvatar(File imageFile) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AppError(
        'You are signed out. Please log in to continue.',
        type: AppErrorType.auth,
      );
    }

    // Step 1: Save the picture to SQLite / local storage FIRST
    String localPath;
    try {
      localPath = await ProfileLocalDatabase.instance.saveLocalImage(
        userId: user.id,
        sourceFile: imageFile,
        isSynced: false,
      );
      print('💾 Profile picture saved in SQLite first: $localPath');
    } catch (e) {
      print('⚠️ Failed to save avatar in SQLite: $e');
      localPath = imageFile.path;
    }

    // Step 2: Firebase Storage retrieves and uploads that local picture
    final persistentFile = File(localPath);
    final isPng = persistentFile.path.toLowerCase().endsWith('.png');
    final ext = isPng ? 'png' : 'jpg';
    final path = 'avatars/${user.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';

    String? publicUrl;
    try {
      final storageRef = FirebaseStorage.instance.ref().child(path);
      final metadata = SettableMetadata(
        contentType: isPng ? 'image/png' : 'image/jpeg',
      );

      final uploadTask = await storageRef.putFile(persistentFile, metadata);
      publicUrl = await uploadTask.ref.getDownloadURL();
      print('✅ Profile picture uploaded to Firebase Storage from local file: $publicUrl');

      // Step 3: Mark synced in SQLite
      await ProfileLocalDatabase.instance.markSynced(
        userId: user.id,
        avatarUrl: publicUrl,
      );

      // Step 4: Update saved accounts in SQLite
      await SavedAccountsDatabase.instance.updateProfilePicture(user.id, publicUrl);

      // Step 5: Update Supabase profiles table
      await _client
          .from('profiles')
          .update({
            'avatar_url': publicUrl,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('supabase_user_id', user.id);

      return publicUrl;
    } catch (firebaseError) {
      // Firebase issue or offline: Picture remains safely in SQLite
      print('⚠️ Firebase Storage upload failed, picture is preserved locally in SQLite: $firebaseError');
      return null;
    }
  }

  /// Checks if the user has an unsynced avatar in SQLite and attempts to upload to Firebase.
  Future<String?> syncPendingAvatar() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      final pending = await ProfileLocalDatabase.instance.getPendingUpload(user.id);
      if (pending == null || pending.localPath == null) return null;

      final file = File(pending.localPath!);
      if (!await file.exists()) return null;

      print('🔄 Attempting to sync pending avatar from SQLite to Firebase Storage...');
      final isPng = file.path.toLowerCase().endsWith('.png');
      final ext = isPng ? 'png' : 'jpg';
      final path = 'avatars/${user.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';

      final storageRef = FirebaseStorage.instance.ref().child(path);
      final metadata = SettableMetadata(
        contentType: isPng ? 'image/png' : 'image/jpeg',
      );

      final uploadTask = await storageRef.putFile(file, metadata);
      final publicUrl = await uploadTask.ref.getDownloadURL();

      await ProfileLocalDatabase.instance.markSynced(
        userId: user.id,
        avatarUrl: publicUrl,
      );

      await SavedAccountsDatabase.instance.updateProfilePicture(user.id, publicUrl);

      await _client
          .from('profiles')
          .update({
            'avatar_url': publicUrl,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('supabase_user_id', user.id);

      print('✅ Pending avatar synced successfully: $publicUrl');
      return publicUrl;
    } catch (e) {
      print('⚠️ Failed to sync pending avatar: $e');
      return null;
    }
  }

  /// Removes the user's avatar from SQLite, cloud storage, and their profile.
  Future<void> deleteAvatar() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AppError(
        'You are signed out. Please log in to continue.',
        type: AppErrorType.auth,
      );
    }

    // 1. Remove from local SQLite database and delete file from disk
    try {
      await ProfileLocalDatabase.instance.deleteAvatar(user.id);
      await SavedAccountsDatabase.instance.updateProfilePicture(user.id, null);
    } catch (e) {
      print('⚠️ Failed to delete local avatar from SQLite: $e');
    }

    // 2. Clear avatar_url in Supabase profiles
    try {
      await _client
          .from('profiles')
          .update({
            'avatar_url': null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('supabase_user_id', user.id);
    } catch (e) {
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }
}
