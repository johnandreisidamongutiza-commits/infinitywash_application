import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'config/supabase_config.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'utils/app_error.dart';
import 'services/connectivity_service.dart';
import 'services/lifecycle_service.dart';
import 'services/auth_service.dart';
import 'services/push_notification_service.dart';
import 'widgets/offline_banner.dart';
import 'services/cache/route_cache_service.dart';
import 'services/cache/job_cache_service.dart';
import 'services/api/api_gate.dart';
import 'screens/splash_screen.dart';

void main() {
  // Catch everything: framework errors, uncaught async errors, and errors
  // escaping zone callbacks. The app must never crash with a red screen.
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      // Keep default console logging for developers.
      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      // ignore: avoid_print
      print('💥 Uncaught platform error: $error');
      _reportGlobalError(error, stack);
      return true; // Error consumed — do not crash.
    };

    _bootstrap();
  }, (error, stack) {
    // ignore: avoid_print
    print('💥 Uncaught zone error: $error');
    _reportGlobalError(error, stack);
  });
}

/// Show a non-fatal dialog for uncaught errors (deduplicated so repeated
/// identical errors don't stack dialogs).
void _reportGlobalError(Object error, StackTrace stack) {
  final context = infinityWashNavigatorKey.currentContext;
  if (context == null || !context.mounted) return;

  final mapped = mapError(error, stackTrace: stack);
  // Network problems are surfaced by screens and the offline banner;
  // showing a dialog too would be noise.
  if (mapped.isNetwork) return;

  _showErrorDialogOnce(context, mapped.message);
}

String? _lastDialogMessage;
DateTime? _lastDialogAt;

void _showErrorDialogOnce(BuildContext context, String message) {
  final now = DateTime.now();
  if (_lastDialogMessage == message &&
      _lastDialogAt != null &&
      now.difference(_lastDialogAt!) < const Duration(seconds: 3)) {
    return; // Same message within 3s — suppress duplicates.
  }
  _lastDialogMessage = message;
  _lastDialogAt = now;

  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.error_outline, color: AppTheme.errorRed),
          SizedBox(width: 10),
          Text('Unexpected error'),
        ],
      ),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK', style: TextStyle(color: AppTheme.accentBlue)),
        ),
      ],
    ),
  ).catchError((Object e) {
    // Navigator not ready yet — the error is already logged.
    return null;
  });
}

Future<void> _bootstrap() async {
  // These startup tasks do not depend on one another. Run them together so
  // the first Flutter frame is not held back by a serial initialization chain.
  await Future.wait<void>([
    _initializeLocalCaches(),
    _initializeConnectivity(),
    _initializeLifecycle(),
    _initializeSupabase(),
    _initializeFirebase(),
  ]);

  runApp(const InfinityWashApp());
}

Future<void> _initializeLocalCaches() async {
  // Initialize Hive for local caching
  try {
    await Hive.initFlutter();
    // ignore: avoid_print
    print('✅ Hive cache initialized');
  } catch (e) {
    // ignore: avoid_print
    print('❌ Hive initialization error: $e');
  }

  // Initialize cache services
  try {
    await RouteCacheService.init();
    await JobCacheService.init();
    await ApiGate.instance.init();
    // ignore: avoid_print
    print('✅ Cache services initialized');
  } catch (e) {
    // ignore: avoid_print
    print('❌ Cache services initialization error: $e');
  }
}

Future<void> _initializeConnectivity() async {
  // Initialize connectivity watcher (offline banner + fail-fast actions).
  try {
    await ConnectivityService.instance.initialize();
    // ignore: avoid_print
    print('✅ Connectivity watcher initialized');
  } catch (e) {
    // ignore: avoid_print
    print('⚠️ Connectivity init error (app continues): $e');
  }
}

Future<void> _initializeLifecycle() async {
  // Initialize Android app lifecycle service (handles background/foreground transitions).
  try {
    LifecycleService.instance.initialize();
    // ignore: avoid_print
    print('✅ App lifecycle service initialized');
  } catch (e) {
    // ignore: avoid_print
    print('⚠️ Lifecycle service init error: $e');
  }
}

Future<void> _initializeSupabase() async {
  // Initialize Supabase before the app starts routing auth state.
  try {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
    // ignore: avoid_print
    print('✅ Supabase initialized successfully');
  } catch (e) {
    // ignore: avoid_print
    print('❌ Supabase initialization error: $e');
  }
}

Future<void> _initializeFirebase() async {
  // Initialize Firebase (for notifications)
  // If this fails, the app will still work but notifications will be empty
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // ignore: avoid_print
    print('✅ Firebase initialized successfully');
    // ignore: avoid_print
    print('✅ Firebase app name: ${Firebase.app().name}');

    // Register the background handler BEFORE any other FCM call.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    // ignore: avoid_print
    print('❌ Firebase initialization error: $e');
    // ignore: avoid_print
    print('⚠️ App will run but notifications will not work');
  }
}

class InfinityWashApp extends StatelessWidget {
  const InfinityWashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Infinity Wash',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // Used by push notifications to show banners / deep-link from taps,
      // and by the global offline banner.
      navigatorKey: infinityWashNavigatorKey,
      // Start with the lightweight auth routing gate.
      home: const SplashScreen(),
      builder: (context, child) {
        // Global offline banner above every screen.
        return OfflineBanner(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
