import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/supabase_service.dart';

/// Test script to disable/enable trigger and test registration
Future<void> testTrigger() async {
  try {
    print('🔧 Step 1: Disabling trigger...');
    await SupabaseService.client.rpc('exec_sql', params: {
      'query': 'ALTER TABLE auth.users DISABLE TRIGGER on_auth_user_created'
    });
    print('✅ Trigger disabled');
    
    print('\n📝 Now try registering a test user in the app');
    print('After testing, run this script again with enable=true to re-enable');
    
  } catch (e) {
    print('❌ Error: $e');
    print('\nTrying alternative approach - direct SQL execution may not work from app');
    print('You need to run this SQL directly in Supabase SQL Editor:');
    print('ALTER TABLE auth.users DISABLE TRIGGER on_auth_user_created;');
  }
}

void main() async {
  await testTrigger();
}
