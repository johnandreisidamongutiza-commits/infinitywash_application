import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Broadcasts order and dispatch changes so visible screens can refresh only
/// after data changes, rather than polling every tab independently.
class DataChangeMonitor {
  DataChangeMonitor._();

  static final DataChangeMonitor instance = DataChangeMonitor._();

  final ValueNotifier<int> ordersVersion = ValueNotifier<int>(0);
  final ValueNotifier<int> dispatchJobsVersion = ValueNotifier<int>(0);
  final ValueNotifier<int> operationalDataVersion = ValueNotifier<int>(0);

  RealtimeChannel? _channel;
  Timer? _fallbackTimer;
  Timer? _changeDebounce;
  bool _ordersChangePending = false;
  bool _dispatchChangePending = false;
  bool _started = false;
  bool _realtimeConnected = false;

  void start() {
    if (_started) return;
    _started = true;

    try {
      _channel = Supabase.instance.client
          .channel('infinitywash:data-change-monitor')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            callback: (_) => _notifyOrdersChanged(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'order_loads',
            callback: (_) => _notifyOrdersChanged(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'dispatch_jobs',
            callback: (_) => _notifyDispatchJobsChanged(),
          )
          .subscribe((status, error) {
            final connected = status == RealtimeSubscribeStatus.subscribed;
            _realtimeConnected = connected;
            if (connected) {
              _fallbackTimer?.cancel();
              _fallbackTimer = null;
            } else {
              _startFallbackRefresh();
              if (error != null) {
                debugPrint('Data change listener unavailable: $error');
              }
            }
          });
    } catch (error) {
      debugPrint('Could not start data change listener: $error');
      _startFallbackRefresh();
    }
  }

  void _startFallbackRefresh() {
    if (_realtimeConnected || _fallbackTimer != null) return;
    _fallbackTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      // Screens decide whether they are visible before issuing any read.
      _notifyOrdersChanged();
      _notifyDispatchJobsChanged();
    });
  }

  void _notifyOrdersChanged() {
    _ordersChangePending = true;
    _scheduleChangeFlush();
  }

  /// Manually notify that an order has been created or updated
  void notifyOrdersChanged() {
    _notifyOrdersChanged();
  }

  void _notifyDispatchJobsChanged() {
    _dispatchChangePending = true;
    _scheduleChangeFlush();
  }

  void _scheduleChangeFlush() {
    _changeDebounce ??= Timer(const Duration(milliseconds: 200), () {
      _changeDebounce = null;
      final ordersChanged = _ordersChangePending;
      final dispatchJobsChanged = _dispatchChangePending;
      if (ordersChanged) ordersVersion.value++;
      if (dispatchJobsChanged) dispatchJobsVersion.value++;
      if (ordersChanged || dispatchJobsChanged) {
        operationalDataVersion.value++;
      }
      _ordersChangePending = false;
      _dispatchChangePending = false;
    });
  }
}
