import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../theme/app_theme.dart';
import '../../../models/dispatch_job.dart';
import '../../../services/rider_service.dart';
import '../../../services/supabase_service.dart';
import '../../../config/location_constants.dart';
import '../../../state/gps_provider.dart';
import '../../../widgets/map_loading_overlay.dart';
import '../../../widgets/cached_tile_provider.dart';
import 'rider_job_details_screen.dart';

/// Rider jobs screen with interactive map
/// Shows all assigned jobs as markers on the map
/// Allows rider to explore map and tap on jobs
class RiderJobsMapScreen extends StatefulWidget {
  const RiderJobsMapScreen({super.key});

  @override
  State<RiderJobsMapScreen> createState() => _RiderJobsMapScreenState();
}

class _RiderJobsMapScreenState extends State<RiderJobsMapScreen> {
  final MapController _mapController = MapController();
  final RiderService _riderService = RiderService();
  final GpsProvider _gpsProvider = GpsProvider();
  
  List<DispatchJob> _allJobs = [];
  List<DispatchJob> _filteredJobs = [];
  bool _isLoading = false;
  String? _error;
  String _filter = 'all'; // 'all', 'pickup', 'delivery'
  LatLng? _riderLocation;
  bool _isMapLoading = true; // Track map loading state

  @override
  void initState() {
    super.initState();
    _initializeLocation();
    _loadJobs();
    
    // Hide loading after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isMapLoading = false);
      }
    });
  }

  Future<void> _initializeLocation() async {
    try {
      await _gpsProvider.initialize();
      await _gpsProvider.startTracking();
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

  Future<void> _loadJobs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final riderId = SupabaseService.client.auth.currentUser?.id;
      print('🔍 Current rider ID: $riderId');
      print('🔍 Current user email: ${SupabaseService.client.auth.currentUser?.email}');
      
      if (riderId == null) {
        throw Exception('Not authenticated');
      }

      // Fetch all jobs for the rider
      final jobs = await _riderService.getRiderJobs(riderId);
      print('🔍 Fetched ${jobs.length} jobs from Supabase');
      
      if (mounted) {
        setState(() {
          _allJobs = jobs;
          _applyFilter();
          _isLoading = false;
        });

        print('✅ Loaded ${jobs.length} jobs for rider');
        
        // Center map on first job or shop if no jobs
        if (jobs.isNotEmpty && jobs.first.latitude != null && jobs.first.longitude != null) {
          _mapController.move(
            LatLng(jobs.first.latitude!, jobs.first.longitude!),
            14.0,
          );
        } else {
          _mapController.move(LocationConstants.shopLocation, 14.0);
        }
      }
    } catch (e) {
      print('❌ Error loading jobs: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilter() {
    if (_filter == 'all') {
      _filteredJobs = _allJobs;
    } else if (_filter == 'pickup') {
      _filteredJobs = _allJobs.where((j) => j.jobType == 'pickup').toList();
    } else if (_filter == 'delivery') {
      _filteredJobs = _allJobs.where((j) => j.jobType == 'delivery').toList();
    }
  }

  void _setFilter(String filter) {
    setState(() {
      _filter = filter;
      _applyFilter();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Jobs Map'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadJobs,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LocationConstants.shopLocation,
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
              MarkerLayer(
                markers: _buildMarkers(),
              ),
              // Shop delivery radius circle
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
                ],
              ),
            ],
          ),

          // Map loading overlay
          MapLoadingOverlay(
            isLoading: _isMapLoading,
            message: 'Loading jobs map...',
          ),

          // Filter chips at top
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    _buildFilterChip('All', 'all', _allJobs.length),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'Pickups',
                      'pickup',
                      _allJobs.where((j) => j.jobType == 'pickup').length,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'Deliveries',
                      'delivery',
                      _allJobs.where((j) => j.jobType == 'delivery').length,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Loading indicator
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading jobs...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Error display
          if (_error != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Card(
                color: AppTheme.errorRed,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _loadJobs,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Empty state
          if (!_isLoading && _error == null && _filteredJobs.isEmpty)
            Center(
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 64,
                        color: AppTheme.textLight.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No jobs available',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Check back later for new assignments',
                        style: TextStyle(color: AppTheme.textLight),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Center on rider location
          if (_riderLocation != null)
            FloatingActionButton(
              heroTag: 'center_rider',
              mini: true,
              onPressed: () {
                if (_riderLocation != null) {
                  _mapController.move(_riderLocation!, 15.0);
                }
              },
              child: const Icon(Icons.my_location),
            ),
          const SizedBox(height: 8),
          // Center on shop
          FloatingActionButton(
            heroTag: 'center_shop',
            mini: true,
            onPressed: () {
              _mapController.move(LocationConstants.shopLocation, 14.0);
            },
            child: const Icon(Icons.store),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, int count) {
    final isSelected = _filter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setFilter(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.accentBlue : AppTheme.softGray,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$label ($count)',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : AppTheme.textDark,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Add shop marker
    markers.add(
      Marker(
        point: LocationConstants.shopLocation,
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () {
            _showShopInfo();
          },
          child: const Icon(
            Icons.store,
            color: AppTheme.accentBlue,
            size: 40,
          ),
        ),
      ),
    );

    // Add rider location marker
    if (_riderLocation != null) {
      markers.add(
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
            child: const Icon(
              Icons.navigation,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      );
    }

    // Add job markers
    for (final job in _filteredJobs) {
      if (job.latitude == null || job.longitude == null) continue;

      markers.add(
        Marker(
          point: LatLng(job.latitude!, job.longitude!),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _showJobDetails(job),
            child: Stack(
              children: [
                Icon(
                  Icons.location_on,
                  color: job.jobType == 'pickup'
                      ? AppTheme.errorRed
                      : AppTheme.teamMemberIconOrange,
                  size: 40,
                ),
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: Icon(
                    job.jobType == 'pickup' ? Icons.arrow_upward : Icons.arrow_downward,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return markers;
  }

  void _showShopInfo() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.store, size: 48, color: AppTheme.accentBlue),
            const SizedBox(height: 16),
            const Text(
              'Infinity Wash Shop',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Bubukal, Sta Cruz, Laguna',
              style: TextStyle(color: AppTheme.textLight),
            ),
            const SizedBox(height: 16),
            Text(
              '${LocationConstants.deliveryRadiusKm}km delivery radius',
              style: const TextStyle(color: AppTheme.textLight),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accentBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, size: 16, color: AppTheme.accentBlue),
                  SizedBox(width: 8),
                  Text(
                    'Map view limited to delivery area',
                    style: TextStyle(fontSize: 12, color: AppTheme.accentBlue),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showJobDetails(DispatchJob job) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RiderJobDetailsScreen(job: job),
      ),
    ).then((_) => _loadJobs()); // Refresh after returning
  }

  @override
  void dispose() {
    _gpsProvider.stopTracking();
    super.dispose();
  }
}
