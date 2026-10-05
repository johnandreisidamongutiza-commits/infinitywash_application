import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Singleton connectivity watcher.
///
/// Tracks whether the device has any network interface (wifi/mobile/ethernet)
/// and exposes a broadcast stream so the UI can show/hide an offline banner
/// and critical actions can fail fast with a clear message.
class ConnectivityService {
  ConnectivityService._internal();
  static final ConnectivityService instance = ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _isOnline = true;
  bool _initialized = false;
  final _controller = StreamController<bool>.broadcast();

  /// Last known connectivity state. Safe to read synchronously.
  bool get isOnline => _isOnline;

  bool get isOffline => !_isOnline;

  /// Broadcast stream emitting the online state whenever it changes.
  Stream<bool> get onConnectivityChanged => _controller.stream;

  /// Start listening to connectivity changes and do an initial check.
  /// Safe to call multiple times; only the first call has effect.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await checkNow();
      _subscription = _connectivity.onConnectivityChanged.listen(
        _updateFromResults,
        // Never let a stream error crash the app — keep last known state.
        onError: (Object e) {
          // Keep last known state; a periodic checkNow() from callers recovers.
          // ignore: avoid_print
          print('⚠️ Connectivity stream error: $e');
        },
        cancelOnError: false,
      );
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ ConnectivityService init failed (assuming online): $e');
      _isOnline = true;
    }
  }

  void _updateFromResults(List<ConnectivityResult> results) {
    final online = _resultsMeanOnline(results);
    _setOnline(online);
  }

  bool _resultsMeanOnline(List<ConnectivityResult> results) {
    return results.any(
      (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.mobile || r == ConnectivityResult.ethernet,
    );
  }

  /// Force an immediate connectivity check (e.g. before login or payment).
  Future<bool> checkNow() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateFromResults(results);
    } catch (e) {
      // If the plugin fails, assume online — real requests will surface
      // their own mapped network errors.
      // ignore: avoid_print
      print('⚠️ Connectivity check failed (assuming online): $e');
      _setOnline(true);
    }
    return _isOnline;
  }

  /// Fail fast: throws an [AppError]-style message when offline.
  /// Returns normally when online.
  Future<void> ensureOnline({String? action}) async {
    final online = await checkNow();
    if (!online) {
      throw OfflineException(action: action);
    }
  }

  void _setOnline(bool online) {
    if (_isOnline == online) return;
    _isOnline = online;
    if (!_controller.isClosed) {
      _controller.add(online);
    }
  }

  /// Stop listening (testing / app teardown).
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _initialized = false;
    await _controller.close();
  }
}

/// Thrown by [ConnectivityService.ensureOnline] when the device is offline.
class OfflineException implements Exception {
  final String? action;

  OfflineException({this.action});

  @override
  String toString() => action == null
      ? 'No internet connection. Please check your connection and try again.'
      : 'No internet connection. You need to be online to $action.';
}
