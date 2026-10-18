import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/secure_storage_service.dart';
import '../services/supabase_service.dart';

/// The kinds of OS permissions InfinityWash requests, with the plain-language
/// purpose shown to the user BEFORE the OS permission dialog appears.
///
/// Rationale: Android/iOS show a bare system dialog with no context; showing
/// our own one-screen explanation first (at the moment the user taps a
/// feature that needs the permission) is the store-review-friendly pattern.
enum AppPermission {
  camera(
    'Allow camera access?',
    'InfinityWash uses your camera to photograph your laundry for pickup and '
        'your GCash receipt as proof of payment. Photos are attached only to '
        'your order.',
    'camera',
  ),
  photos(
    'Allow photo library access?',
    'InfinityWash uses your photo library so you can attach laundry photos '
        'and payment receipts to your order. Your photos are never shared '
        'outside the app.',
    'photo library',
  ),
  location(
    'Allow location access?',
    'Your location is used to pinpoint your delivery address and let '
        'customers track riders in real time. InfinityWash only reads your '
        'location while the app is open.',
    'location',
  ),
  notifications(
    'Allow notifications?',
    'Get notified the moment your order moves — rider assigned, pickup on '
        'the way, laundry ready, and payment updates. You can turn these '
        'off anytime in Settings.',
    'notification',
  );

  const AppPermission(this.rationaleTitle, this.rationaleMessage, this.label);

  /// Human-readable name used inside denial copy ("camera access was not…").
  final String label;
  final String rationaleTitle;
  final String rationaleMessage;

  /// Shown when the OS reports the permission is permanently denied
  /// (user must re-enable it from system settings).
  String get deniedForeverMessage =>
      'You previously blocked $label access on this device. To use this '
      'feature, enable it in Settings → Apps → InfinityWash → Permissions.';

  /// Shown after a one-time denial (a later attempt can still show the
  /// OS prompt, or the user can enable it from settings).
  String get deniedOnceMessage =>
      '$label access was not granted. You can enable it later in '
      'Settings → Apps → InfinityWash → Permissions.';
}

/// Outcome of a permission request, normalized across plugins
/// (the `location` package uses an enum, FCM uses authorization status,
/// image_picker only surfaces denial via error codes).
class PermissionRequestResult {
  final bool granted;
  final bool deniedForever;

  const PermissionRequestResult.granted()
      : granted = true,
        deniedForever = false;

  const PermissionRequestResult.denied()
      : granted = false,
        deniedForever = false;

  const PermissionRequestResult.deniedForever()
      : granted = false,
        deniedForever = true;
}

/// Shared permission UX for the whole app.
///
/// Usage patterns:
///  - Explicit permission APIs (location, FCM notifications):
///    [ensure] — checks current status, shows the purpose dialog, requests,
///    and on refusal shows denial guidance with a Settings deep link.
///  - image_picker flows (camera / gallery): call [confirmRationale] before
///    `pickImage`, then on a picker permission error call [showDeniedDialog]
///    (see [isPickerPermissionCode]).
class PermissionManager {
  /// MethodChannel bridging to native "open this app's settings page".
  /// Implemented in MainActivity.kt (Android) and AppDelegate.swift (iOS);
  /// fails silently when unavailable — dialogs always tell the user the
  /// manual path too.
  static const MethodChannel _settingsChannel =
      MethodChannel('infinitywash/app_settings');

  /// Opens the OS settings page for this app.
  static Future<void> openAppSettings() async {
    try {
      await _settingsChannel.invokeMethod<bool>('openAppSettings');
    } on PlatformException {
      // Deep link unavailable — the denial dialog already shows the path.
    } on MissingPluginException {
      // Channel not registered (e.g. tests/desktop) — nothing to do.
    }
  }

  /// Shows the purpose explanation and asks the user to proceed.
  /// Returns false when the user chose "Not now" — no OS dialog is shown.
  static Future<bool> confirmRationale(
    BuildContext context,
    AppPermission kind,
  ) async {
    final userId = kind == AppPermission.camera
        ? SupabaseService.currentUser?.id
        : null;
    if (userId != null &&
        await SecureStorageService.instance.hasAcceptedPermissionRationale(
          userId: userId,
          permission: kind.name,
        )) {
      return true;
    }
    if (!context.mounted) return false;

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(kind.rationaleTitle),
        content: Text(kind.rationaleMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    if (proceed != true) return false;

    if (userId != null) {
      try {
        await SecureStorageService.instance.savePermissionRationaleAcceptance(
          userId: userId,
          permission: kind.name,
        );
      } catch (_) {
        // A storage failure must not prevent the user from granting permission.
      }
    }
    return true;
  }

  /// Dialog after an OS request was denied. [deniedForever] switches the copy
  /// to the permanent-denial message; "Open Settings" deep-links there.
  static Future<void> showDeniedDialog(
    BuildContext context,
    AppPermission kind, {
    bool deniedForever = false,
  }) async {
    final label =
        '${kind.label[0].toUpperCase()}${kind.label.substring(1)}';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label access needed'),
        content: Text(
          deniedForever ? kind.deniedForeverMessage : kind.deniedOnceMessage,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Full flow for explicit permission APIs:
  /// 1. skip everything when already granted (no nagging),
  /// 2. purpose dialog ("requested at the right time" — user-initiated),
  /// 3. OS request,
  /// 4. denial guidance with a Settings deep link on refusal.
  static Future<bool> ensure(
    BuildContext context,
    AppPermission kind, {
    /// Cheap pre-check; when it reports already-granted, nothing is shown.
    Future<bool> Function()? check,
    required Future<PermissionRequestResult> Function() request,
  }) async {
    if (check != null && await check()) return true;

    if (!context.mounted) return false;
    if (!await confirmRationale(context, kind)) return false;

    final result = await request();
    if (result.granted) return true;

    if (context.mounted) {
      await showDeniedDialog(context, kind, deniedForever: result.deniedForever);
    }
    return false;
  }

  /// True when an image_picker PlatformException code means the underlying
  /// OS permission was denied (vs. user simply cancelling the picker).
  static bool isPickerPermissionCode(String code) =>
      code == 'camera_access_denied' ||
      code == 'photo_access_denied' ||
      code == 'access_denied';
}
