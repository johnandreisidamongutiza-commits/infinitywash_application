import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../theme/app_theme.dart';
import '../../../models/dispatch_job.dart';
import '../../../services/rider_service.dart';
import '../../../state/gps_provider.dart';
import 'rider_job_tracking_screen.dart';

/// Details screen for a specific dispatch job
/// Shows job information, location on map, and action buttons
class RiderJobDetailsScreen extends StatefulWidget {
  final DispatchJob job;

  const RiderJobDetailsScreen({
    super.key,
    required this.job,
  });

  @override
  State<RiderJobDetailsScreen> createState() => _RiderJobDetailsScreenState();
}

class _RiderJobDetailsScreenState extends State<RiderJobDetailsScreen> {
  final MapController _mapController = MapController();
  final RiderService _riderService = RiderService();
  final GpsProvider _gpsProvider = GpsProvider();
  
  LatLng? _riderLocation;
  bool _isStarting = false;
  
  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    try {
      await _gpsProvider.initialize();
      _gpsProvider.locationStream.listen((location) {
        if (mounted && location.latitude != null && location.longitude != null) {
          setState(() {
            _riderLocation = LatLng(location.latitude!, location.longitude!);
          });
        }
      });
    } catch (e) {
      print('❌ Error initializing GPS: $e');
    }
  }

  Future<void> _startJob() async {
    setState(() => _isStarting = true);

    try {
      await _riderService.startJob(widget.job.id);
      
      if (mounted) {
        // Navigate to tracking screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => RiderJobTrackingScreen(job: widget.job),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting job: $e'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
        setState(() => _isStarting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobLocation = widget.job.latitude != null && widget.job.longitude != null
        ? LatLng(widget.job.latitude!, widget.job.longitude!)
        : null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.job.jobNumber ?? 'Job Details'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Map preview
            if (jobLocation != null)
              SizedBox(
                height: 250,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: jobLocation,
                    initialZoom: 14.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.infinitywash.app',
                    ),
                    MarkerLayer(
                      markers: [
                        // Job marker
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
                        // Rider marker
                        if (_riderLocation != null)
                          Marker(
                            point: _riderLocation!,
                            width: 30,
                            height: 30,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(
                                Icons.navigation,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

            // Job details
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Job type badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: widget.job.jobType == 'pickup'
                          ? AppTheme.errorRed.withValues(alpha: 0.1)
                          : AppTheme.teamMemberIconOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.job.jobType == 'pickup' ? 'PICKUP' : 'DELIVERY',
                      style: TextStyle(
                        color: widget.job.jobType == 'pickup'
                            ? AppTheme.errorRed
                            : AppTheme.teamMemberIconOrange,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Customer name (most important info)
                  _buildInfoRow(
                    icon: Icons.person_outline,
                    label: 'Customer',
                    value: widget.job.customerName ?? 'Unknown Customer',
                  ),
                  const SizedBox(height: 16),

                  // Job number
                  if (widget.job.jobNumber != null) ...[
                    _buildInfoRow(
                      icon: Icons.confirmation_number,
                      label: 'Job Number',
                      value: widget.job.jobNumber!,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Status
                  _buildInfoRow(
                    icon: Icons.info_outline,
                    label: 'Status',
                    value: _formatStatus(widget.job.status),
                  ),
                  const SizedBox(height: 16),

                  // Address
                  _buildInfoRow(
                    icon: Icons.location_on_outlined,
                    label: 'Address',
                    value: widget.job.address ?? 'No address provided',
                  ),
                  const SizedBox(height: 16),

                  // Landmark
                  if (widget.job.landmark != null) ...[
                    _buildInfoRow(
                      icon: Icons.place_outlined,
                      label: 'Landmark',
                      value: widget.job.landmark!,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Distance
                  if (_riderLocation != null && jobLocation != null) ...[
                    _buildInfoRow(
                      icon: Icons.straighten,
                      label: 'Distance',
                      value: _calculateDistance(_riderLocation!, jobLocation),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Coordinates
                  if (widget.job.latitude != null && widget.job.longitude != null) ...[
                    _buildInfoRow(
                      icon: Icons.gps_fixed,
                      label: 'Coordinates',
                      value: '${widget.job.latitude!.toStringAsFixed(6)}, ${widget.job.longitude!.toStringAsFixed(6)}',
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Start button
                  if (widget.job.status == 'pending')
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isStarting ? null : _startJob,
                        child: _isStarting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text('Start Job'),
                      ),
                    ),

                  // Already in progress
                  if (widget.job.status == 'in_progress')
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RiderJobTrackingScreen(job: widget.job),
                            ),
                          );
                        },
                        child: const Text('Continue Tracking'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppTheme.textLight),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textLight,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.textDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatStatus(String status) {
    return status.split('_').map((word) {
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  String _calculateDistance(LatLng from, LatLng to) {
    final distance = const Distance().as(LengthUnit.Kilometer, from, to);
    if (distance < 1) {
      return '${(distance * 1000).toStringAsFixed(0)}m';
    }
    return '${distance.toStringAsFixed(2)}km';
  }

  @override
  void dispose() {
    _gpsProvider.stopTracking();
    super.dispose();
  }
}
