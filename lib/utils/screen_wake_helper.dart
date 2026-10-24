import 'package:flutter/services.dart';

/// Native Screen WakeLock Helper
/// 
/// Uses native Android WindowManager FLAG_KEEP_SCREEN_ON via MethodChannel.
/// Keeps the phone screen turned on during active navigation without requiring
/// heavy multi-platform desktop dependencies or third-party plugins.
class ScreenWakeHelper {
  static const MethodChannel _channel = MethodChannel('infinitywash/screen_wake');

  /// Keep the screen awake
  static Future<void> enable() async {
    try {
      await _channel.invokeMethod('keepScreenOn', {'enable': true});
    } catch (_) {}
  }

  /// Allow the screen to turn off normally
  static Future<void> disable() async {
    try {
      await _channel.invokeMethod('keepScreenOn', {'enable': false});
    } catch (_) {}
  }
}
