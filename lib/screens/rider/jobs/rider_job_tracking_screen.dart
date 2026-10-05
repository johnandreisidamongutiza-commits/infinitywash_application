import 'dart:async';
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
import '../../../state/rider_location_provider.dart';
import '../../../widgets/map_loading_overlay.dart';
import '../../../widgets/cached_tile_provider.dart';
import '../payments/rider_payment_process_screen.dart';

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
  final RoutingService _routingService = RoutingService();
  
  LatLng? _riderLocation;
  StreamSubscription? _locationSubscription;
  bool _isCompleting = false;
  int _updateCount = 0;
  bool _isMapLoading = true; // Track map loading state
  
  // Route calculation
  List<LatLng> _routePoints = [];
  bool _isRouteFallback = false;
  bool _isLoadingRoute = false;
  
  // Performance optimization - throttling & debouncing
  DateTime? _lastMapUpdate;
  Timer? _routeCalculationTimer;
  static const _mapUpdateInterval = Duration(seconds: 2);
  static const _routeDebounceDelay = Duration(seconds: 5);
  
  // Cache job location to avoid repeated calculations
  LatLng? _cachedJobLocation;
  
  @override
  void initState() {
    super.initState();
    // Cache job location once
    if (widget.job.latitude != null && widget.job.longitude != null) {
      _cachedJobLocation = LatLng(widget.job.latitude!, widget.job.longitude!);
    }
    _initializeLocation();
    
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
          final isFirstLocation = _riderLocation == null;
          final newLocation = LatLng(locationData.latitude!, locationData.longitude!);
          
          // Update state immediately for marker position
          setState(() {
            _riderLocation = newLocation;
            _updateCount++;
          });
          
          // Throttle map center updates to reduce render pressure
          if (_shouldUpdateMapCenter()) {
            _mapController.move(_riderLocation!, 15.0);
            _lastMapUpdate = DateTime.now();
          }
          
          // Calculate route immediately on first location
          if (isFirstLocation) {
            _calculateRoute();
          } else {
            // Debounce route recalculation for subsequent updates
            _debounceRouteCalculation();
          }
        }
      });
    } catch (e) {
      print('❌ Error starting tracking: $e');
    }
  }

  /// Check if enough time has passed to update map center (throttle)
  bool _shouldUpdateMapCenter() {
    if (_lastMapUpdate == null) return true;
    final elapsed = DateTime.now().difference(_lastMapUpdate!);
    return elapsed >= _mapUpdateInterval;
  }

  /// Debounce route calculation to avoid excessive API calls
  void _debounceRouteCalculation() {
    // Cancel existing timer if any
    _routeCalculationTimer?.cancel();
    
    // Start new timer - only calculates if no updates for 5 seconds
    _routeCalculationTimer = Timer(_routeDebounceDelay, () {
      if (mounted) {
        _calculateRoute();
      }
    });
  }

  /// Calculate the actual road route from rider to job location
  Future<void> _calculateRoute() async {
    // Use cached job location
    if (_riderLocation == null || _cachedJobLocation == null) {
      setState(() => _routePoints = []);
      return;
    }

    setState(() => _isLoadingRoute = true);

    try {
      final waypoints = [_riderLocation!, _cachedJobLocation!];
      final route = await _routingService.getRouteResult(waypoints);

      if (mounted) {
        setState(() {
          _routePoints = route.points;
          _isRouteFallback = route.isFallback;
          _isLoadingRoute = false;
        });
        
        if (route.isFallback) {
          print('⚠️ Using fallback straight-line route');
        } else {
          print('✅ Road route calculated with ${route.points.length} points');
        }
      }
    } catch (e) {
      print('❌ Error calculating route: $e');
      if (mounted) {
        setState(() {
          _routePoints = [];
          _isLoadingRoute = false;
        });
      }
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

    bool isOrderPaid = false;

    // Check payment status before closing the job
    try {
      final paymentInfo = await _riderService.getOrderPaymentInfo(widget.job.orderId);
      final paymentStatus = paymentInfo?['payment_status'] as String? ?? 'pending';
      isOrderPaid = (paymentStatus == 'paid');

      if (!isOrderPaid && mounted) {
        final double totalAmount = (paymentInfo?['total_amount'] as num?)?.toDouble() ??
            (paymentInfo?['subtotal'] as num?)?.toDouble() ??
            170.0;

        final shouldPay = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.payments_outlined, color: AppTheme.accentBlue),
                SizedBox(width: 8),
                Text('Payment Due'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This order has an unpaid balance of ₱${totalAmount.toStringAsFixed(2)}.',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Would you like to collect payment now via Cash or GCash?',
                  style: TextStyle(fontSize: 12, color: AppTheme.textLight),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Skip / Pay Later', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Collect Payment', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );

        if (shouldPay == true && mounted) {
          final order = await _riderService.fetchOrderById(widget.job.orderId);
          if (!mounted) return;

          final paid = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => RiderPaymentProcessScreen(
                order: order,
                orderId: widget.job.orderId,
                customerName: widget.job.customerName,
                address: widget.job.address,
                amount: totalAmount,
                jobType: widget.job.jobType,
              ),
            ),
          );

          if (!mounted) return;
          if (paid == true) {
            isOrderPaid = true;
          } else {
            final continueAnyway = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Payment Skipped'),
                content: const Text('Payment was not recorded. Mark the job as complete anyway?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Go Back'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Complete Anyway'),
                  ),
                ],
              ),
            );

            if (continueAnyway != true) return;
          }
        }
      }
    } catch (e) {
      print('⚠️ Non-critical error checking payment status: $e');
    }

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
          SnackBar(
            content: Row(
              children: [
                Icon(
                  isOrderPaid ? Icons.check_circle : Icons.info_outline,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isOrderPaid
                        ? 'Job completed & payment recorded!'
                        : 'Job completed! Payment pending — collect anytime in the Payment tab.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: isOrderPaid ? Colors.green : Colors.blueGrey.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mapErrorToMessage(e)),
            backgroundColor: AppTheme.errorRed,
          ),
        );
        setState(() => _isCompleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use cached job location to avoid repeated null checks and object creation
    final jobLocation = _cachedJobLocation;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: jobLocation ?? LocationConstants.shopLocation,
              initialZoom: 15.0,
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
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
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
                  if (jobLocation != null)
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
              // Route line following roads
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: _isRouteFallback ? 3.0 : 4.0,
                      color: _isRouteFallback ? AppTheme.textLight : AppTheme.accentBlue,
                      pattern: _isRouteFallback
                          ? StrokePattern.dashed(segments: [10, 6])
                          : StrokePattern.solid(),
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
                    // Route status indicator
                    if (_isLoadingRoute) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppTheme.accentBlue,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Calculating route...',
                            style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                          ),
                        ],
                      ),
                    ] else if (_isRouteFallback && _routePoints.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.warning_amber, size: 12, color: Colors.orange),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Showing straight line - road route unavailable',
                              style: TextStyle(fontSize: 10, color: Colors.orange),
                            ),
                          ),
                        ],
                      ),
                    ] else if (_routePoints.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.route, size: 12, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            'Route: ${_routePoints.length} points',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                          ),
                        ],
                      ),
                    ],
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

          // Map loading overlay
          MapLoadingOverlay(
            isLoading: _isMapLoading,
            message: 'Loading tracking map...',
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _routeCalculationTimer?.cancel();
    _locationSubscription?.cancel();
    _locationProvider.stopUploading();
    _gpsProvider.stopTracking();
    super.dispose();
  }
}
