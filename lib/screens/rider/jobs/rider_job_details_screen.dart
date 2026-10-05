import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../theme/app_theme.dart';
import '../../../models/dispatch_job.dart';
import '../../../services/rider_service.dart';
import '../../../config/location_constants.dart';
import '../../../state/gps_provider.dart';
import '../../../widgets/cached_tile_provider.dart';
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
  bool _takenByOther = false;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
    _verifyJobAvailable();
  }

  /// If this screen was opened from a stale list, another rider may have
  /// claimed the job in the meantime. Fail fast with a clear message.
  Future<void> _verifyJobAvailable() async {
    final available = await _riderService.isJobStillAvailable(widget.job.id);
    if (!available && mounted) {
      setState(() => _takenByOther = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This job has already been taken by another rider.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
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
    } on JobClaimedException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job already taken by another rider.'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
        setState(() {
          _isStarting = false;
          _takenByOther = true;
        });
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
                    minZoom: 12.0, // Restrict zoom out to keep within delivery area
                    maxZoom: 18.0,
                    // Restrict map bounds to 10km around shop
                    cameraConstraint: CameraConstraint.contain(
                      bounds: LatLngBounds(
                        // Southwest corner (10km south and west of shop)
                        LatLng(
                          LocationConstants.shopLocation.latitude - 0.09, // ~10km south
                          LocationConstants.shopLocation.longitude - 0.09, // ~10km west
                        ),
                        // Northeast corner (10km north and east of shop)
                        LatLng(
                          LocationConstants.shopLocation.latitude + 0.09, // ~10km north
                          LocationConstants.shopLocation.longitude + 0.09, // ~10km east
                        ),
                      ),
                    ),
                    // Keep map centered on delivery area when user interacts
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.infinitywash.app',
                      tileProvider: CachedTileProvider(), // Use cached tiles
                    ),
                    // Shop delivery radius circle & customer meetup radius circle
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: LocationConstants.shopLocation,
                          radius: LocationConstants.deliveryRadiusMeters,
                          useRadiusInMeter: true,
                          color: AppTheme.accentBlue.withValues(alpha: 0.1),
                          borderColor: AppTheme.accentBlue.withValues(alpha: 0.3),
                          borderStrokeWidth: 2,
                        ),
                        // 20-meter customer meetup zone
                        CircleMarker(
                          point: jobLocation,
                          radius: LocationConstants.customerMeetingRadiusMeters,
                          useRadiusInMeter: true,
                          color: Colors.green.withValues(alpha: 0.22),
                          borderColor: Colors.green.shade700,
                          borderStrokeWidth: 2,
                        ),
                      ],
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

                  // Taken by another rider — replaces the Start button
                  if (_takenByOther)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.errorRed.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.do_not_disturb_on, color: AppTheme.errorRed),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'This job was taken by another rider.',
                              style: TextStyle(color: AppTheme.errorRed, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // No map pin on this job — warn the rider instead of routing them somewhere wrong.
                  if (jobLocation == null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.location_off, color: Colors.orange),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No map pin for this job — use the address and call the customer if needed.',
                              style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Start button
                  if (widget.job.status == 'pending' && !_takenByOther)
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
