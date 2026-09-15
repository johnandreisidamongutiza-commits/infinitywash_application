import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  // Get the Supabase client instance
  static SupabaseClient get client => Supabase.instance.client;
  
  // Get the current user
  static User? get currentUser => client.auth.currentUser;
  
  // Check if user is logged in
  static bool get isLoggedIn => currentUser != null;
  
  // Get auth stream to listen for auth state changes
  static Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;
}
