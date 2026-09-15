import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class AuthService {
  final _auth = SupabaseService.client.auth;

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
  }) async {
    try {
      final response = await _auth.signInWithPassword(
        email: email,
        password: password,
      );
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
}
