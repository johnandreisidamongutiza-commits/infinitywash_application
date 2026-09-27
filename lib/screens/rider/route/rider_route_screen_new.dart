import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../theme/app_theme.dart';
import '../../../models/dispatch_job.dart';
import '../../../services/rider_service.dart';
import '../../../services/supabase_service.dart';
import '../../../services/routing_service.dart';
import '../../../config/location_constants.dart';
import '../../../state/gps_provider.dart';
import '../../../widgets/map_loading_overlay.dart';
import '../../../widgets/cached_tile_provider.dart';
import '../jobs/rider_job_details_screen.dart';
import 'rider_active_route_screen.dart';

/// Route Overview Screen - Shows rider's route with all stops
/// Displays real map with route lines from Supabase data
class RiderRouteScreenNew extends StatefulWidget {
  final VoidCallback? onBackToHome;

  const RiderRouteScreenNew({super.key, this.onBackToHome});

  @override
  State<RiderRouteScreenNew> createState() => _RiderRouteScreenNewState();
}

class _RiderRouteScreenNewState extends State<RiderRouteScreenNew> {
  final MapController _mapController = MapController();
  final RiderService _riderService = RiderService();
  final RoutingService _routingService = RoutingService();
  final GpsProvider _gpsProvider = GpsProvider();
  
  List<DispatchJob> _allJobs = [];
  List<DispatchJob> _pickupJobs = [];
  List<DispatchJob> _deliveryJobs = [];
  bool _isLoading = false;
  String? _error;
  LatLng? _riderLocation;
  String _filter = 'all'; // 'all', 'pickup', 'delivery'
  
  // Cache for route points following roads
  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = false;
  bool _isRouteFallback = false;
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
      if (riderId == null) {
        throw Exception('Not authenticated');
      }

      final jobs = await _riderService.getRiderJobs(riderId);
      
