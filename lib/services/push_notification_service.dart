import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/permission_manager.dart';
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
///   - foreground display as a system notification,
///   - background/terminated handling via the top-level handler wired in main.dart,
///   - tap routing through [onNotificationTap] so the shell can deep-link.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SupabaseClient _client = SupabaseService.client;
  static const MethodChannel _foregroundNotificationChannel =
      MethodChannel('infinitywash/foreground_notifications');

  /// Tray notifications on Android land on the channel named by the
  /// `com.google.firebase.messaging.default_notification_channel_id`
  /// meta-data in AndroidManifest.xml (`infinitywash_default`).  /// Set by the app shell so notification taps can deep-link.
  static void Function(PushMessage message)? onNotificationTap;

  bool _initialized = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _announcementSubscription;
  String? _announcementListenerUserId;
  final Map<String, DateTime> _recentSystemNotifications = {};
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

        // iOS suppresses remote notifications while the app is active unless
        // foreground presentation is explicitly enabled. Android displays
        // foreground pushes through the native channel below.
        await _messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

        // Fired when FCM rotates the token (app restore, key rotation...).
        FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);

        // Foreground: show the app's existing top banner.
        FirebaseMessaging.onMessage.listen(_showForegroundBanner);

        // App opened from a notification tap (background -> foreground).
        FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

        _initialized = true;
      }

      // Firestore announcements update the in-app feed directly. Turn those
      // live updates into Android system notifications too, even when the
      // admin's FCM delivery is misconfigured. This listener is foreground
      // only; background delivery still comes from FCM.
      await _watchForegroundAnnouncements(SupabaseService.currentUser!.id);

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

  Future<void> _watchForegroundAnnouncements(String userId) async {
    if (_announcementListenerUserId == userId &&
        _announcementSubscription != null) {
      return;
    }

    await _announcementSubscription?.cancel();
    _announcementListenerUserId = userId;

    String? role;
    try {
      final profile = await _client
          .from('profiles')
          .select('role')
          .eq('supabase_user_id', userId)
          .single();
      role = profile['role'] as String?;
    } catch (error) {
      debugPrint('🔔 Could not load role for announcement alerts: $error');
      return;
    }
    if (role == null || role.isEmpty) return;

    var isInitialSnapshot = true;
    _announcementSubscription = _firestore
        .collection('announcements')
        .where('status', isEqualTo: 'published')
        .snapshots()
        .listen((snapshot) {
      if (isInitialSnapshot) {
        isInitialSnapshot = false;
        return; // Don't alert for old announcements when opening the app.
      }

      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.removed) continue;
        final data = change.doc.data();
        if (data == null) continue;

        final rawRoles = data['audience_roles'] ?? data['audienceRoles'];
        final roles = rawRoles is List
            ? rawRoles.map((value) => value.toString()).toList()
            : const <String>[];
        if (!roles.contains(role)) continue;

        final expiresAt = data['expires_at'] ?? data['expiresAt'];
        if (expiresAt is Timestamp && expiresAt.toDate().isBefore(DateTime.now())) {
          continue;
        }

        final title = (data['title'] ?? '').toString().trim();
        final body = (data['message'] ?? data['body'] ?? '').toString().trim();
        if (title.isEmpty && body.isEmpty) continue;

        _showSystemNotification(
          id: change.doc.id.hashCode,
          title: title.isEmpty ? 'InfinityWash' : title,
          body: body.isEmpty ? 'You have a new announcement.' : body,
        );
      }
    }, onError: (Object error) {
      debugPrint('🔔 Firestore announcement alert listener failed: $error');
    });
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

  Future<void> _showForegroundBanner(RemoteMessage message) async {
    final push = PushMessage.fromRemoteMessage(message);
    // Fall back to data fields so data-only FCM messages still show a banner.
    final title = push.title ??
        message.data['title'] as String? ??
        'InfinityWash';
    final body = push.body ??
        message.data['body'] as String? ??
        message.data['message'] as String? ??
        'You have a new notification.';

    await _showSystemNotification(
      id: message.messageId?.hashCode ??
          DateTime.now().millisecondsSinceEpoch.remainder(0x7fffffff),
      title: title,
      body: body,
    );
  }

  Future<void> _showSystemNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // The same announcement can arrive through both Firestore and FCM.
      // Avoid displaying it twice when those two live paths overlap.
      final fingerprint = '$title\n$body';
      final now = DateTime.now();
      final lastShown = _recentSystemNotifications[fingerprint];
      if (lastShown != null && now.difference(lastShown).inSeconds < 30) {
        return;
      }
      _recentSystemNotifications[fingerprint] = now;
      _recentSystemNotifications.removeWhere(
        (_, shownAt) => now.difference(shownAt).inMinutes >= 2,
      );

      try {
        await _foregroundNotificationChannel.invokeMethod<void>(
          'showForegroundNotification',
          {
            'id': id,
            'title': title,
            'body': body,
          },
        );
      } catch (error) {
        debugPrint('🔔 Could not show foreground system notification: $error');
      }
    }
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
