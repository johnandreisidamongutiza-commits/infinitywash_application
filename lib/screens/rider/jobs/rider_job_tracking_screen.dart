import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../theme/app_theme.dart';
import '../../../models/dispatch_job.dart';
import '../../../services/rider_service.dart';
import '../../../services/supabase_service.dart';
import '../../../state/gps_provider.dart';
import '../../../state/rider_location_provider.dart';

/// Active job tracking screen with real-time location updates
class RiderJobTrackingScreen extends StatefulWidget {
  final DispatchJob job;

  const RiderJobTrackingScreen({super.key, required this.job});

  @override
  State<RiderJobTrackingScreen> createState() => _RiderJobTrackingScreenState();
}

class _RiderJobTrackingScreenState extends State<RiderJobTrackingScreen> {
  final MapController _mapController = MapController();
  final RiderService _riderService = RiderService();
  final GpsProvider _gpsProvider = GpsProvider();
  final RiderLocationProvider _locationProvider = RiderLocationProvider();
  
  LatLng? _riderLocation;
  StreamSubscription? _locationSubscription;
  bool _isCompleting = false;
  int _updateCount = 0;
  
  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    try {
      await _gpsProvider.initialize();
      await _gpsProvider.startTracking();

      // Get rider ID
      final riderId = widget.job.riderId ?? SupabaseService.client.auth.currentUser?.id;
      if (riderId == null) {
        throw Exception('Rider ID not found');
      }

      // Start uploading to Supabase
      await _locationProvider.startUploading(
        riderId: riderId,
        dispatchJobId: widget.job.id,
        locationStream: _gpsProvider.locationStream
            .where((loc) => loc.latitude != null && loc.longitude != null)
            .map((locationData) =>
                LatLng(locationData.latitude!, locationData.longitude!)),
      );

      _locationSubscription = _gpsProvider.locationStream.listen((locationData) {
        if (mounted && locationData.latitude != null && locationData.longitude != null) {
          setState(() {
            _riderLocation = LatLng(locationData.latitude!, locationData.longitude!);
            _updateCount++;
          });
          _mapController.move(_riderLocation!, 15.0);
        }
      });
    } catch (e) {
      print('❌ Error starting tracking: $e');
    }
  }

  Future<void> _completeJob() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Complete ${widget.job.jobType == 'pickup' ? 'Pickup' : 'Delivery'}?'),
        content: const Text('Mark this job as complete?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isCompleting = true);

    try {
      if (widget.job.jobType == 'pickup') {
        await _riderService.completePickup(widget.job.id, widget.job.orderId);
      } else {
        await _riderService.completeDelivery(widget.job.id, widget.job.orderId);
      }

      await _locationProvider.stopUploading();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job completed!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
        setState(() => _isCompleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobLocation = widget.job.latitude != null && widget.job.longitude != null
        ? LatLng(widget.job.latitude!, widget.job.longitude!)
        : null;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: jobLocation ?? const LatLng(14.2499596, 121.4027956),
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.infinitywash.app',
              ),
              if (_riderLocation != null && jobLocation != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [_riderLocation!, jobLocation],
                      strokeWidth: 4.0,
                      color: AppTheme.accentBlue,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (jobLocation != null)
                    Marker(
                      point: jobLocation,
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.location_on,
                        color: widget.job.jobType == 'pickup'
                            ? AppTheme.errorRed
                            : AppTheme.teamMemberIconOrange,
                        size: 40,
                      ),
                    ),
                  if (_riderLocation != null)
                    Marker(
                      point: _riderLocation!,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: const Icon(Icons.navigation, color: Colors.white, size: 20),
                      ),
                    ),
                ],
              ),
            ],
          ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: widget.job.jobType == 'pickup'
                                ? AppTheme.errorRed.withValues(alpha: 0.1)
                                : AppTheme.teamMemberIconOrange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.job.jobType == 'pickup' ? 'PICKUP' : 'DELIVERY',
                            style: TextStyle(
                              color: widget.job.jobType == 'pickup'
                                  ? AppTheme.errorRed
                                  : AppTheme.teamMemberIconOrange,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.job.jobNumber ?? 'Job',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.circle, color: Colors.white, size: 8),
                        ),
                        const SizedBox(width: 4),
                        const Text('Tracking', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.job.address ?? 'No address',
                            style: const TextStyle(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.upload, size: 16, color: AppTheme.textLight),
                        const SizedBox(width: 8),
                        Text(
                          'Updates: $_updateCount',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 32,
            left: 16,
            right: 16,
            child: ElevatedButton(
              onPressed: _isCompleting ? null : _completeJob,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isCompleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text('Complete ${widget.job.jobType == 'pickup' ? 'Pickup' : 'Delivery'}'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _locationProvider.stopUploading();
    _gpsProvider.stopTracking();
    super.dispose();
  }
}
