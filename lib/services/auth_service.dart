import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'secure_storage_service.dart';
import 'saved_accounts_db.dart';
import '../models/saved_account.dart';

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
        phone: phone,
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
  }) async {
    final metadata = {
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      'address': address,
      'landmark': landmark,
      'role': 'customer',
    };

    final response = await signUp(
      email: email,
      password: password,
      phone: phone,
      metadata: metadata,
    );

    if (response.user != null && response.session != null) {
      await _saveCustomerProfile(response.user!, email, metadata);
    }

    return response;
  }

  Future<void> ensureCustomerProfileFromMetadata() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final metadata = user.userMetadata ?? <String, dynamic>{};
    if (metadata['role'] != 'customer') return;

    await _saveCustomerProfile(user, user.email ?? '', metadata);
  }

  Future<void> _saveCustomerProfile(
    User user,
    String email,
    Map<String, dynamic> metadata,
  ) async {
    final now = DateTime.now().toIso8601String();
    final client = SupabaseService.client;
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
      'role': 'customer',
      'status': 'active',
      'updated_at': now,
    };

    if (profile == null) {
      await client.from('profiles').insert({
        'id': user.id,
        ...profileData,
        'created_at': now,
      });
    } else {
      await client.from('profiles').update(profileData).eq('id', profile['id']);
    }
  }

  // Sign in with email and password
  Future<AuthResponse> signIn({
    required String email,
    required String password,
    bool rememberMe = false,
    String? role,
  }) async {
    try {
      final response = await _auth.signInWithPassword(
        email: email,
        password: password,
      );

      // If remember me is enabled and login successful, save the account and tokens
      if (rememberMe && response.user != null && response.session != null) {
        await _saveRememberMeData(
          user: response.user!,
          session: response.session!,
          email: email,
          role: role,
        );
      }

      return response;
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> hasActiveRole(String role) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final profile = await SupabaseService.client
        .from('profiles')
        .select('role, status')
        .eq('supabase_user_id', user.id)
        .maybeSingle();

    if (profile == null) return false;

    final profileRole = (profile['role'] as String?)?.toLowerCase();
    final profileStatus = (profile['status'] as String?)?.toLowerCase();
    return profileRole == role.toLowerCase() && profileStatus == 'active';
  }

  Future<bool> hasActiveEmployeeRole(String role) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final client = SupabaseService.client;
    final profile = await client
        .from('profiles')
        .select('id, role, status')
        .eq('supabase_user_id', user.id)
        .maybeSingle();

    if (profile == null ||
        (profile['role'] as String?)?.toLowerCase() != role.toLowerCase() ||
        (profile['status'] as String?)?.toLowerCase() != 'active') {
      return false;
    }

    final employee = await client
        .from('employees')
        .select('role, status, profile_id')
        .eq('profile_id', profile['id'])
        .maybeSingle();

    if (employee == null) return false;

    return (employee['role'] as String?)?.toLowerCase() == role.toLowerCase() &&
        (employee['status'] as String?)?.toLowerCase() == 'active';
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      rethrow;
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
      rethrow;
    }
  }

  // Update password (requires current session)
  Future<UserResponse> updatePassword(String newPassword) async {
    try {
      final response = await _auth.updateUser(
        UserAttributes(password: newPassword),
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  // Update user metadata
  Future<UserResponse> updateUserMetadata(Map<String, dynamic> metadata) async {
    try {
      final response = await _auth.updateUser(
        UserAttributes(data: metadata),
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  // Listen to auth state changes
  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  // ==================== Remember Me Functionality ====================

  // Save remember me data (account info + tokens)
  Future<void> _saveRememberMeData({
    required User user,
    required Session session,
    required String email,
    String? role,
  }) async {
    try {
      print('🔐 REMEMBER ME: Starting save process...');
      print('🔐 User ID: ${user.id}');
      print('🔐 Email: $email');
      print('🔐 Role: $role');
      
      // Fetch profile data to get name and role
      final profile = await SupabaseService.client
          .from('profiles')
          .select('first_name, last_name, role')
          .eq('supabase_user_id', user.id)
          .maybeSingle();

      print('🔐 Profile data fetched: ${profile != null ? "Yes" : "No"}');

      final firstName = profile?['first_name'] as String?;
      final lastName = profile?['last_name'] as String?;
      final userRole = role ?? profile?['role'] as String? ?? 'Customer';

      print('🔐 Using role: $userRole');
      print('🔐 User name: ${firstName ?? "N/A"} ${lastName ?? "N/A"}');

      // Create saved account
      final savedAccount = SavedAccount(
        id: user.id,
        email: email,
        role: userRole,
        firstName: firstName,
        lastName: lastName,
        profilePictureUrl: null, // Can be extended later
        lastLoginDate: DateTime.now(),
      );

      // Save account to database
      await _savedAccountsDb.saveAccount(savedAccount);
      print('✅ REMEMBER ME: Account saved to SQLite database');

      // Save tokens to secure storage
      await _secureStorage.saveAuthTokens(
        userId: user.id,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        expiresAt: session.expiresAt != null 
            ? DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000)
            : null,
      );
      print('✅ REMEMBER ME: Tokens saved to secure storage');

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

  // Try to auto-login with saved session
  Future<AuthResponse?> tryAutoLogin({String? userId}) async {
    try {
      print('🔄 AUTO-LOGIN: Starting auto-login process...');
      
      // Get user ID - either provided or last auto-login user
      final targetUserId = userId ?? await _secureStorage.getLastAutoLoginUser();
      print('🔄 Target User ID: $targetUserId');
      
      if (targetUserId == null) {
        print('❌ AUTO-LOGIN: No saved user ID found');
        return null;
      }

      // Check if we have a valid token
      final hasValidToken = await _secureStorage.isTokenValid(targetUserId);
      print('🔄 Has valid token: $hasValidToken');
      
      if (!hasValidToken) {
        print('❌ AUTO-LOGIN: Token expired or invalid');
        // Token expired or doesn't exist
        await _removeRememberMeData(targetUserId);
        return null;
      }

      // Get the access token
      final accessToken = await _secureStorage.getAccessToken(targetUserId);
      final refreshToken = await _secureStorage.getRefreshToken(targetUserId);
      
      print('🔄 Access token present: ${accessToken != null}');
      print('🔄 Refresh token present: ${refreshToken != null}');
      
      if (accessToken == null) {
        print('❌ AUTO-LOGIN: No access token found');
        return null;
      }

      // Try to restore session with Supabase
      // Note: Supabase Flutter handles session restoration automatically
      // We just need to verify the current session is valid
      final currentSession = _auth.currentSession;
      
      if (currentSession != null && currentSession.user.id == targetUserId) {
        print('✅ AUTO-LOGIN: Session already active');
        // Session is already active
        await _savedAccountsDb.updateLastLogin(targetUserId);
        return AuthResponse(
          user: currentSession.user,
          session: currentSession,
        );
      }

      // If we have a refresh token, try to refresh the session
      if (refreshToken != null) {
        print('🔄 AUTO-LOGIN: Attempting to refresh session...');
        try {
          final response = await _auth.refreshSession(refreshToken);
          if (response.session != null) {
            print('✅ AUTO-LOGIN: Session refreshed successfully');
            // Update stored tokens with new ones
            await _secureStorage.saveAuthTokens(
              userId: targetUserId,
              accessToken: response.session!.accessToken,
              refreshToken: response.session!.refreshToken,
              expiresAt: response.session!.expiresAt != null
                  ? DateTime.fromMillisecondsSinceEpoch(response.session!.expiresAt! * 1000)
                  : null,
            );
            
            await _savedAccountsDb.updateLastLogin(targetUserId);
            return response;
          }
        } catch (e) {
          print('❌ AUTO-LOGIN: Refresh failed - $e');
          // Refresh failed, remove saved data
          await _removeRememberMeData(targetUserId);
          return null;
        }
      }

      print('❌ AUTO-LOGIN: Could not restore session');
      return null;
    } catch (e) {
      print('❌ AUTO-LOGIN ERROR: $e');
      return null;
    }
  }

  // Get all saved accounts
  Future<List<SavedAccount>> getSavedAccounts() async {
    return await _savedAccountsDb.getAllAccounts();
  }

  // Get saved accounts for a specific role
  Future<List<SavedAccount>> getSavedAccountsByRole(String role) async {
    return await _savedAccountsDb.getAccountsByRole(role);
  }

  // Get a specific saved account
  Future<SavedAccount?> getSavedAccount(String email, String role) async {
    return await _savedAccountsDb.getAccount(email, role);
  }

  // Remove remember me data for a user
  Future<void> _removeRememberMeData(String userId) async {
    try {
      await _secureStorage.deleteUserTokens(userId);
      await _savedAccountsDb.deleteAccount(userId);
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
      await _secureStorage.clearAllTokens();
      await _secureStorage.clearLastAutoLoginUser();
    } catch (e) {
      print('Failed to clear all saved accounts: $e');
    }
  }

  // Check if a user has a saved session
  Future<bool> hasSavedSession(String userId) async {
    return await _secureStorage.hasValidSession(userId);
  }
}
