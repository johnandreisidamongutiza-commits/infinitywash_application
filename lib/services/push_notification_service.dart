import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../utils/permission_manager.dart';
import '../widgets/top_notification.dart';
import 'supabase_service.dart';

/// Global navigator key used by push handling to reach the overlay from
/// outside the widget tree (foreground banners and tap routing).
final GlobalKey<NavigatorState> infinityWashNavigatorKey =
    GlobalKey<NavigatorState>();

/// A single push notification payload, normalized from FCM.
class PushMessage {
  final String? title;
  final String? body;
  final Map<String, dynamic> data;

  const PushMessage({
    this.title,
    this.body,
    this.data = const {},
  });

  factory PushMessage.fromRemoteMessage(RemoteMessage message) {
    return PushMessage(
      title: message.notification?.title ?? message.data['title'] as String?,
      body: message.notification?.body ?? message.data['body'] as String?,
      data: message.data,
    );
  }
}

/// FCM push notification service.
///
/// Handles the full push lifecycle for every signed-in user
/// (customers, staff and riders alike):
///   - permission request,
///   - FCM token generation and registration in the `fcm_tokens` table,
///   - token-refresh re-registration and stale-token cleanup on sign-out,
///   - foreground display via the app's existing top banner,
///   - background/terminated handling via the top-level handler wired in main.dart,
///   - tap routing through [onNotificationTap] so the shell can deep-link.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final SupabaseClient _client = SupabaseService.client;

  /// Tray notifications on Android land on the channel named by the
  /// `com.google.firebase.messaging.default_notification_channel_id`
  /// meta-data in AndroidManifest.xml (`infinitywash_default`).  /// Set by the app shell so notification taps can deep-link.
  static void Function(PushMessage message)? onNotificationTap;

  bool _initialized = false;
  String? _registeredToken;
  String? _registeredUserId;

  /// Check / request permission and return the granted status.
  ///
  /// Shows the app's purpose explanation (why order updates need
  /// notifications) BEFORE the OS prompt — the request fires right after a
  /// user-initiated sign-in, using the global navigator context. On denial,
  /// guidance with a Settings deep link is shown.
  Future<bool> _ensurePermission() async {
    // Already answered before? Never re-nag: denied users re-enable from
    // Settings, authorized users need no prompt at all.
    final existing = await _messaging.getNotificationSettings();
    switch (existing.authorizationStatus) {
      case AuthorizationStatus.authorized:
      case AuthorizationStatus.provisional:
        return true;
      case AuthorizationStatus.denied:
        return false;
      case AuthorizationStatus.notDetermined:
        break; // first time — show the purpose explanation below
    }

    final context = infinityWashNavigatorKey.currentContext;
    final hasContext = context != null && context.mounted;

    if (hasContext) {
      final proceed = await PermissionManager.confirmRationale(
        context,
        AppPermission.notifications,
      );
      if (!proceed) {
        debugPrint('🔔 Push permission postponed by user; skipping registration');
        return false;
      }
    }

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

    if (!granted && hasContext && context.mounted) {
      await PermissionManager.showDeniedDialog(
        context,
        AppPermission.notifications,
      );
    }

    return granted;
  }

  /// Initialize push for the current signed-in user.
  ///
  /// Safe to call on every sign-in / app start; idempotent per token+user
  /// pair and never throws — push failures must never block the app.
  Future<void> initializeForCurrentUser() async {
    try {
      if (SupabaseService.currentUser == null) return; // not signed in

      await _ensureAndroidSetup();

      if (!_initialized) {
        final granted = await _ensurePermission();
        if (!granted) {
          debugPrint('🔔 Push permission denied; skipping registration');
          return; // user can re-enable from OS settings later
        }

        // Fired when FCM rotates the token (app restore, key rotation...).
        FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);

        // Foreground: show the app's existing top banner.
        FirebaseMessaging.onMessage.listen(_showForegroundBanner);

        // App opened from a notification tap (background -> foreground).
        FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

        _initialized = true;
      }

      final token = await _messaging.getToken();
      if (token == null) {
        debugPrint('🔔 FCM token unavailable');
        return;
      }

      await _registerToken(token);

      // App launched fresh from a terminated state by a notification tap.
      final initial = await _messaging.getInitialMessage();
      if (initial != null) {
        // Give the navigator a moment to mount before deep-linking.
        Future.delayed(
          const Duration(seconds: 1),
          () => _handleTap(initial),
        );
      }
    } catch (e) {
      debugPrint('🔔 Push initialization failed (non-fatal): $e');
    }
  }

  /// Enable FCM auto-init on Android. The notification channel used by
  /// tray notifications is declared in AndroidManifest.xml via the
  /// `com.google.firebase.messaging.default_notification_channel_id`
  /// meta-data; the FCM SDK creates that channel itself on first use.
  Future<void> _ensureAndroidSetup() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _messaging.setAutoInitEnabled(true).catchError((_) {}); // non-fatal
  }

  /// Upsert the token for the current user (user_id + token are unique together).
  Future<void> _registerToken(String token) async {
    final user = SupabaseService.currentUser;
    if (user == null || token.isEmpty) return;

    // Same token already registered for this user: nothing to do.
    if (_registeredToken == token && _registeredUserId == user.id) return;

    try {
      await _client.from('fcm_tokens').upsert({
        'user_id': user.id,
        'token': token,
        'platform':
            defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,token');

      _registeredToken = token;
      _registeredUserId = user.id;
      debugPrint('✅ FCM token registered for user ${user.id}');
    } catch (e) {
      debugPrint('🔔 FCM token registration failed (non-fatal): $e');
    }
  }

  /// Drop this device's token row (called on sign-out so the backend
  /// doesn't push to a device nobody is signed in on).
  Future<void> unregisterCurrentUser() async {
    final token = _registeredToken;
    _registeredToken = null;
    _registeredUserId = null;
    if (token == null) return;
    try {
      await _client.from('fcm_tokens').delete().eq('token', token);
    } catch (e) {
      debugPrint('🔔 Token unregister failed (non-fatal): $e');
    }
  }

  void _showForegroundBanner(RemoteMessage message) {
    final push = PushMessage.fromRemoteMessage(message);
    final context = infinityWashNavigatorKey.currentContext;
    if (context == null) return;
    showTopNotification(
      context,
      message: push.body ?? push.title ?? 'New notification',
      icon: Icons.notifications_active,
      backgroundColor: AppTheme.primaryBlue,
    );
  }

  void _handleTap(RemoteMessage message) {
    onNotificationTap?.call(PushMessage.fromRemoteMessage(message));
  }
}

/// Top-level handler Firebase requires for background/terminated messages.
/// Must be a top-level (non-closure) function annotated @pragma('vm:entry-point').
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Display notifications are rendered by the system tray automatically;
  // data-only messages would be processed here. Keep it lightweight.
  debugPrint('🔔 Background push received: ${message.messageId}');
}
