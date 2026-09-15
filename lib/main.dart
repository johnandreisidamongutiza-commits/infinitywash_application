import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'theme/app_theme.dart';
import 'screens/role_selection_screen.dart';
// For testing Supabase auth

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Initialize Supabase
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
    print('✅ Supabase initialized successfully');
  } catch (e) {
    print('❌ Supabase initialization error: $e');
  }
  
  runApp(const InfinityWashApp());
}

class InfinityWashApp extends StatelessWidget {
  const InfinityWashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Infinity Wash',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // Toggle between these two screens to test:
      home: const RoleSelectionScreen(), // Your normal app
      // home: const TestLoginScreen(),   // Uncomment to test Supabase auth
    );
  }
}