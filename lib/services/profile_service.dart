import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class ProfileService {
  final SupabaseClient _client = SupabaseService.client;

  Future<Map<String, dynamic>> getProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('No authenticated user.');

    final profile = await _client
        .from('profiles')
        .select()
        .eq('supabase_user_id', user.id)
        .single();
    return profile;
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
    if (user == null) throw Exception('No authenticated user.');

    // Pin values to persist: explicit coordinates, or NULL when removePin
    // is set (customer cleared their pin). Omitted entirely when neither is
    // provided so unrelated saves don't touch the pin.
    final pinColumns = <String, dynamic>{
      if (pinLatitude != null) 'pin_latitude': pinLatitude,
      if (pinLongitude != null) 'pin_longitude': pinLongitude,
      if (removePin) ...{'pin_latitude': null, 'pin_longitude': null},
    };

    // Base payload for core fields
    final basePayload = <String, dynamic>{
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
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
        rethrow;
      }
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
    await _client
        .from('employees')
        .update({
          'name': name,
          'phone': phone,
          'vehicle_details': ?vehicleDetails,
          'delivery_zones': ?deliveryZones,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('profile_id', profileId);
  }
}
