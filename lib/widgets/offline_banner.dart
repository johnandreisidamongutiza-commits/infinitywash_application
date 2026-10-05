import 'dart:async';

import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';

/// Global offline banner shown at the top of the app whenever the device
/// loses internet connectivity. Listens to [ConnectivityService] and shows
/// "No internet connection" when offline, hides again when back online.
///
/// Wrap it around the app's home (or each main screen's Scaffold body) so
/// every role sees it:
///
/// ```dart
/// Column(children: [const OfflineBanner(), Expanded(child: body)])
/// ```
class OfflineBanner extends StatefulWidget {
  final Widget child;

  const OfflineBanner({super.key, required this.child});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  StreamSubscription<bool>? _sub;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _offline = ConnectivityService.instance.isOffline;
    _sub = ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (!mounted) return;
      setState(() => _offline = !online);
    });
    // Also do a fresh check when the banner mounts.
    ConnectivityService.instance.checkNow();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _offline ? _buildBanner() : const SizedBox(width: double.infinity),
        ),
        Expanded(child: widget.child),
      ],
    );
  }

  Widget _buildBanner() {
    return Material(
      color: AppTheme.errorRed,
      elevation: 0,
      child: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: const Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No internet connection — some features may be unavailable.',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
