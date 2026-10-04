import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../theme/app_theme.dart';
import '../../../models/dispatch_job.dart';
import '../../../services/routing_service.dart';
import '../../../config/location_constants.dart';
import '../../../state/gps_provider.dart';
import '../../../widgets/map_loading_overlay.dart';
import '../../../widgets/cached_tile_provider.dart';
import '../jobs/rider_job_details_screen.dart';

/// Active Route Tracking Screen
/// Shows rider's live location centered on map with rotating arrow pointing to next destination
class RiderActiveRouteScreen extends StatefulWidget {
  final List<DispatchJob> jobs;

  const RiderActiveRouteScreen({super.key, required this.jobs});

  @override
  State<RiderActiveRouteScreen> createState() => _RiderActiveRouteScreenState();
}

class _RiderActiveRouteScreenState extends State<RiderActiveRouteScreen> {
  final MapController _mapController = MapController();
  final RoutingService _routingService = RoutingService();
  final GpsProvider _gpsProvider = GpsProvider();
  
  LatLng? _currentLocation;
  double _currentBearing = 0.0; // Direction rider is facing/moving
  List<DispatchJob> _remainingJobs = [];
  List<LatLng> _routePoints = [];
  bool _isRouteFallback = false;
  int _currentJobIndex = 0;
  StreamSubscription? _locationSubscription;
  bool _isLoadingRoute = false;
  bool _isMapLoading = true; // Track map loading state

