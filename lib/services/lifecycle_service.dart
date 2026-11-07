import 'dart:async';
import 'package:flutter/widgets.dart';

import 'connectivity_service.dart';
import 'auth_service.dart';

/// Centralized service for tracking and handling Android / Flutter app lifecycle states.
///
/// Observes [AppLifecycleState] changes:
/// - [AppLifecycleState.resumed]: App is in the foreground and interactive.
/// - [AppLifecycleState.inactive]: App lost focus (phone call, split screen, system dialog).
/// - [AppLifecycleState.paused]: App is fully backgrounded (user pressed home or switched apps).
/// - [AppLifecycleState.detached]: App engine is detached / app is terminating.
/// - [AppLifecycleState.hidden]: App is hidden from the user.
class LifecycleService with WidgetsBindingObserver {
  LifecycleService._internal();
  static final LifecycleService instance = LifecycleService._internal();

  bool _isInitialized = false;
  AppLifecycleState _currentState = AppLifecycleState.resumed;
  DateTime? _lastPausedAt;
  Duration? _lastBackgroundDuration;

  final StreamController<AppLifecycleState> _stateController =
      StreamController<AppLifecycleState>.broadcast();
  final StreamController<Duration> _resumeDurationController =
      StreamController<Duration>.broadcast();

  final List<void Function(AppLifecycleState)> _customListeners = [];

  /// Current app lifecycle state.
  AppLifecycleState get currentState => _currentState;

  /// Whether the app is currently in the foreground and interactive.
  bool get isForeground => _currentState == AppLifecycleState.resumed;

  /// Whether the app is currently backgrounded or paused.
  bool get isBackground =>
      _currentState == AppLifecycleState.paused ||
      _currentState == AppLifecycleState.hidden;

  /// The timestamp when the app was last paused / sent to the background.
  DateTime? get lastPausedAt => _lastPausedAt;

  /// Duration spent in background during the most recent pause-resume cycle.
  Duration? get lastBackgroundDuration => _lastBackgroundDuration;

  /// Stream of all lifecycle state transitions.
  Stream<AppLifecycleState> get onLifecycleChanged => _stateController.stream;

  /// Stream that emits the background duration whenever the app resumes.
  Stream<Duration> get onResumedWithDuration => _resumeDurationController.stream;

  /// Initialize the lifecycle observer. Safe to call multiple times.
  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;
    WidgetsBinding.instance.addObserver(this);
    debugPrint('LifecycleService initialized');
  }

  /// Add a direct callback listener for lifecycle transitions.
  void addListener(void Function(AppLifecycleState) listener) {
    if (!_customListeners.contains(listener)) {
      _customListeners.add(listener);
    }
  }

  /// Remove a direct callback listener.
  void removeListener(void Function(AppLifecycleState) listener) {
    _customListeners.remove(listener);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _currentState = state;
    debugPrint('Lifecycle transition: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        _handleResumed();
        break;
      case AppLifecycleState.inactive:
        _handleInactive();
        break;
      case AppLifecycleState.paused:
        _handlePaused();
        break;
      case AppLifecycleState.detached:
        _handleDetached();
        break;
      case AppLifecycleState.hidden:
        _handleHidden();
        break;
    }

    if (!_stateController.isClosed) {
      _stateController.add(state);
    }

    for (final listener in List.of(_customListeners)) {
      try {
        listener(state);
      } catch (e) {
        debugPrint('Error in custom lifecycle listener: $e');
      }
    }
  }

  void _handleResumed() {
    final now = DateTime.now();
    Duration duration = Duration.zero;
    if (_lastPausedAt != null) {
      duration = now.difference(_lastPausedAt!);
      _lastBackgroundDuration = duration;
      debugPrint('App resumed after ${duration.inSeconds}s in background');
    } else {
      debugPrint('App resumed (fresh launch or no previous pause timestamp)');
    }

    if (!_resumeDurationController.isClosed) {
      _resumeDurationController.add(duration);
    }

    // 1. Re-check network connectivity immediately upon returning to foreground
    try {
      ConnectivityService.instance.checkNow();
    } catch (e) {
      debugPrint('Error re-checking connectivity on resume: $e');
    }

    // 2. Validate / refresh authentication session
    try {
      AuthService().validateOrRefreshSessionOnResume();
    } catch (e) {
      debugPrint('Error validating session on resume: $e');
    }
  }

  void _handleInactive() {
    debugPrint('App entered inactive state (focus transition)');
  }

  void _handlePaused() {
    _lastPausedAt = DateTime.now();
    debugPrint('App paused / sent to background at $_lastPausedAt');
  }

  void _handleHidden() {
    debugPrint('App window hidden');
  }

  void _handleDetached() {
    debugPrint('App detached / shutting down');
  }

  /// Clean up resources (useful during tests or teardown).
  void dispose() {
    if (_isInitialized) {
      WidgetsBinding.instance.removeObserver(this);
      _isInitialized = false;
    }
    _customListeners.clear();
    _stateController.close();
    _resumeDurationController.close();
  }
}

/// Convenience mixin for StatefulWidgets to easily react to app lifecycle transitions.
mixin AppLifecycleSubscriber<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    LifecycleService.instance.addListener(_handleLifecycleChanged);
  }

  @override
  void dispose() {
    LifecycleService.instance.removeListener(_handleLifecycleChanged);
    super.dispose();
  }

  void _handleLifecycleChanged(AppLifecycleState state) {
    if (!mounted) return;
    switch (state) {
      case AppLifecycleState.resumed:
        onAppResumed();
        break;
      case AppLifecycleState.paused:
        onAppPaused();
        break;
      case AppLifecycleState.inactive:
        onAppInactive();
        break;
      case AppLifecycleState.detached:
        onAppDetached();
        break;
      case AppLifecycleState.hidden:
        onAppHidden();
        break;
    }
  }

  /// Called when the app returns to the foreground and is interactive.
  void onAppResumed() {}

  /// Called when the app is backgrounded / paused.
  void onAppPaused() {}

  /// Called when the app enters an inactive transition state.
  void onAppInactive() {}

  /// Called when the app is terminating / detached.
  void onAppDetached() {}

  /// Called when the app window is hidden.
  void onAppHidden() {}
}

