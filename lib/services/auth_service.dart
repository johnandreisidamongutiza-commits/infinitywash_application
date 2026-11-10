import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_error.dart';
import 'supabase_service.dart';
import 'secure_storage_service.dart';
import 'saved_accounts_db.dart';
import 'customer_service.dart';
import 'push_notification_service.dart';
import '../models/saved_account.dart';
import 'legal_service.dart';

class AuthService {
  final _auth = SupabaseService.client.auth;
  final _secureStorage = SecureStorageService.instance;
  final _savedAccountsDb = SavedAccountsDatabase.instance;

  // Sign up with email and password
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? phone,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final response = await _auth.signUp(
        email: email,
        password: password,
        data: metadata,
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  Future<AuthResponse> registerCustomer({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
    required String address,
    required String landmark,
    double? latitude,
    double? longitude,

    /// Consent evidence built by [LegalService.registrationAcceptances].
    /// Read and enforced by handle_new_auth_user(), which writes the
    /// legal_acceptances rows and refuses the registration when a
    /// required document is missing.
    required List<Map<String, String>> legalAcceptances,

    /// Build version stamped on the acceptance rows. Built by
    /// [LegalService.appVersion].
    required String? appVersion,
  }) async {
    final metadata = {
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      'address': address,
      'landmark': landmark,
      'role': 'customer',
      // Optional map pin picked during registration.
      // Omitted (not empty) when the customer skips it so the
      // DB trigger stores NULL instead of failing to parse.
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,

      // Legal consent (Terms of Service + Privacy Policy).
      // handle_new_auth_user() rejects the sign-up if a required
      // document is absent, so this is what makes acceptance stick.
      'legal_acceptances': legalAcceptances,

      // Recorded on each acceptance row so we can prove WHICH build
      // showed the user the document text.
      'app_version': appVersion,
    };

    // Don't pass phone to signUp - it's for SMS auth, not user data
    // Phone is included in metadata instead
    final response = await signUp(
      email: email,
      password: password,
      metadata: metadata,
    );

    // NOTE: Profile and customer creation now handled by database trigger
    // No need to call _saveCustomerProfile here
    print('✅ Registration complete - trigger created profile + customer');

    return response;
  }

  Future<void> ensureCustomerProfileFromMetadata() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final metadata = user.userMetadata ?? <String, dynamic>{};
    if (metadata['role'] != 'customer') return;

    await _saveCustomerProfile(user, user.email ?? '', metadata);
  }

