import 'package:flutter/material.dart';
import '../../../models/dispatch_job.dart';
import '../route/rider_active_route_screen.dart';

/// Active single-job tracking screen.
/// Delegates directly to [RiderActiveRouteScreen] to maintain a single,
/// unified navigation experience (Heading-Up rotation, road-aligned heading,
/// zoom preservation, pre-GPS loading state, and timeout fallback).
class RiderJobTrackingScreen extends StatelessWidget {
  final DispatchJob job;

  const RiderJobTrackingScreen({super.key, required this.job});

  @override
  Widget build(BuildContext context) {
    return RiderActiveRouteScreen(jobs: [job]);
  }
}
