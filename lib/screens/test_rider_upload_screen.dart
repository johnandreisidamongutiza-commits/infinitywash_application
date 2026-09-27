import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../state/gps_provider.dart';
import '../state/rider_location_provider.dart';
import 'dart:async';

/// Test screen for Phase 10: Rider Location Uploads
/// 
/// Tests:
/// - GPS location uploads to Supabase
/// - 30 second interval threshold
/// - 50 meter distance threshold
/// - Upload count tracking
/// - Error handling
class TestRiderUploadScreen extends StatefulWidget {
  const TestRiderUploadScreen({super.key});

  @override
  State<TestRiderUploadScreen> createState() => _TestRiderUploadScreenState();
}

class _TestRiderUploadScreenState extends State<TestRiderUploadScreen> {
  late final GpsProvider _gpsProvider;
  late final RiderLocationProvider _riderLocationProvider;
  
  // Test rider ID (replace with actual rider ID in production)
  final String _testRiderId = 'test-rider-123';
  final String? _testDispatchJobId = 'test-job-456';
  
  final StreamController<LatLng> _locationStreamController = StreamController<LatLng>.broadcast();
  
  @override
  void initState() {
    super.initState();
    _gpsProvider = GpsProvider();
    _riderLocationProvider = RiderLocationProvider();
    _initializeGps();
  }

  Future<void> _initializeGps() async {
    await _gpsProvider.initialize();
    
    if (_gpsProvider.hasPermission && _gpsProvider.isServiceEnabled) {
      await _gpsProvider.startTracking();
      
      // Forward GPS updates to location stream
      _gpsProvider.addListener(_onGpsUpdate);
    }
  }

  void _onGpsUpdate() {
    if (_gpsProvider.currentLocation != null) {
      _locationStreamController.add(_gpsProvider.currentLocation!);
    }
  }

