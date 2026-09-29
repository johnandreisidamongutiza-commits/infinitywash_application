import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/supabase_service.dart';

/// Diagnostic tool to test registration with minimal data
Future<void> testRegistration() async {
  final auth = SupabaseService.client.auth;
  
  print('🧪 TEST 1: Minimal registration (no metadata)');
  try {
    final response1 = await auth.signUp(
      email: 'test_minimal_${DateTime.now().millisecondsSinceEpoch}@example.com',
      password: 'test123456',
    );
    print('✅ TEST 1 PASSED: ${response1.user?.id}');
  } catch (e) {
    print('❌ TEST 1 FAILED: $e');
  }

  await Future.delayed(Duration(seconds: 2));

  print('\n🧪 TEST 2: Registration with small metadata');
  try {
    final response2 = await auth.signUp(
      email: 'test_small_${DateTime.now().millisecondsSinceEpoch}@example.com',
      password: 'test123456',
      data: {
        'role': 'customer',
      },
    );
    print('✅ TEST 2 PASSED: ${response2.user?.id}');
  } catch (e) {
    print('❌ TEST 2 FAILED: $e');
  }

  await Future.delayed(Duration(seconds: 2));

  print('\n🧪 TEST 3: Registration with full metadata (actual use case)');
  try {
    final response3 = await auth.signUp(
      email: 'test_full_${DateTime.now().millisecondsSinceEpoch}@example.com',
      password: 'test123456',
      data: {
        'first_name': 'John',
        'last_name': 'Doe',
        'phone': '09123456789',
        'address': '123 Test St, Test City',
        'landmark': 'Near Test Mall',
        'role': 'customer',
      },
    );
    print('✅ TEST 3 PASSED: ${response3.user?.id}');
  } catch (e) {
    print('❌ TEST 3 FAILED: $e');
  }

  print('\n🧪 TEST 4: Check auth configuration');
  try {
    final config = await SupabaseService.client
        .from('auth.config')
        .select()
        .limit(5);
    print('✅ TEST 4 - Auth config: $config');
  } catch (e) {
    print('❌ TEST 4 FAILED: $e');
  }

  print('\n🧪 TEST 5: Check existing test users');
  try {
    final users = await SupabaseService.client
        .from('auth.users')
        .select('id, email, created_at')
        .ilike('email', 'test_%@example.com')
        .limit(10);
    print('✅ TEST 5 - Test users: $users');
  } catch (e) {
    print('❌ TEST 5 FAILED: $e');
  }
}

void main() async {
  print('🚀 Starting Registration Diagnostic Tests...\n');
  
  // Initialize Supabase (you need to call this in your app's main method)
  // await Supabase.initialize(url: 'your-url', anonKey: 'your-key');
  
  await testRegistration();
  
  print('\n✅ All tests completed!');
}