  @override
  void initState() {
    super.initState();
    _remainingJobs = List.from(widget.jobs);
    _initializeTracking();
    
    // Hide loading after 2 seconds (map tiles should be loaded by then)
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isMapLoading = false);
      }
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _gpsProvider.stopTracking();
    super.dispose();
  }

  Future<void> _initializeTracking() async {
    try {
      await _gpsProvider.initialize();
      await _gpsProvider.startTracking();
      
      // Listen to location updates
      _locationSubscription = _gpsProvider.locationStream.listen((location) {
        if (mounted && location.latitude != null && location.longitude != null) {
          final newLocation = LatLng(location.latitude!, location.longitude!);
          
          final isFirstLocation = _currentLocation == null;
          
          setState(() {
            final oldLocation = _currentLocation;
            _currentLocation = newLocation;
            
            // Calculate bearing (direction of movement)
            if (oldLocation != null && _remainingJobs.isNotEmpty) {
              _currentBearing = _calculateBearing(
                _currentLocation!,
                LatLng(_remainingJobs.first.latitude!, _remainingJobs.first.longitude!),
              );
            }
          });

          // Center map on rider's location
          _mapController.move(_currentLocation!, 17.0);
          
          // Recalculate route when location first acquired or every 10 seconds
          if (isFirstLocation) {
            _calculateRoute();
          }
        }
      });

      // Calculate initial route
      await _calculateRoute();
    } catch (e) {
      print('❌ Error initializing tracking: $e');
    }
  }

  /// Calculate bearing (angle) from current location to target
  double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final bearing = math.atan2(y, x);
    return (bearing * 180 / math.pi + 360) % 360; // Convert to degrees (0-360)
  }

  /// Calculate distance in meters between two points
  double _calculateDistance(LatLng from, LatLng to) {
    const distance = Distance();
    return distance.as(LengthUnit.Meter, from, to);
  }

  Future<void> _calculateRoute() async {
    if (_remainingJobs.isEmpty) {
      print('⚠️ No remaining jobs to calculate route');
      setState(() => _routePoints = []);
      return;
    }
    
    if (_currentLocation == null) {
      print('⚠️ Current location is null, cannot calculate route');
      setState(() => _routePoints = []);
      return;
    }

    print('🔵 Calculating route from ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
    setState(() => _isLoadingRoute = true);

    try {
      final waypoints = <LatLng>[_currentLocation!];
      
      for (final job in _remainingJobs) {
        if (job.latitude != null && job.longitude != null) {
          waypoints.add(LatLng(job.latitude!, job.longitude!));
          print('  → Adding waypoint: ${job.latitude}, ${job.longitude} (${job.jobType})');
        }
      }

      if (waypoints.length < 2) {
        print('⚠️ Not enough waypoints for route calculation');
        setState(() {
          _routePoints = [];
          _isLoadingRoute = false;
        });
        return;
      }

      print('🔵 Requesting route with ${waypoints.length} waypoints...');
      final route = await _routingService.getRouteResult(waypoints);

      print(
        '${route.isFallback ? '⚠️ Fallback' : '✅'} route with ${route.points.length} points'
        '${route.error != null ? ' (${route.error})' : ''}',
      );

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
        setState(() {
          _routePoints = [];
          _isRouteFallback = false;
          _isLoadingRoute = false;
        });
      }
    }
  }

  void _completeCurrentJob() async {
    if (_remainingJobs.isEmpty) return;

    setState(() {
      _remainingJobs.removeAt(0);
      _currentJobIndex++;
    });

    if (_remainingJobs.isEmpty) {
      // All jobs completed!
      _showCompletionDialog();
    } else {
      // Recalculate route to next job
      await _calculateRoute();
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Route Completed! 🎉'),
        content: const Text('All deliveries have been completed.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Go back to route overview
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nextJob = _remainingJobs.isNotEmpty ? _remainingJobs.first : null;
    final distanceToNext = _currentLocation != null && nextJob?.latitude != null
        ? _calculateDistance(
            _currentLocation!,
            LatLng(nextJob!.latitude!, nextJob.longitude!),
          )
        : 0.0;

    return Scaffold(
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation ?? const LatLng(14.2499596, 121.4027956),
              initialZoom: 17.0,
              minZoom: 12.0,
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
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.infinitywash.app',
                tileProvider: CachedTileProvider(), // Use cached tiles
              ),
              // Shop delivery radius circle & customer meetup radius circles
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
                  ..._remainingJobs
                      .where((j) => j.latitude != null && j.longitude != null)
                      .map(
                        (j) => CircleMarker(
                          point: LatLng(j.latitude!, j.longitude!),
                          radius: LocationConstants.customerMeetingRadiusMeters,
                          useRadiusInMeter: true,
                          color: Colors.green.withValues(alpha: 0.22),
                          borderColor: Colors.green.shade700,
                          borderStrokeWidth: 2,
                        ),
                      ),
                ],
              ),
              // Route line
              if (_isLoadingRoute)
                // Show loading indicator
                const Center(
                  child: Card(
                    margin: EdgeInsets.all(16),
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Calculating route...'),
                        ],
                      ),
                    ),
                  ),
                )
              else if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: _isRouteFallback ? 3.0 : 5.0,
                      color: _isRouteFallback
                          ? AppTheme.textLight
                          : AppTheme.accentBlue,
                      pattern: _isRouteFallback
                          ? StrokePattern.dashed(segments: [10, 6])
                          : StrokePattern.solid(),
                    ),
                  ],
                ),
              // Markers
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),

          // Top info card
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Text(
                          'Stop ${_currentJobIndex + 1} of ${widget.jobs.length}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Column(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: _calculateRoute,
                            ),
                            if (_routePoints.isNotEmpty)
                              Text(
                                '${_routePoints.length}',
                                style: const TextStyle(fontSize: 8, color: Colors.green),
                              ),
                          ],
                        ),
                      ],
                    ),
                    if (nextJob != null) ...[
                      const Divider(),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: nextJob.jobType == 'pickup'
                              ? AppTheme.errorRed
                              : AppTheme.teamMemberIconOrange,
                          child: Icon(
                            nextJob.jobType == 'pickup'
                                ? Icons.local_shipping
                                : Icons.home,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          nextJob.address ?? 'No address',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${(distanceToNext / 1000).toStringAsFixed(2)} km away',
                          style: const TextStyle(color: AppTheme.textLight),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.info_outline),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RiderJobDetailsScreen(job: nextJob),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Bottom action button
          if (nextJob != null)
            Positioned(
              bottom: 32,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_isLoadingRoute &&
                      (_routePoints.isEmpty || _isRouteFallback))
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning, color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _currentLocation == null
                                  ? 'Waiting for GPS'
                                  : _isRouteFallback
                                      ? 'Showing straight line — road route unavailable. Tap refresh to retry.'
                                      : 'No route: tap refresh',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentBlue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: () {
                      // Check if rider is close enough to complete (within 50 meters)
                      if (distanceToNext < 50) {
                        _completeCurrentJob();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'You need to be within 50m to complete this stop (currently ${(distanceToNext).toStringAsFixed(0)}m away)',
                            ),
                            backgroundColor: AppTheme.errorRed,
                          ),
                        );
                      }
                    },
                    child: Text(
                      distanceToNext < 50 ? 'Complete Stop' : 'Arrive to Complete',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // Map loading overlay
          MapLoadingOverlay(
            isLoading: _isMapLoading,
            message: 'Loading route map...',
          ),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Rider's current location with rotating arrow
    if (_currentLocation != null) {
      markers.add(
        Marker(
          point: _currentLocation!,
          width: 60,
          height: 60,
          alignment: Alignment.center,
          child: Transform.rotate(
            angle: _currentBearing * math.pi / 180, // Convert degrees to radians
            child: Icon(
              Icons.navigation,
              size: 40,
              color: AppTheme.accentBlue,
              shadows: [
                Shadow(
                  blurRadius: 4,
                  color: Colors.black.withValues(alpha: 0.5),
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Job markers
    int index = 0;
    for (final job in _remainingJobs) {
      if (job.latitude != null && job.longitude != null) {
        markers.add(
          Marker(
            point: LatLng(job.latitude!, job.longitude!),
            width: 80,
            height: 80,
            alignment: Alignment.center,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: index == 0
                        ? AppTheme.errorRed
                        : AppTheme.teamMemberIconOrange,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_drop_down,
                  color: Colors.red,
                  size: 24,
                ),
              ],
            ),
          ),
        );
        index++;
      }
    }

    return markers;
  }
}
