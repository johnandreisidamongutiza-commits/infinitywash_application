import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'secure_storage_service.dart';

/// Sound and haptic alert service for staff and order notifications.
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  static const MethodChannel _foregroundChannel =
      MethodChannel('infinitywash/foreground_notifications');
  static const String _soundPrefKey = 'staff_sound_notifications_enabled';

  DateTime? _lastPlayedAt;
  bool? _cachedSoundEnabled;

  /// Check whether sound alerts are enabled (defaults to true).
  Future<bool> isSoundEnabled() async {
    if (_cachedSoundEnabled != null) return _cachedSoundEnabled!;
    try {
      final value = await SecureStorageService.instance.storage.read(key: _soundPrefKey);
      _cachedSoundEnabled = value != 'false';
    } catch (_) {
      _cachedSoundEnabled = true;
    }
    return _cachedSoundEnabled!;
  }

  /// Update the sound alert preference.
  Future<void> setSoundEnabled(bool enabled) async {
    _cachedSoundEnabled = enabled;
    try {
      await SecureStorageService.instance.storage.write(
        key: _soundPrefKey,
        value: enabled ? 'true' : 'false',
      );
    } catch (e) {
      debugPrint('🔔 Could not persist sound preference: $e');
    }
  }

  /// Play the default notification sound and trigger haptic feedback.
  /// Includes a 2.5 second debounce to prevent overlapping audio triggers.
  Future<void> playNotificationSound({bool force = false}) async {
    if (!force) {
      final enabled = await isSoundEnabled();
      if (!enabled) return;

      final now = DateTime.now();
      if (_lastPlayedAt != null &&
          now.difference(_lastPlayedAt!).inMilliseconds < 2500) {
        return;
      }
      _lastPlayedAt = now;
    }

    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _foregroundChannel.invokeMethod('playNotificationSound');
      } else {
        await SystemSound.play(SystemSoundType.alert);
        await HapticFeedback.heavyImpact();
      }
    } catch (e) {
      debugPrint('🔔 Native sound playback fallback: $e');
      try {
        await SystemSound.play(SystemSoundType.alert);
        await HapticFeedback.heavyImpact();
      } catch (_) {}
    }
  }
}

