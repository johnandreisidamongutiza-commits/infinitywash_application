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
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('No authenticated user.');

    await _client
        .from('profiles')
        .update({
          'first_name': firstName,
          'last_name': lastName,
          'phone': phone,
          'email': ?email,
          'address': ?address,
          'landmark': ?landmark,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('supabase_user_id', user.id);
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