      if (mounted) {
        setState(() {
          _allJobs = jobs;
          _pickupJobs = jobs.where((j) => j.jobType == 'pickup').toList();
          _deliveryJobs = jobs.where((j) => j.jobType == 'delivery').toList();
          _isLoading = false;
        });

        // Calculate route along roads
        await _calculateRoute();
        
        // Center map to show all jobs
        if (jobs.isNotEmpty) {
          _fitMapToJobs();
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

  /// Calculate the actual road route through all job locations
  Future<void> _calculateRoute() async {
    if (_filteredJobs.isEmpty) {
      setState(() => _routePoints = []);
      return;
    }

    setState(() => _isLoadingRoute = true);

    try {
      // Build waypoints list
      final waypoints = <LatLng>[];
      
      // Start from rider's current location or shop
      if (_riderLocation != null) {
        waypoints.add(_riderLocation!);
      } else {
        waypoints.add(LocationConstants.shopLocation);
      }
      
      // Add all job locations
      for (final job in _filteredJobs) {
        if (job.latitude != null && job.longitude != null) {
          waypoints.add(LatLng(job.latitude!, job.longitude!));
        }
      }

      // Get route from routing service (ORS / OSRM with road snapping)
      final route = await _routingService.getRouteResult(waypoints);

      if (mounted) {
        setState(() {
          _routePoints = route.points;
          _isRouteFallback = route.isFallback;
          _isLoadingRoute = false;
        });
      }
    } catch (e) {
      print('❌ Error calculating route: $e');
      if (mounted) {
        setState(() => _isLoadingRoute = false);
      }
    }
  }

  void _fitMapToJobs() {
    final jobsWithCoords = _allJobs.where((j) => j.latitude != null && j.longitude != null).toList();
    if (jobsWithCoords.isEmpty) return;

    final points = jobsWithCoords.map((j) => LatLng(j.latitude!, j.longitude!)).toList();
    points.add(LocationConstants.shopLocation);
    if (_riderLocation != null) points.add(_riderLocation!);

    final bounds = LatLngBounds.fromPoints(points);
    
    // Delay until after map is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)));
        } catch (e) {
          print('⚠️ Could not fit map bounds: $e');
        }
      }
    });
  }

  List<DispatchJob> get _filteredJobs {
    if (_filter == 'pickup') return _pickupJobs;
    if (_filter == 'delivery') return _deliveryJobs;
    return _allJobs;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Route Overview'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: widget.onBackToHome != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBackToHome,
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadJobs,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : _allJobs.isEmpty
                  ? _buildEmptyState()
                  : _buildRouteView(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppTheme.errorRed),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadJobs,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.route_outlined, size: 64, color: AppTheme.textLight.withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text(
            'No route today',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Check Jobs tab for new assignments',
            style: TextStyle(color: AppTheme.textLight),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteView() {
    final totalDistance = _calculateTotalDistance();
    final totalStops = _filteredJobs.length;

    return Column(
      children: [
        // Map
        Expanded(
          flex: 3,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: LocationConstants.shopLocation,
                  initialZoom: 13.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.infinitywash.app',
                    tileProvider: CachedTileProvider(), // Use cached tiles
                  ),
                  // Route lines
                  if (_routePoints.isNotEmpty)
                    PolylineLayer(polylines: _buildRouteLines()),
                  // Markers
                  MarkerLayer(markers: _buildMarkers()),
                ],
              ),
              // Stats overlay
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem(Icons.straighten, '${totalDistance.toStringAsFixed(1)}km', 'Distance'),
                        _buildStatItem(Icons.location_on, '$totalStops', 'Stops'),
                        _buildStatItem(Icons.local_shipping, '${_pickupJobs.length}', 'Pickups'),
                        _buildStatItem(Icons.home, '${_deliveryJobs.length}', 'Deliveries'),
                      ],
                    ),
                  ),
                ),
              ),
              if (_isRouteFallback)
                Positioned(
                  top: 96,
                  left: 16,
                  right: 16,
                  child: Material(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(
                        'Showing straight line — road route unavailable.',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              // Map loading overlay
              MapLoadingOverlay(
                isLoading: _isMapLoading,
                message: 'Loading route overview...',
              ),
            ],
          ),
        ),

        // Jobs list
        Expanded(
          flex: 2,
          child: Column(
            children: [
              // Filter tabs
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    _buildFilterTab('All (${_allJobs.length})', 'all'),
                    const SizedBox(width: 8),
                    _buildFilterTab('Pickups (${_pickupJobs.length})', 'pickup'),
                    const SizedBox(width: 8),
                    _buildFilterTab('Deliveries (${_deliveryJobs.length})', 'delivery'),
                  ],
                ),
              ),
              // Jobs list
              Expanded(
                child: _filteredJobs.isEmpty
                    ? Center(
                        child: Text(
                          'No $_filter jobs',
                          style: const TextStyle(color: AppTheme.textLight),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredJobs.length,
                        itemBuilder: (context, index) => _buildJobCard(_filteredJobs[index], index + 1),
                      ),
              ),
            ],
          ),
        ),

        // Start route button
        if (_allJobs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  // Navigate to active route tracking screen
                  if (_allJobs.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RiderActiveRouteScreen(jobs: _allJobs),
                      ),
                    ).then((_) => _loadJobs());
                  }
                },
                child: const Text('Start This Route'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppTheme.textLight),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
        ),
      ],
    );
  }

  Widget _buildFilterTab(String label, String value) {
    final isSelected = _filter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          setState(() => _filter = value);
          // Recalculate route when filter changes
          await _calculateRoute();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.accentBlue : AppTheme.softGray,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
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

  Widget _buildJobCard(DispatchJob job, int number) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: job.jobType == 'pickup' ? AppTheme.errorRed : AppTheme.teamMemberIconOrange,
          child: Text(
            '$number',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(job.address ?? 'No address'),
        subtitle: Text(
          '${job.jobType == 'pickup' ? 'Pickup' : 'Delivery'} • ${job.status}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RiderJobDetailsScreen(job: job),
            ),
          ).then((_) => _loadJobs());
        },
      ),
    );
  }

  List<Polyline> _buildRouteLines() {
    if (_routePoints.isEmpty) return [];

    return [
      Polyline(
        points: _routePoints,
        strokeWidth: _isRouteFallback ? 3.0 : 4.0,
        color: _isRouteFallback ? AppTheme.textLight : AppTheme.accentBlue,
        pattern: _isRouteFallback
            ? StrokePattern.dashed(segments: [10, 6])
            : StrokePattern.solid(),
      ),
    ];
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    
    // Shop marker
    markers.add(Marker(
      point: LocationConstants.shopLocation,
      width: 40,
      height: 40,
      child: const Icon(Icons.store, color: AppTheme.accentBlue, size: 40),
    ));
    
    // Rider marker
    if (_riderLocation != null) {
      markers.add(Marker(
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
      ));
    }
    
    // Job markers
    for (int i = 0; i < _filteredJobs.length; i++) {
      final job = _filteredJobs[i];
      if (job.latitude == null) continue;
      
      markers.add(Marker(
        point: LatLng(job.latitude!, job.longitude!),
        width: 40,
        height: 40,
        child: Stack(
          children: [
            Icon(
              Icons.location_on,
              color: job.jobType == 'pickup' ? AppTheme.errorRed : AppTheme.teamMemberIconOrange,
              size: 40,
            ),
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Text(
                '${i + 1}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ));
    }
    
    return markers;
  }

  double _calculateTotalDistance() {
    if (_filteredJobs.isEmpty || _riderLocation == null) return 0;
    
    const Distance distance = Distance();
    double total = 0;
    
    // Distance to first job
    if (_filteredJobs.first.latitude != null) {
      total += distance.as(
        LengthUnit.Kilometer,
        _riderLocation!,
        LatLng(_filteredJobs.first.latitude!, _filteredJobs.first.longitude!),
      );
    }
    
    // Distance between jobs
    for (int i = 0; i < _filteredJobs.length - 1; i++) {
      final current = _filteredJobs[i];
      final next = _filteredJobs[i + 1];
      if (current.latitude != null && next.latitude != null) {
        total += distance.as(
          LengthUnit.Kilometer,
          LatLng(current.latitude!, current.longitude!),
          LatLng(next.latitude!, next.longitude!),
        );
      }
    }
    
    return total;
  }

  @override
  void dispose() {
    _gpsProvider.stopTracking();
    super.dispose();
  }
}
