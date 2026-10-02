// Shared test setup for a hermetic Supabase instance.
//
// `Supabase.initialize` normally creates SharedPreferences-backed storages and
// deep-link observers, none of which work in a plugin-less unit test
// environment. This helper initializes Supabase with:
//   * in-memory PKCE storage (no shared_preferences plugin),
//   * no session persistence (no shared_preferences plugin),
//   * no deep-link observer (no app_links plugin),
//   * no auto token refresh (no pending timers in widget tests).
//
// Call `initializeTestSupabase()` in `setUpAll` and `disposeTestSupabase()` in
// `tearDownAll`.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// In-memory stand-in for the shared_preferences-backed PKCE storage.
class InMemoryGotrueAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> getItem({required String key}) async => _store[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _store[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _store.remove(key);
  }
}

/// Initializes a Supabase instance that requires no platform plugins.
Future<void> initializeTestSupabase({
  String url = 'https://example.supabase.co',
  String publishableKey = 'test-publishable-key',
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: url,
    publishableKey: publishableKey,
    authOptions: FlutterAuthClientOptions(
      persistSession: false,
      detectSessionInUri: false,
      autoRefreshToken: false,
      pkceAsyncStorage: InMemoryGotrueAsyncStorage(),
    ),
  );
}

/// Disposes the hermetic Supabase instance, if initialized.
Future<void> disposeTestSupabase() async {
  if (Supabase.instance.isInitialized) {
    await Supabase.instance.dispose();
  }
}