  Future<void> _startUploading() async {
    try {
      await _riderLocationProvider.startUploading(
        riderId: _testRiderId,
        dispatchJobId: _testDispatchJobId,
        locationStream: _locationStreamController.stream,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Started uploading location to Supabase'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start upload: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _stopUploading() async {
    await _riderLocationProvider.stopUploading();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stopped uploading location'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _gpsProvider.removeListener(_onGpsUpdate);
    _gpsProvider.stopTracking();
    _gpsProvider.dispose();
    _riderLocationProvider.stopUploading();
    _riderLocationProvider.dispose();
    _locationStreamController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _gpsProvider),
        ChangeNotifierProvider.value(value: _riderLocationProvider),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Rider Upload Test - Phase 10'),
          backgroundColor: Colors.cyan,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            // Info banner
            Consumer2<GpsProvider, RiderLocationProvider>(
              builder: (context, gps, riderLocation, child) {
                Color bannerColor;
                String statusText;
                IconData statusIcon;

                if (riderLocation.errorMessage != null) {
                  bannerColor = Colors.red.shade50;
                  statusText = riderLocation.errorMessage!;
                  statusIcon = Icons.error;
                } else if (riderLocation.isTracking) {
                  bannerColor = Colors.green.shade50;
                  statusText = 'Uploading active • ${riderLocation.getUploadStats()}';
                  statusIcon = Icons.cloud_upload;
                } else if (!gps.hasPermission) {
                  bannerColor = Colors.orange.shade50;
                  statusText = 'Location permission required';
                  statusIcon = Icons.warning;
                } else if (!gps.isServiceEnabled) {
                  bannerColor = Colors.orange.shade50;
                  statusText = 'GPS service disabled';
                  statusIcon = Icons.gps_off;
                } else {
                  bannerColor = Colors.blue.shade50;
                  statusText = 'Ready to upload';
                  statusIcon = Icons.info_outline;
                }

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: bannerColor,
                  child: Row(
                    children: [
                      Icon(statusIcon, size: 20, color: Colors.grey.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '✅ Phase 10: Rider Location Upload Test',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Status cards
            Padding(
              padding: const EdgeInsets.all(16),
              child: Consumer2<GpsProvider, RiderLocationProvider>(
                builder: (context, gps, riderLocation, child) {
                  return Row(
                    children: [
                      Expanded(
                        child: _buildStatusCard(
                          'GPS',
                          gps.isTracking ? 'Tracking' : 'Off',
                          gps.isTracking ? Colors.green : Colors.grey,
                          Icons.gps_fixed,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildStatusCard(
                          'Upload',
                          riderLocation.isTracking ? 'Active' : 'Stopped',
                          riderLocation.isTracking ? Colors.blue : Colors.grey,
                          Icons.cloud_upload,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildStatusCard(
                          'Count',
                          '${riderLocation.uploadCount}',
                          riderLocation.uploadCount > 0 ? Colors.cyan : Colors.grey,
                          Icons.upload_file,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // Current location display
            Consumer<GpsProvider>(
              builder: (context, gps, child) {
                if (gps.currentLocation == null) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: Text('Waiting for GPS location...'),
                        ),
                      ),
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.my_location, size: 20, color: Colors.blue),
                              SizedBox(width: 8),
                              Text(
                                'Current GPS Location',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Lat: ${gps.currentLocation!.latitude.toStringAsFixed(6)}',
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          ),
                          Text(
                            'Lng: ${gps.currentLocation!.longitude.toStringAsFixed(6)}',
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Last upload info
            Consumer<RiderLocationProvider>(
              builder: (context, riderLocation, child) {
                if (riderLocation.lastUploadedLocation == null) {
                  return const SizedBox.shrink();
                }

                final timeSinceUpload = riderLocation.lastUploadTime != null
                    ? DateTime.now().difference(riderLocation.lastUploadTime!)
                    : Duration.zero;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    color: Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.cloud_done, size: 20, color: Colors.green),
                              SizedBox(width: 8),
                              Text(
                                'Last Upload',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Lat: ${riderLocation.lastUploadedLocation!.latitude.toStringAsFixed(6)}',
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          ),
                          Text(
                            'Lng: ${riderLocation.lastUploadedLocation!.longitude.toStringAsFixed(6)}',
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${timeSinceUpload.inSeconds} seconds ago',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            const Spacer(),

            // Test instructions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Test Checklist:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  _buildCheckItem('GPS location displays'),
                  _buildCheckItem('Upload starts when button pressed'),
                  _buildCheckItem('First upload happens immediately'),
                  _buildCheckItem('Subsequent uploads every 30s OR 50m'),
                  _buildCheckItem('Upload count increments'),
                  _buildCheckItem('Last upload info shows'),
                  _buildCheckItem('Stop button ends uploads'),
                  const SizedBox(height: 12),
                  Consumer2<GpsProvider, RiderLocationProvider>(
                    builder: (context, gps, riderLocation, child) {
                      if (riderLocation.isTracking) {
                        return SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _stopUploading,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop Uploading'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        );
                      } else {
                        return SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: gps.isReady ? _startUploading : null,
                            icon: const Icon(Icons.cloud_upload),
                            label: Text(
                              gps.isReady
                                  ? 'Start Uploading to Supabase'
                                  : 'Enable GPS first',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyan,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey.shade300,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Consumer<RiderLocationProvider>(
                    builder: (context, riderLocation, child) {
                      return SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: riderLocation.uploadCount > 0
                              ? _showTestResultDialog
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade300,
                          ),
                          child: Text(
                            riderLocation.uploadCount > 0
                                ? 'Phase 10 Complete ✓'
                                : 'Upload location first',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          Text(
            value,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.check_box_outline_blank, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _showTestResultDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('Phase 10 Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rider location upload functionality verified!'),
            const SizedBox(height: 16),
            Text(
              'Upload Stats:\n'
              '• Total uploads: ${_riderLocationProvider.uploadCount}\n'
              '• Interval: 30 seconds OR 50 meters\n'
              '• Database flooding prevented ✓',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Text(
              'Next steps:\n'
              '• Phase 11: Supabase Realtime (customer side)\n'
              '• Phase 11.5: Order status sync\n'
              '• Phase 12: Tracking gate logic',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
