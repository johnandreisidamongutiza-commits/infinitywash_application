import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'config/supabase_config.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'services/cache/route_cache_service.dart';
import 'services/cache/job_cache_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive for local caching
  try {
    await Hive.initFlutter();
    print('✅ Hive cache initialized');
  } catch (e) {
    print('❌ Hive initialization error: $e');
  }
  
  // Initialize cache services
  try {
    await RouteCacheService.init();
    await JobCacheService.init();
    print('✅ Cache services initialized');
  } catch (e) {
    print('❌ Cache services initialization error: $e');
  }
  
  // Initialize Supabase first (required for auth)
  try {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
    print('✅ Supabase initialized successfully');
  } catch (e) {
    print('❌ Supabase initialization error: $e');
  }
  
  // Initialize Firebase (for notifications)
  // If this fails, the app will still work but notifications will be empty
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase initialized successfully');
    print('✅ Firebase app name: ${Firebase.app().name}');
  } catch (e) {
    print('❌ Firebase initialization error: $e');
    print('⚠️ App will run but notifications will not work');
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
      // Start with splash screen for auto-login check
      home: const SplashScreen(),
    );
  }
}