  /// Saves the account using the app's existing remember-me storage.
  /// For Google sign-in users, only account metadata is saved (no credentials),
  /// so auto-login is not available — the user will see their account card
  /// and need to tap "Continue with Google" again.
  Future<void> rememberCurrentSession() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _saveRememberMeData(
      user: user,
      email: user.email ?? '',
    );
  }

  /// Completes the customer data required before a Google-authenticated
  /// account can be routed to ordering screens.
  Future<void> completeCustomerProfile({
    required String firstName,
    required String lastName,
    required String phone,
    required String address,
    required String landmark,
  }) async {
    final user = _auth.currentUser;
    if (user == null)
      throw StateError('Sign in before completing your profile.');
    final metadata = <String, dynamic>{
      ...?user.userMetadata,
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      'address': address,
      'landmark': landmark,
      'role': 'customer',
    };
    await _auth.updateUser(UserAttributes(data: metadata));
    final updatedUser = _auth.currentUser;
    if (updatedUser == null)
      throw StateError('Your sign-in expired. Please try again.');
    await _saveCustomerProfile(updatedUser, updatedUser.email ?? '', metadata);
    final profile = await SupabaseService.client
        .from('profiles')
        .select('id, address, landmark, first_name, last_name, phone, email')
        .eq('supabase_user_id', updatedUser.id)
        .single();
    await _syncCustomerRecord(profile, updatedUser.email ?? '');
  }

  Future<bool> isCustomerProfileComplete() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final profile = await SupabaseService.client
        .from('profiles')
        .select('role, status, first_name, last_name, phone, address')
        .eq('supabase_user_id', user.id)
        .maybeSingle();
    if (profile == null ||
        profile['role'] != 'customer' ||
        profile['status'] != 'active')
      return false;
    for (final key in ['first_name', 'last_name', 'phone', 'address']) {
      if ((profile[key] as String? ?? '').trim().isEmpty) return false;
    }
    return LegalService().hasAcceptedCurrentVersions(user.id);
  }

  Future<void> _saveCustomerProfile(
    User user,
    String email,
    Map<String, dynamic> metadata,
  ) async {
    final now = DateTime.now().toIso8601String();
    final client = SupabaseService.client;

    // Step 1: Create or update profile
    final profile = await client
        .from('profiles')
        .select('id')
        .eq('supabase_user_id', user.id)
        .maybeSingle();

    final profileData = {
      'supabase_user_id': user.id,
      'first_name': metadata['first_name'],
      'last_name': metadata['last_name'],
      'email': email,
      'phone': metadata['phone'],
      'address': metadata['address'],
      'landmark': metadata['landmark'],
      if (metadata['latitude'] is num)
        'pin_latitude': (metadata['latitude'] as num).toDouble(),
      if (metadata['longitude'] is num)
        'pin_longitude': (metadata['longitude'] as num).toDouble(),
      'role': 'customer',
      'status': 'active',
      'updated_at': now,
    };

    String profileId;
    if (profile == null) {
      final newProfile = await client
          .from('profiles')
          .insert({'id': user.id, ...profileData, 'created_at': now})
          .select('id')
          .single();
      profileId = newProfile['id'] as String;
      print('✅ Profile created: $profileId');
    } else {
      await client.from('profiles').update(profileData).eq('id', profile['id']);
      profileId = profile['id'] as String;
      print('✅ Profile updated: $profileId');
    }

    // Step 2: Create or update customer record with address and landmark
    // NOTE: Customer creation is now handled by database trigger during registration
    // This code only runs for updates and sign-ins (not during initial registration)
    try {
      final existingCustomer = await client
          .from('customers')
          .select('id, address, landmark')
          .eq('profile_id', profileId)
          .maybeSingle();

      final address = metadata['address'] as String? ?? '';
      final landmark = metadata['landmark'] as String? ?? '';

      if (existingCustomer == null) {
        // Customer doesn't exist yet (shouldn't happen - trigger should create it)
        // Skip creation here, let trigger handle it
        print(
          'ℹ️ Customer not found - trigger should create it during registration',
        );
      } else {
        // Update existing customer with address and landmark
        final existingAddress = existingCustomer['address'] as String? ?? '';
        final existingLandmark = existingCustomer['landmark'] as String? ?? '';

        // Only update if address is empty or different
        if (existingAddress.isEmpty ||
            existingLandmark.isEmpty ||
            existingAddress != address ||
            existingLandmark != landmark) {
          await client
              .from('customers')
              .update({
                'first_name': metadata['first_name'],
                'last_name': metadata['last_name'],
                'phone': metadata['phone'],
                'email': email,
                'address': address,
                'landmark': landmark,
                if (metadata['latitude'] is num)
                  'pin_latitude': (metadata['latitude'] as num).toDouble(),
                if (metadata['longitude'] is num)
                  'pin_longitude': (metadata['longitude'] as num).toDouble(),
                'updated_at': now,
              })
              .eq('id', existingCustomer['id']);

          print(
            '✅ Customer updated with address: "$address" and landmark: "$landmark"',
          );
        } else {
          print('ℹ️ Customer already has correct address and landmark');
        }
      }
    } catch (e) {
      print('⚠️ Error creating/updating customer record: $e');
      // Don't fail the registration if customer creation fails
      // The profile is created successfully, customer can be synced later
    }
  }

  /// Validate account status and throw exception if deactivated
  /// This is called after Supabase authentication succeeds
  Future<void> _validateAccountStatus(String userId) async {
    try {
      print('🔒 Validating account status for user: $userId');

      // Try to query with deactivation_reason first (after migration)
      // Fall back to without it if column doesn't exist (before migration)
      Map<String, dynamic>? profile;

      try {
        profile = await SupabaseService.client
            .from('profiles')
            .select('status, deactivation_reason, role, email')
            .eq('supabase_user_id', userId)
            .maybeSingle();
      } catch (e) {
        // If column doesn't exist, query without deactivation_reason
        if (e.toString().contains('42703') ||
            e.toString().contains('deactivation_reason does not exist')) {
          print('⚠️ deactivation_reason column not found, querying without it');
          profile = await SupabaseService.client
              .from('profiles')
              .select('status, role, email')
              .eq('supabase_user_id', userId)
              .maybeSingle();
        } else {
          rethrow;
        }
      }

      if (profile == null) {
        print('❌ Profile not found for user: $userId');
        throw AppError(
          'We could not find your account profile. Please contact support.',
          type: AppErrorType.auth,
        );
      }

      final status = (profile['status'] as String?)?.toLowerCase() ?? '';
      final role = profile['role'] as String? ?? 'user';
      final email = profile['email'] as String? ?? '';
      final reason = profile['deactivation_reason'] as String?;

      print('🔒 Account status: $status, role: $role, email: $email');
      print('🔒 Deactivation reason from DB: "${reason ?? "NULL"}"');
      print('🔒 Reason is null: ${reason == null}');
      print('🔒 Reason is empty: ${reason?.isEmpty ?? true}');
      print('🔒 Profile keys: ${profile.keys.toList()}');

      if (status == 'deactivated') {
        // Sign out immediately
        await _auth.signOut();

        print(
          '❌ Account deactivated. Reason: ${reason ?? "No reason provided"}',
        );

        // Throw a specific exception with the reason
        if (reason != null && reason.trim().isNotEmpty) {
          throw Exception('ACCOUNT_DEACTIVATED:$reason');
        } else {
          throw Exception(
            'ACCOUNT_DEACTIVATED:No reason provided. Please contact support for more information.',
          );
        }
      } else if (status == 'archived') {
        // Archived accounts are also blocked
        await _auth.signOut();
        print('❌ Account archived');
        throw Exception(
          'ACCOUNT_DEACTIVATED:This account has been archived. Please contact support.',
        );
      } else if (status != 'active') {
        // Any other non-active status
        await _auth.signOut();
        print('❌ Account status invalid: $status');
        throw Exception(
          'ACCOUNT_DEACTIVATED:Account status is invalid. Please contact support.',
        );
      }

      print('✅ Account status valid: $status');
    } catch (e) {
      // If it's already our exception, rethrow it
      if (e.toString().contains('ACCOUNT_DEACTIVATED:')) {
        rethrow;
      }
      // Otherwise map network/offline failures to a friendly message.
      print('❌ Error validating account status: $e');
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  // Sign in with email and password
  Future<AuthResponse> signIn({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    try {
      final response = await _auth.signInWithPassword(
        email: email,
        password: password,
      );

      // After successful login, ensure profile exists
      if (response.user != null) {
        await _ensureProfileExists(response.user!);

        // Validate account status BEFORE allowing login
        await _validateAccountStatus(response.user!.id);

        // Register this device for push notifications (every signed-in user).
        // Fire-and-forget: never blocks or fails the login.
        PushNotificationService.instance.initializeForCurrentUser();
      }

      // If remember me is enabled and login successful, save the account and credentials
      if (rememberMe && response.user != null && response.session != null) {
        await _saveRememberMeData(
          user: response.user!,
          email: email,
          password: password,
        );
      } else if (response.user != null) {
        // When not saving the account, clear any previous auto-login marker
        await _secureStorage.clearLastAutoLoginUser();
      }

      return response;
    } catch (e) {
      // Map Supabase auth errors (bad credentials, unconfirmed email,
      // rate limits) and network failures to friendly, typed errors.
      if (e is AppError) rethrow;
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  /// Ensure a profile exists for the user, create if missing
  /// Also ensures customer record is synced with profile data
  Future<void> _ensureProfileExists(User user) async {
    try {
      // Check if profile exists
      final profile = await SupabaseService.client
          .from('profiles')
          .select(
            'id, role, address, landmark, first_name, last_name, phone, email',
          )
          .eq('supabase_user_id', user.id)
          .maybeSingle();

      if (profile != null) {
        print('✅ Profile exists for ${user.email}');

        // If this is a customer profile, ensure customer record exists with address
        final role = profile['role'] as String? ?? '';
        if (role.toLowerCase() == 'customer') {
          await _syncCustomerRecord(profile, user.email ?? '');
        }

        return;
      }

      print('⚠️ Profile missing for ${user.email}, creating...');

      // Create profile from user metadata
      final metadata = user.userMetadata ?? {};
      final now = DateTime.now().toIso8601String();

      await SupabaseService.client.from('profiles').insert({
        'id': user.id,
        'supabase_user_id': user.id,
        'email': user.email ?? '',
        'first_name': metadata['first_name'] ?? 'User',
        'last_name': metadata['last_name'] ?? '',
        'phone': metadata['phone'] ?? user.phone ?? '',
        'address': metadata['address'] ?? '',
        'landmark': metadata['landmark'] ?? '',
        if (metadata['latitude'] is num)
          'pin_latitude': (metadata['latitude'] as num).toDouble(),
        if (metadata['longitude'] is num)
          'pin_longitude': (metadata['longitude'] as num).toDouble(),
        'role': metadata['role'] ?? 'customer',
        'status': 'active',
        'created_at': now,
        'updated_at': now,
      });

      print('✅ Profile created automatically on login');

      // Create customer record if role is customer
      if ((metadata['role'] ?? 'customer') == 'customer') {
        await _saveCustomerProfile(user, user.email ?? '', metadata);
      }
    } catch (e) {
      print('⚠️ Could not auto-create profile: $e');
      // Don't fail the login if profile creation fails
    }
  }

  /// Sync customer record with profile data (for existing users with empty address)
  Future<void> _syncCustomerRecord(
    Map<String, dynamic> profile,
    String email,
  ) async {
    try {
      final profileId = profile['id'] as String;
      final address = profile['address'] as String? ?? '';
      final landmark = profile['landmark'] as String? ?? '';

      // Check if customer record exists
      final customer = await SupabaseService.client
          .from('customers')
          .select('id, address, landmark')
          .eq('profile_id', profileId)
          .maybeSingle();

      if (customer == null) {
        // No customer record exists, create one using idempotent method
        print('⚠️ Customer record missing, creating from profile...');

        final customerService = CustomerService();
        await customerService.createOrGetCustomerForProfile(
          profileId: profileId,
          firstName: profile['first_name'] as String,
          lastName: profile['last_name'] as String?,
          phone: profile['phone'] as String?,
          email: email,
          address: address,
          landmark: landmark,
          customerType: 'mobile_app',
        );

        print('✅ Customer record created/verified with address from profile');
      } else {
        // Customer exists, check if address needs updating
        final customerAddress = customer['address'] as String? ?? '';
        final customerLandmark = customer['landmark'] as String? ?? '';

        // If customer address is empty but profile has address, sync it
        if ((customerAddress.isEmpty || customerLandmark.isEmpty) &&
            address.isNotEmpty) {
          print('⚠️ Customer address empty, syncing from profile...');

          await SupabaseService.client
              .from('customers')
              .update({
                'address': address,
                'landmark': landmark,
                'first_name': profile['first_name'],
                'last_name': profile['last_name'],
                'phone': profile['phone'],
                'email': email,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', customer['id']);

          print('✅ Customer address synced from profile: "$address"');
        }
      }
    } catch (e) {
      print('⚠️ Error syncing customer record: $e');
      // Don't fail the login
    }
  }

  /// Discover the authenticated user's active role from the backend.
  ///
  /// Returns 'customer', 'staff', 'rider', 'admin' or 'superadmin' when the
  /// account has an active profile (for staff/rider an active employee record
  /// matching the role is also required). Returns null when no active role can
  /// be determined, or when the lookup fails — callers must treat null as
  /// "not authorized" and sign the user out.
  Future<String?> getUserRole() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final client = SupabaseService.client;
      final profile = await client
          .from('profiles')
          .select('id, role, status')
          .eq('supabase_user_id', user.id)
          .maybeSingle();

      if (profile == null) return null;

      final profileStatus = (profile['status'] as String?)?.toLowerCase() ?? '';
      if (profileStatus != 'active') return null;

      final role = (profile['role'] as String?)?.toLowerCase() ?? '';
      if (role.isEmpty) return null;

      // Staff and riders must also have an active employee record that matches.
      if (role == 'staff' || role == 'rider') {
        final employee = await client
            .from('employees')
            .select('role, status')
            .eq('profile_id', profile['id'])
            .maybeSingle();

        if (employee == null) return null;

        final employeeRole = (employee['role'] as String?)?.toLowerCase() ?? '';
        final employeeStatus =
            (employee['status'] as String?)?.toLowerCase() ?? '';

        if (employeeRole != role || employeeStatus != 'active') return null;
      }

      return role;
    } catch (e) {
      print('❌ Error discovering user role: $e');
      return null;
    }
  }

  // Sign out
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {
    try {
      await _secureStorage.clearLastAutoLoginUser();
      await _auth.signOut(scope: scope);
    } catch (e) {
      // Signing out locally should never hard-fail the UI; log and continue.
      print('⚠️ Sign out error (continuing): $e');
    }
  }

  /// Logs out the user from their current active session.
  ///
  /// - Unregisters push notifications for the current user.
  /// - Clears the last auto-login user marker so subsequent app launches
  ///   will show the saved accounts screen (or login screen) instead of
  ///   automatically bypassing it.
  /// - Signs out from Supabase globally. Saved credentials remain in secure
  ///   storage so the account card can re-authenticate on next tap.
  Future<void> logout() async {
    try {
      PushNotificationService.instance.unregisterCurrentUser();
      await _secureStorage.clearLastAutoLoginUser();
      await _auth.signOut(scope: SignOutScope.global);
    } catch (e) {
      print('⚠️ Logout error (continuing): $e');
    }
  }

  // Get current user
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  // Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _auth.resetPasswordForEmail(email);
    } catch (e) {
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  // Note: The new password reset flow uses PasswordResetService
  // which integrates with the password_reset_tokens table
  // See password_reset_service.dart for the complete implementation

  // Update password (requires current session)
  Future<UserResponse> updatePassword(String newPassword) async {
    try {
      final response = await _auth.updateUser(
        UserAttributes(password: newPassword),
      );
      return response;
    } catch (e) {
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  /// Re-authenticate and change the password through the rate-limited server
  /// endpoint. This keeps password changes under one server-side policy.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = _auth.currentUser;
      final email = user?.email;
      if (user == null || email == null) {
        throw const AppError(
          'You are signed out. Please log in and try again.',
          type: AppErrorType.auth,
        );
      }
      final result = await SupabaseService.client.functions.invoke(
        'change-password',
        body: {
          'email': email,
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
      if (result.data is Map && (result.data as Map)['ok'] == true) return;
      throw const AppError(
        'Password change failed. Please try again.',
        type: AppErrorType.server,
      );
    } on FunctionException catch (e) {
      final detail = e.details;
      final message = detail is Map && detail['error'] is String
          ? detail['error'] as String
          : 'Password change failed. Please try again.';
      throw AppError(message, type: AppErrorType.server, originalError: e);
    } catch (e) {
      if (e is AppError) rethrow;
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  // Update user metadata
  Future<UserResponse> updateUserMetadata(Map<String, dynamic> metadata) async {
    try {
      final response = await _auth.updateUser(UserAttributes(data: metadata));
      return response;
    } catch (e) {
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  // Listen to auth state changes
  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  /// Keep the app's secure per-account token cache in step with Supabase token
  /// rotation. With credential-based auto-login this is no longer needed,
  /// but kept as a no-op stub so callers do not break.
  static void initializeSessionPersistence() {
    // No-op: credential-based auto-login does not need session tracking.
  }

  // ==================== Remember Me Functionality ====================

  // Save remember me data (account info + credentials)
  Future<void> _saveRememberMeData({
    required User user,
    required String email,
    String? password,
  }) async {
    try {
      print('🔐 REMEMBER ME: Starting save process...');
      print('🔐 User ID: ${user.id}');
      print('🔐 Email: $email');

      // Fetch profile data to get name
      final profile = await SupabaseService.client
          .from('profiles')
          .select('first_name, last_name')
          .eq('supabase_user_id', user.id)
          .maybeSingle();

      print('🔐 Profile data fetched: ${profile != null ? "Yes" : "No"}');

      final firstName = profile?['first_name'] as String?;
      final lastName = profile?['last_name'] as String?;

      print('🔐 User name: ${firstName ?? "N/A"} ${lastName ?? "N/A"}');

      // Create saved account
      final savedAccount = SavedAccount(
        id: user.id,
        email: email,
        firstName: firstName,
        lastName: lastName,
        profilePictureUrl: null, // Can be extended later
        lastLoginDate: DateTime.now(),
      );

      // Save account to database
      await _savedAccountsDb.saveAccount(savedAccount);
      print('✅ REMEMBER ME: Account saved to SQLite database');

      // Save credentials to secure storage (email/password login only)
      if (password != null) {
        await _secureStorage.saveCredentials(
          userId: user.id,
          email: email,
          password: password,
        );
        print('✅ REMEMBER ME: Credentials saved to secure storage');
      } else {
        print('ℹ️ REMEMBER ME: No password (OAuth user) — account saved without credentials');
      }

      // Save as last auto-login user
      await _secureStorage.saveLastAutoLoginUser(user.id);
      print('✅ REMEMBER ME: Set as last auto-login user');
      print('✅ REMEMBER ME: Save process completed successfully!');
    } catch (e) {
      // Don't fail the login if remember me fails
      print('❌ REMEMBER ME ERROR: $e');
      print('❌ Stack trace: ${StackTrace.current}');
    }
  }

  // Try to auto-login with saved credentials
  Future<AuthResponse?> tryAutoLogin({String? userId}) async {
    try {
      print('🔄 AUTO-LOGIN: Starting auto-login process...');

      // Get user ID - either provided or last auto-login user
      final targetUserId =
          userId ?? await _secureStorage.getLastAutoLoginUser();
      print('🔄 Target User ID: $targetUserId');

      if (targetUserId == null) {
        print('❌ AUTO-LOGIN: No saved user ID found');
        return null;
      }

      // Check if we have saved credentials for this user
      final credentials = await _secureStorage.getCredentials(targetUserId);

      if (credentials == null) {
        print('❌ AUTO-LOGIN: No saved credentials found');
        // Clean up orphaned account entry
        await _removeRememberMeData(targetUserId);
        return null;
      }

      print('🔄 AUTO-LOGIN: Saved credentials found, signing in...');

      try {
        final response = await _auth.signInWithPassword(
          email: credentials.email,
          password: credentials.password,
        );

        if (response.user == null) {
          print('❌ AUTO-LOGIN: Sign-in returned no user');
          await _removeRememberMeData(targetUserId);
          return null;
        }

        print('✅ AUTO-LOGIN: Signed in successfully');

        // Validate account status before allowing access
        try {
          await _validateAccountStatus(response.user!.id);
        } catch (e) {
          print('❌ AUTO-LOGIN: Account validation failed - $e');
          await _removeRememberMeData(targetUserId);
          return null;
        }

        await _secureStorage.saveLastAutoLoginUser(targetUserId);
        await _savedAccountsDb.updateLastLogin(targetUserId);
        // Register push for auto-logged-in users too (fire-and-forget).
        PushNotificationService.instance.initializeForCurrentUser();
        return response;
      } on AuthException catch (e) {
        print('❌ AUTO-LOGIN: Auth error - ${e.message}');
        // Invalid credentials (password changed, account deleted, etc.)
        // Remove saved data so the user is prompted to sign in again.
        if (e is! AuthRetryableFetchException) {
          await _removeRememberMeData(targetUserId);
        }
        return null;
      }
    } catch (e) {
      print('❌ AUTO-LOGIN ERROR: $e');
      return null;
    }
  }

  // Get all saved accounts
  Future<List<SavedAccount>> getSavedAccounts() async {
    return await _savedAccountsDb.getAllAccounts();
  }

  Future<bool> isAccountSaved(String userId) async {
    return await _savedAccountsDb.getAccountById(userId) != null;
  }

  // Remove remember me data for a user
  Future<void> _removeRememberMeData(String userId) async {
    try {
      await _secureStorage.deleteCredentials(userId);
      await _secureStorage.deleteUserTokens(userId);
      await _savedAccountsDb.deleteAccount(userId);
      if (await _secureStorage.getLastAutoLoginUser() == userId) {
        await _secureStorage.clearLastAutoLoginUser();
      }
    } catch (e) {
      print('Failed to remove remember me data: $e');
    }
  }

  // Remove a saved account (called when user explicitly removes it)
  Future<void> removeSavedAccount(String userId) async {
    await _removeRememberMeData(userId);

    // If this was the last auto-login user, clear that reference
    final lastAutoLogin = await _secureStorage.getLastAutoLoginUser();
    if (lastAutoLogin == userId) {
      await _secureStorage.clearLastAutoLoginUser();
    }
  }

  // Clear all saved accounts
  Future<void> clearAllSavedAccounts() async {
    try {
      await _savedAccountsDb.clearAllAccounts();
      await _secureStorage.clearAllCredentials();
      await _secureStorage.clearAllTokens();
      await _secureStorage.clearLastAutoLoginUser();
    } catch (e) {
      print('Failed to clear all saved accounts: $e');
    }
  }

  // Check if a user has saved credentials
  Future<bool> hasSavedSession(String userId) async {
    return await _secureStorage.hasSavedCredentials(userId);
  }
}
