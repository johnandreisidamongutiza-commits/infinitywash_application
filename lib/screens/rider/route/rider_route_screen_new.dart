import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_error.dart';
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
  List<DispatchJob> _completedPickupJobs = [];
  List<DispatchJob> _completedDeliveryJobs = [];
  bool _isLoading = false;
  String? _error;
  LatLng? _riderLocation;
  String _filter = 'all'; // 'all', 'pickup', 'delivery', 'completed'
  
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

      // Fetch active jobs (pending/in_progress only)
      final activePickupJobs = await _riderService.fetchActivePickupJobs();
      final activeDeliveryJobs = await _riderService.fetchActiveDeliveryJobs();
      
      // Fetch completed jobs (today only)
      final completedPickupJobs = await _riderService.fetchCompletedPickupJobs();
      final completedDeliveryJobs = await _riderService.fetchCompletedDeliveryJobs();
      
      print('🔍 DEBUG - Completed jobs fetched:');
      print('   Completed Pickups: ${completedPickupJobs.length}');
      print('   Completed Deliveries: ${completedDeliveryJobs.length}');
      if (completedPickupJobs.isNotEmpty) {
        print('   First pickup: ${completedPickupJobs.first.customerName} - ${completedPickupJobs.first.status}');
      }
      if (completedDeliveryJobs.isNotEmpty) {
        print('   First delivery: ${completedDeliveryJobs.first.customerName} - ${completedDeliveryJobs.first.status}');
      }
      
      if (mounted) {
        setState(() {
          _pickupJobs = activePickupJobs;
          _deliveryJobs = activeDeliveryJobs;
          _allJobs = [...activePickupJobs, ...activeDeliveryJobs]; // Only active jobs
          _completedPickupJobs = completedPickupJobs;
          _completedDeliveryJobs = completedDeliveryJobs;
          _isLoading = false;
        });

        print('✅ Jobs loaded:');
        print('   Active Pickups: ${_pickupJobs.length}');
        print('   Active Deliveries: ${_deliveryJobs.length}');
        print('   Completed Pickups: ${_completedPickupJobs.length}');
        print('   Completed Deliveries: ${_completedDeliveryJobs.length}');

        // Calculate route along roads
        await _calculateRoute();
        
        // Center map to show all jobs (including completed if needed)
        _fitMapToJobs();
      }
    } catch (e) {
      print('❌ Error loading jobs: $e');
      if (mounted) {
        setState(() {
          _error = mapErrorToMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  /// Calculate the actual road route through all job locations
  Future<void> _calculateRoute() async {
    // Don't calculate route for completed jobs view
    if (_filter == 'completed') {
      setState(() => _routePoints = []);
      return;
    }
    
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
    // Use filtered jobs to include completed jobs when on that tab
    final jobsWithCoords = _filteredJobs
        .where((j) => 
            j.latitude != null && 
            j.longitude != null &&
            j.latitude!.isFinite && 
            j.longitude!.isFinite)
        .toList();
    
    if (jobsWithCoords.isEmpty) {
      // If no jobs with coordinates, just center on shop
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          try {
            _mapController.move(LocationConstants.shopLocation, 13.0);
          } catch (e) {
            print('⚠️ Could not center map: $e');
          }
        }
      });
      return;
    }

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
    if (_filter == 'completed') {
      // Return ALL completed jobs together (pickups + deliveries)
      final completed = [..._completedPickupJobs, ..._completedDeliveryJobs];
      print('🔍 DEBUG - Filtered completed jobs: ${completed.length}');
      return completed;
    } else {
      // Active jobs only
      if (_filter == 'pickup') return _pickupJobs;
      if (_filter == 'delivery') return _deliveryJobs;
      return _allJobs; // all active
    }
  }

  void _recenterToRider() {
    if (_riderLocation != null) {
      _mapController.move(_riderLocation!, 15.0);
    } else {
      _mapController.move(LocationConstants.shopLocation, 14.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Route Overview',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: AppTheme.textDark,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: AppTheme.borderGray.withValues(alpha: 0.6),
            height: 1,
          ),
        ),
        leading: widget.onBackToHome != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
                onPressed: widget.onBackToHome,
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryBlue),
            tooltip: 'Refresh Route',
            onPressed: _isLoading ? null : _loadJobs,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
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
            const Icon(Icons.error_outline, size: 56, color: AppTheme.errorRed),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textDark, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadJobs,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilteredEmptyState() {
    String message;
    String subtitle;
    IconData icon;
    Color iconColor;

    switch (_filter) {
      case 'completed':
        message = 'No Completed Jobs Today';
        subtitle = 'Jobs you complete today will appear here.';
        icon = Icons.check_circle_outline;
        iconColor = Colors.green;
        break;
      case 'pickup':
        message = 'No Pickups Scheduled';
        subtitle = 'There are no active pickup jobs on your route.';
        icon = Icons.shopping_bag_outlined;
        iconColor = AppTheme.errorRed;
        break;
      case 'delivery':
        message = 'No Deliveries Scheduled';
        subtitle = 'There are no active delivery jobs on your route.';
        icon = Icons.local_shipping_outlined;
        iconColor = AppTheme.teamMemberIconOrange;
        break;
      default:
        final hasCompleted = _completedPickupJobs.isNotEmpty || _completedDeliveryJobs.isNotEmpty;
        if (hasCompleted) {
          message = 'All Stops Completed!';
          subtitle = 'Great work! Check the Completed tab to view details.';
        } else {
          message = 'No Jobs in Route';
          subtitle = 'Waiting for dispatch jobs to be assigned.';
        }
        icon = Icons.route_outlined;
        iconColor = AppTheme.primaryBlue;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: iconColor),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textLight,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteView() {
    final totalDistance = _calculateTotalDistance();
    final totalStops = _filteredJobs.length;

    return Column(
      children: [
        // Map Area
        Expanded(
          flex: 3,
          child: Stack(
            children: [
              FlutterMap(
                key: ValueKey('map_$_filter'),
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: LocationConstants.shopLocation,
                  initialZoom: 13.0,
                  minZoom: 12.0,
                  maxZoom: 18.0,
                  cameraConstraint: CameraConstraint.contain(
                    bounds: LatLngBounds(
                      LatLng(
                        LocationConstants.shopLocation.latitude - 0.09,
                        LocationConstants.shopLocation.longitude - 0.09,
                      ),
                      LatLng(
                        LocationConstants.shopLocation.latitude + 0.09,
                        LocationConstants.shopLocation.longitude + 0.09,
                      ),
                    ),
                  ),
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.infinitywash.app',
                    tileProvider: CachedTileProvider(),
                  ),
                  if (_routePoints.isNotEmpty)
                    PolylineLayer(polylines: _buildRouteLines()),
                  if (_buildMarkers().isNotEmpty)
                    MarkerLayer(markers: _buildMarkers()),
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: LocationConstants.shopLocation,
                        radius: LocationConstants.deliveryRadiusMeters,
                        useRadiusInMeter: true,
                        color: AppTheme.accentBlue.withValues(alpha: 0.08),
                        borderColor: AppTheme.accentBlue.withValues(alpha: 0.25),
                        borderStrokeWidth: 1.5,
                      ),
                    ],
                  ),
                ],
              ),

              // Floating Summary Bar
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: _buildStatsCard(totalDistance, totalStops),
              ),

              // Route Fallback Banner
              if (_isRouteFallback)
                Positioned(
                  top: 76,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade700,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline, color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'Showing direct path — road route unavailable',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),

              // Floating Map Quick-Controls
              Positioned(
                bottom: 12,
                right: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMapControlButton(
                      icon: Icons.crop_free,
                      tooltip: 'Fit All Stops',
                      onPressed: _fitMapToJobs,
                    ),
                    const SizedBox(height: 8),
                    _buildMapControlButton(
                      icon: Icons.my_location,
                      tooltip: 'My Location',
                      onPressed: _recenterToRider,
                    ),
                  ],
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

        // Filter Tabs
        _buildFilterTabs(),

        // Jobs List
        Expanded(
          flex: 2,
          child: _filteredJobs.isEmpty
              ? _buildFilteredEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  itemCount: _filteredJobs.length,
                  itemBuilder: (context, index) => _buildJobCard(_filteredJobs[index], index + 1),
                ),
        ),

        // Bottom Action Bar
        if (_allJobs.isNotEmpty && _filter != 'completed')
          _buildBottomActionBar(),
      ],
    );
  }

  Widget _buildStatsCard(double totalDistance, int totalStops) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            Icons.route_outlined,
            _isLoadingRoute ? '...' : '${totalDistance.toStringAsFixed(1)}km',
            'Distance',
            AppTheme.primaryBlue,
          ),
          _buildStatDivider(),
          _buildStatItem(Icons.pin_drop_outlined, '$totalStops', 'Stops', AppTheme.accentBlue),
          _buildStatDivider(),
          _buildStatItem(Icons.shopping_bag_outlined, '${_pickupJobs.length}', 'Pickups', AppTheme.errorRed),
          _buildStatDivider(),
          _buildStatItem(Icons.local_shipping_outlined, '${_deliveryJobs.length}', 'Deliveries', AppTheme.teamMemberIconOrange),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(
      height: 24,
      width: 1,
      color: AppTheme.borderGray.withValues(alpha: 0.7),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label, Color accentColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: accentColor),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppTheme.textLight,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildMapControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: 18, color: AppTheme.primaryBlue),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _buildFilterChip('All', _allJobs.length, 'all'),
            const SizedBox(width: 8),
            _buildFilterChip('Pickups', _pickupJobs.length, 'pickup', color: AppTheme.errorRed),
            const SizedBox(width: 8),
            _buildFilterChip('Deliveries', _deliveryJobs.length, 'delivery', color: AppTheme.teamMemberIconOrange),
            const SizedBox(width: 8),
            _buildFilterChip('Completed', _completedPickupJobs.length + _completedDeliveryJobs.length, 'completed', color: Colors.green),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int count, String value, {Color? color}) {
    final isSelected = _filter == value;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () async {
        setState(() => _filter = value);
        await _calculateRoute();
        _fitMapToJobs();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            try {
              final currentZoom = _mapController.camera.zoom;
              _mapController.move(_mapController.camera.center, currentZoom);
            } catch (e) {
              print('⚠️ Could not refresh map: $e');
            }
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue : AppTheme.softGray,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryBlue : AppTheme.borderGray,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppTheme.textDark,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.22)
                    : (color != null ? color.withValues(alpha: 0.12) : AppTheme.borderGray),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : (color ?? AppTheme.textDark),
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobCard(DispatchJob job, int number) {
    final isCompleted = _filter == 'completed';
    final isPickup = job.jobType == 'pickup';
    final accentColor = isCompleted
        ? Colors.green
        : (isPickup ? AppTheme.errorRed : AppTheme.teamMemberIconOrange);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: isCompleted ? const Color(0xFFF9FAFB) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCompleted ? AppTheme.borderGray.withValues(alpha: 0.6) : AppTheme.borderGray,
          width: 1,
        ),
        boxShadow: isCompleted
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RiderJobDetailsScreen(job: job),
              ),
            ).then((_) => _loadJobs());
          },
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Stop badge + Type tag + Job number
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isCompleted
                                ? Icons.check_circle
                                : (isPickup ? Icons.shopping_bag_outlined : Icons.local_shipping_outlined),
                            size: 13,
                            color: accentColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isCompleted
                                ? 'COMPLETED'
                                : (isPickup ? 'STOP #$number • PICKUP' : 'STOP #$number • DELIVERY'),
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (job.jobNumber != null)
                      Text(
                        job.jobNumber!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textLight,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Customer Name
                Text(
                  job.customerName ?? 'Unknown Customer',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isCompleted ? AppTheme.textLight : AppTheme.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),

                // Address
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textLight),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        job.address ?? 'No address provided',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textLight,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                // Landmark if present
                if (job.landmark != null && job.landmark!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.softGray,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.place_outlined, size: 12, color: AppTheme.accentBlue),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            job.landmark!,
                            style: const TextStyle(fontSize: 11, color: AppTheme.textDark),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Footer row: Completed time OR Details arrow
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (isCompleted && job.completedAt != null)
                      Row(
                        children: [
                          const Icon(Icons.check_circle_outline, size: 13, color: Colors.green),
                          const SizedBox(width: 4),
                          Text(
                            'Completed ${_formatCompletionTime(job.completedAt!)}',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'Tap to view order details',
                        style: TextStyle(
                          color: AppTheme.textLight.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                    const Icon(Icons.chevron_right, size: 18, color: AppTheme.textLight),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.borderGray.withValues(alpha: 0.6))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: () {
              if (_allJobs.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RiderActiveRouteScreen(jobs: _allJobs),
                  ),
                ).then((_) => _loadJobs());
              }
            },
            icon: const Icon(Icons.navigation_outlined, size: 18),
            label: Text(
              'Start Route (${_allJobs.length} ${_allJobs.length == 1 ? 'Stop' : 'Stops'})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
          ),
        ),
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

    // Shop hub marker
    markers.add(Marker(
      point: LocationConstants.shopLocation,
      width: 40,
      height: 40,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.local_laundry_service, color: Colors.white, size: 20),
      ),
    ));

    // Rider marker
    if (_riderLocation != null) {
      markers.add(Marker(
        point: _riderLocation!,
        width: 36,
        height: 36,
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.accentBlue.withValues(alpha: 0.25),
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(4),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.accentBlue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accentBlue.withValues(alpha: 0.4),
                  blurRadius: 6,
                ),
              ],
            ),
            child: const Icon(Icons.navigation, color: Colors.white, size: 14),
          ),
        ),
      ));
    }

    // Job markers
    final isCompleted = _filter == 'completed';
    for (int i = 0; i < _filteredJobs.length; i++) {
      final job = _filteredJobs[i];
      if (job.latitude == null || job.longitude == null) continue;
      if (!job.latitude!.isFinite || !job.longitude!.isFinite) continue;

      final Color markerColor = isCompleted
          ? Colors.green
          : (job.jobType == 'pickup' ? AppTheme.errorRed : AppTheme.teamMemberIconOrange);

      markers.add(Marker(
        point: LatLng(job.latitude!, job.longitude!),
        width: 34,
        height: 34,
        child: Container(
          decoration: BoxDecoration(
            color: markerColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: markerColor.withValues(alpha: 0.35),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ));
    }

    return markers;
  }

  double _calculateTotalDistance() {
    final validJobs = _filteredJobs
        .where((j) =>
            j.latitude != null &&
            j.longitude != null &&
            j.latitude!.isFinite &&
            j.longitude!.isFinite)
        .toList();

    if (validJobs.isEmpty || _riderLocation == null) return 0;

    const Distance distance = Distance();
    double total = 0;

    try {
      total += distance.as(
        LengthUnit.Kilometer,
        _riderLocation!,
        LatLng(validJobs.first.latitude!, validJobs.first.longitude!),
      );
    } catch (e) {
      print('⚠️ Error calculating distance to first job: $e');
    }

    for (int i = 0; i < validJobs.length - 1; i++) {
      final current = validJobs[i];
      final next = validJobs[i + 1];
      try {
        total += distance.as(
          LengthUnit.Kilometer,
          LatLng(current.latitude!, current.longitude!),
          LatLng(next.latitude!, next.longitude!),
        );
      } catch (e) {
        print('⚠️ Error calculating distance between jobs: $e');
      }
    }

    return total;
  }

  String _formatCompletionTime(DateTime completedAt) {
    final now = DateTime.now();
    final difference = now.difference(completedAt);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      final hour = completedAt.hour;
      final minute = completedAt.minute;
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return 'at $displayHour:${minute.toString().padLeft(2, '0')} $period';
    } else {
      return 'on ${completedAt.month}/${completedAt.day}';
    }
  }

  @override
  void dispose() {
    _gpsProvider.stopTracking();
    super.dispose();
  }
}
