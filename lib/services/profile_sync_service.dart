import 'supabase_service.dart';

/// Service to sync profiles between Supabase Auth and profiles table
class ProfileSyncService {
  final _client = SupabaseService.client;
  
  /// Create a profile for the currently logged-in user if it doesn't exist
  Future<bool> ensureCurrentUserProfile() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        print('❌ No user logged in');
        return false;
      }
      
      print('🔍 Checking profile for user: ${user.email}');
      
      // Check if profile exists
      final existingProfile = await _client
          .from('profiles')
          .select('id')
          .eq('supabase_user_id', user.id)
          .maybeSingle();
      
      if (existingProfile != null) {
        print('✅ Profile already exists');
        return true;
      }
      
      print('⚠️ Profile missing, creating...');
      
      // Get user metadata
      final metadata = user.userMetadata ?? {};
      final now = DateTime.now().toIso8601String();
      
      // Create profile
      await _client.from('profiles').insert({
        'id': user.id,
        'supabase_user_id': user.id,
        'email': user.email,
        'first_name': metadata['first_name'] ?? 'User',
        'last_name': metadata['last_name'] ?? '',
        'phone': metadata['phone'] ?? user.phone ?? '',
        'address': metadata['address'] ?? '',
        'landmark': metadata['landmark'] ?? '',
        'role': metadata['role'] ?? 'customer',
        'status': 'active',
        'created_at': now,
        'updated_at': now,
      });
      
      print('✅ Profile created successfully!');
      return true;
    } catch (e) {
      print('❌ Error ensuring profile: $e');
      return false;
    }
  }
  
  /// Create profile for a specific email (useful for admin/testing)
  Future<bool> createProfileForEmail(String email, {
    String? firstName,
    String? lastName,
    String? phone,
    String role = 'customer',
  }) async {
    try {
      print('🔍 Looking for auth user with email: $email');
      
      // Note: This requires the user to be logged in as that user
      // or requires admin access via Edge Function
      final user = _client.auth.currentUser;
      
      if (user == null || user.email?.toLowerCase() != email.toLowerCase()) {
        print('❌ Please log in as $email first');
        return false;
      }
      
      // Check if profile exists
      final existingProfile = await _client
          .from('profiles')
          .select('id')
          .eq('supabase_user_id', user.id)
          .maybeSingle();
      
      if (existingProfile != null) {
        print('✅ Profile already exists');
        return true;
      }
      
      final now = DateTime.now().toIso8601String();
      
      // Create profile
      await _client.from('profiles').insert({
        'id': user.id,
        'supabase_user_id': user.id,
        'email': email,
        'first_name': firstName ?? 'User',
        'last_name': lastName ?? '',
        'phone': phone ?? '',
        'address': '',
        'landmark': '',
        'role': role,
        'status': 'active',
        'created_at': now,
        'updated_at': now,
      });
      
      print('✅ Profile created for $email');
      return true;
    } catch (e) {
      print('❌ Error creating profile: $e');
      return false;
    }
  }
  
  /// Check all auth users and list which ones are missing profiles
  Future<void> debugCheckMissingProfiles() async {
    try {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🔍 PROFILE SYNC DEBUG');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      
      // Get current user
      final currentUser = _client.auth.currentUser;
      print('👤 Current user: ${currentUser?.email ?? "Not logged in"}');
      print('   User ID: ${currentUser?.id ?? "N/A"}');
      
      if (currentUser != null) {
        // Check if current user has profile
        final profile = await _client
            .from('profiles')
            .select('id, email, role, status')
            .eq('supabase_user_id', currentUser.id)
            .maybeSingle();
        
        if (profile == null) {
          print('   ⚠️ MISSING PROFILE!');
          print('   📝 You can create it by calling ensureCurrentUserProfile()');
        } else {
          print('   ✅ Profile exists');
          print('      Email: ${profile['email']}');
          print('      Role: ${profile['role']}');
          print('      Status: ${profile['status']}');
        }
      }
      
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    } catch (e) {
      print('❌ Debug check failed: $e');
    }
  }
}
