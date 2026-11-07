import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../theme/app_theme.dart';
import '../../../models/dispatch_job.dart';
import '../../../services/routing_service.dart';
import '../../../services/rider_service.dart';
import '../../../services/supabase_service.dart';
import '../../../config/location_constants.dart';
import '../../../state/gps_provider.dart';
import '../../../widgets/map_loading_overlay.dart';
import '../../../widgets/cached_tile_provider.dart';
import '../jobs/rider_job_details_screen.dart';
import '../payments/rider_payment_process_screen.dart';
import '../../../widgets/address_input_widget.dart';
import '../../../state/rider_location_provider.dart';
import '../../../utils/screen_wake_helper.dart';
import '../../../widgets/in_app_camera_screen.dart';
import '../../../services/photo_file_service.dart';
import '../../../utils/phone_helper.dart';

enum _ArrivalPhotoReviewAction { retake, usePhoto }

/// Active Route Tracking Screen
/// Shows rider's live location centered on map with rotating arrow pointing to next destination
class RiderActiveRouteScreen extends StatefulWidget {
  final List<DispatchJob> jobs;
  final LatLng? initialRiderLocation;

  const RiderActiveRouteScreen({
    super.key,
    required this.jobs,
    this.initialRiderLocation,
  });

  @override
  State<RiderActiveRouteScreen> createState() => _RiderActiveRouteScreenState();
}

class _RiderActiveRouteScreenState extends State<RiderActiveRouteScreen> {
  final MapController _mapController = MapController();
  final RoutingService _routingService = RoutingService();
  final RiderService _riderService = RiderService();
  final GpsProvider _gpsProvider = GpsProvider();
  final RiderLocationProvider _locationProvider = RiderLocationProvider();

  LatLng? _currentLocation;
  double _currentBearing = 0.0; // Direction rider is facing/moving
  List<DispatchJob> _remainingJobs = [];
  List<LatLng> _routePoints = [];
  bool _isRouteFallback = false;
  int _completedStops = 0;
  late int _totalStops;

  StreamSubscription? _locationSubscription;
  Timer? _gpsTimeoutTimer;
  bool _isLoadingRoute = false;
  bool _isMapLoading = true;
  bool _mapReady = false;
  bool _isCompleting = false;
  bool _followRider = true;
  bool _gpsTimedOut = false;
  String? _gpsErrorMessage;
  double _lastMapRotation = 0.0;

  // Metadata cache per order: phone, landmark, customer notes
  final Map<String, Map<String, dynamic>> _jobMetadata = {};

  @override
  void initState() {
    super.initState();
    // Keep screen awake while actively navigating on motorcycle/vehicle mount
    ScreenWakeHelper.enable();
    _remainingJobs = List.from(widget.jobs);
    _totalStops = widget.jobs.length;

    // Fast-seed: if rider location was already known on the previous screen, use immediately
    if (widget.initialRiderLocation != null) {
      _currentLocation = widget.initialRiderLocation;
      _calculateRoute().then((_) {
        if (mounted) {
          _updateHeading(
            newLocation: _currentLocation,
            oldLocation: null,
          );
          _updateCamera(forceRecenter: true, initialZoom: 17.0);
          setState(() {
            _isMapLoading = false;
          });
        }
      });
    }

    _initializeTracking();
    _loadJobsMetadata();
  }

  @override
  void dispose() {
    // Disable screen wake lock to restore normal phone sleep and save battery
    ScreenWakeHelper.disable();
    _gpsTimeoutTimer?.cancel();
    _locationSubscription?.cancel();
    _locationProvider.stopUploading();
    _gpsProvider.stopTracking();
    super.dispose();
  }

  Future<void> _initializeTracking() async {
    // Start 12-second watchdog timer if we don't have location yet
    if (_currentLocation == null) {
      _gpsTimeoutTimer?.cancel();
      _gpsTimeoutTimer = Timer(const Duration(seconds: 12), () {
        if (mounted && _currentLocation == null) {
          setState(() {
            _gpsTimedOut = true;
          });
        }
      });
    }

    try {
      _gpsProvider.attachDialogContext(context);
      await _gpsProvider.initialize();
      if (!mounted) return;

      if (!_gpsProvider.isServiceEnabled) {
        if (mounted) {
          setState(() {
            _gpsTimedOut = true;
            _gpsErrorMessage = 'Location service is disabled in device settings.';
          });
        }
        return;
      }

      if (!_gpsProvider.hasPermission) {
        if (mounted) {
          setState(() {
            _gpsTimedOut = true;
            _gpsErrorMessage = 'Location permission was denied.';
          });
        }
        return;
      }

      // Fast seed from provider cache if screen didn't receive initialRiderLocation
      if (_currentLocation == null && _gpsProvider.currentLocation != null) {
        if (!mounted) return;
        final cached = _gpsProvider.currentLocation!;
        _gpsTimeoutTimer?.cancel();
        setState(() {
          _currentLocation = cached;
          _gpsTimedOut = false;
        });
        _calculateRoute().then((_) {
          if (mounted) {
            _updateHeading(
              newLocation: _currentLocation,
              oldLocation: null,
            );
            _updateCamera(forceRecenter: true, initialZoom: 17.0);
            setState(() {
              _isMapLoading = false;
            });
          }
        });
      }

      // Start active navigation tracking with 6.0m hardware distance filter (prevents stationary/indoor drift)
      await _gpsProvider.startTracking(intervalMillis: 1000, distanceFilterMeters: 6.0);
      if (!mounted) return;

      // Start uploading rider location to Supabase for customer tracking
      final riderId = await _riderService.getCurrentRiderEmployeeId();
      if (!mounted) return;
      if (riderId != null) {
        final currentJobId = _remainingJobs.isNotEmpty ? _remainingJobs.first.id : null;
        _locationProvider.startUploading(
          riderId: riderId,
          dispatchJobId: currentJobId,
          locationStream: _gpsProvider.locationStream
              .where((loc) => loc.latitude != null && loc.longitude != null)
              .map((loc) => LatLng(loc.latitude!, loc.longitude!)),
        );
      }

      _locationSubscription = _gpsProvider.locationStream.listen((location) {
        if (mounted && location.latitude != null && location.longitude != null) {
          _gpsTimeoutTimer?.cancel();
          final newLocation = LatLng(location.latitude!, location.longitude!);
          final isFirstLocation = _currentLocation == null;
          final oldLocation = _currentLocation;

          // 1. Accuracy gate: reject poor accuracy fixes (> 20m) which are indoor Wi-Fi/cell tower drift
          final accuracy = location.accuracy;
          if (!isFirstLocation && accuracy != null && accuracy > 20.0) {
            return;
          }

          // 2. Stationary deadband & physics plausibility
          final speed = location.speed ?? 0.0;
          final distanceMoved = oldLocation != null
              ? _calculateDistance(oldLocation, newLocation)
              : 0.0;

          if (!isFirstLocation) {
            // Stationary deadband: ignore micro-jitter under 6.0m while holding phone or sitting
            if (distanceMoved < 6.0) {
              return;
            }

            // Physics check: cannot jump > 30m in 1s if stationary or crawling
            if (speed < 0.8 && distanceMoved > 30.0) {
              return;
            }
          }

          setState(() {
            _currentLocation = newLocation;
            _gpsTimedOut = false;
            _gpsErrorMessage = null;
          });

          _updateHeading(
            newLocation: newLocation,
            oldLocation: oldLocation,
            gpsHeading: location.heading,
            speed: location.speed,
          );

          if (isFirstLocation) {
            _calculateRoute().then((_) {
              if (mounted) {
                _updateHeading(
                  newLocation: _currentLocation,
                  oldLocation: null,
                );
                _updateCamera(forceRecenter: true, initialZoom: 17.0);
                setState(() {
                  _isMapLoading = false;
                });
              }
            });
          } else {
            _updateCamera();
          }
        }
      });

      if (_currentLocation != null) {
        await _calculateRoute();
      }
    } catch (e) {
      debugPrint('❌ Error initializing tracking: $e');
      if (mounted && _currentLocation == null) {
        setState(() {
          _gpsTimedOut = true;
          _gpsErrorMessage = 'Error connecting to GPS: $e';
        });
      }
    }
  }

  /// Load extra order metadata (phone, landmark, customer notes, payment) for all route jobs
  Future<void> _loadJobsMetadata() async {
    final orderIds = _remainingJobs.map((j) => j.orderId).toSet().toList();
    if (orderIds.isEmpty) return;

    try {
      final ordersRes = await SupabaseService.client
          .from('orders')
          .select('id, customer_id, customer_notes, landmark, payment_status, total_amount, subtotal, delivery_fee, customers(phone, landmark, first_name, last_name)')
          .inFilter('id', orderIds);

      if (mounted) {
        final Map<String, Map<String, dynamic>> meta = {};
        for (final row in (ordersRes as List)) {
          final id = row['id'] as String;
          final cust = row['customers'] as Map<String, dynamic>?;
          final phone = cust?['phone'] as String?;
          final landmark = (row['landmark'] as String?) ?? (cust?['landmark'] as String?);
          final notes = row['customer_notes'] as String?;
          final paymentStatus = row['payment_status'] as String?;
          final custId = row['customer_id']?.toString();

          double? totalAmount = (row['total_amount'] as num?)?.toDouble();
          if (totalAmount == null || totalAmount <= 0) {
            final subtotal = (row['subtotal'] as num?)?.toDouble() ?? 0;
            final deliveryFee = (row['delivery_fee'] as num?)?.toDouble() ?? 0;
            final computed = subtotal + deliveryFee;
            if (computed > 0) totalAmount = computed;
          }

          final first = cust?['first_name'] as String? ?? '';
          final last = cust?['last_name'] as String? ?? '';
          final fullName = last.isNotEmpty ? '$first $last'.trim() : first;

          meta[id] = {
            'phone': phone,
            'landmark': landmark,
            'notes': notes,
            'payment_status': paymentStatus,
            'total_amount': totalAmount,
            'customer_name': fullName.isNotEmpty ? fullName : null,
            'customer_id': custId,
          };
        }
        setState(() {
          _jobMetadata.addAll(meta);
        });
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching job metadata: $e');
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
    return (bearing * 180 / math.pi + 360) % 360;
  }

  /// Calculate distance in meters between two points
  double _calculateDistance(LatLng from, LatLng to) {
    const distance = Distance();
    return distance.as(LengthUnit.Meter, from, to);
  }

  /// Calculates the bearing along the route ahead of the rider's current position
  double _getBearingAlongRoute(LatLng currentPos, List<LatLng> points) {
    if (points.isEmpty) return _currentBearing;
    if (points.length == 1) {
      return _calculateBearing(currentPos, points.first);
    }

    // 1. Find the point on the route closest to currentPos
    int closestIndex = 0;
    double minDistance = double.infinity;

    for (int i = 0; i < points.length; i++) {
      final d = _calculateDistance(currentPos, points[i]);
      if (d < minDistance) {
        minDistance = d;
        closestIndex = i;
      }
    }

    // 2. Follow the road segment itself ahead of closest point (smooth road alignment)
    if (closestIndex < points.length - 1) {
      return _calculateBearing(points[closestIndex], points[closestIndex + 1]);
    }

    // 3. Fallback: last segment bearing
    if (points.length >= 2) {
      return _calculateBearing(points[points.length - 2], points[points.length - 1]);
    }

    return _currentBearing;
  }

  /// Determine and update rider bearing based on route polyline, GPS sensor, or movement
  void _updateHeading({
    LatLng? newLocation,
    LatLng? oldLocation,
    double? gpsHeading,
    double? speed,
  }) {
    if (newLocation == null) return;

    double? calculatedBearing;

    // 1. If device GPS has reliable heading while moving (> 1.2 m/s or ~4 km/h)
    if (gpsHeading != null && gpsHeading >= 0 && speed != null && speed > 1.2) {
      calculatedBearing = gpsHeading;
    }
    // 2. If rider moved noticeably between GPS updates (>= 3.0 meters)
    else if (oldLocation != null && _calculateDistance(oldLocation, newLocation) >= 3.0) {
      calculatedBearing = _calculateBearing(oldLocation, newLocation);
    }
    // 3. Otherwise (stationary or starting out), align along the upcoming route polyline!
    else if (_routePoints.isNotEmpty) {
      // If we already have a bearing established from prior movement, retain it when stationary
      if (_currentBearing != 0.0 && speed != null && speed <= 0.8) {
        calculatedBearing = _currentBearing;
      } else {
        calculatedBearing = _getBearingAlongRoute(newLocation, _routePoints);
      }
    }
    // 4. Fallback: destination bearing
    else if (_remainingJobs.isNotEmpty) {
      final nextJob = _remainingJobs.first;
      if (nextJob.latitude != null && nextJob.longitude != null) {
        calculatedBearing = _calculateBearing(
          newLocation,
          LatLng(nextJob.latitude!, nextJob.longitude!),
        );
      }
    }

    if (calculatedBearing != null) {
      final diff = (calculatedBearing - _currentBearing).abs();
      final normalizedDiff = diff > 180 ? 360 - diff : diff;
      // Damping: when moving, require >= 5° change; when stationary, require >= 12° change
      final threshold = (speed != null && speed > 1.2) ? 5.0 : 12.0;
      if (normalizedDiff >= threshold && mounted) {
        setState(() {
          _currentBearing = calculatedBearing!;
        });
      }
    }
  }

  /// Smoothly moves and optionally rotates the map camera, respecting user's zoom level
  void _updateCamera({bool forceRecenter = false, double? initialZoom}) {
    if (_currentLocation == null) return;
    if (!_mapReady) return;
    if (!_followRider && !forceRecenter) return;

    try {
      double zoom;
      try {
        zoom = initialZoom ?? _mapController.camera.zoom;
      } catch (_) {
        zoom = initialZoom ?? 17.0;
      }
      final targetZoom = zoom.clamp(12.0, 19.0);

      // Preserve user's current 2-finger map rotation angle
      double currentRotation = 0.0;
      try {
        currentRotation = _mapController.camera.rotation;
      } catch (_) {}

      _mapController.moveAndRotate(_currentLocation!, targetZoom, currentRotation);
    } catch (e) {
      debugPrint('⚠️ Error updating camera: $e');
    }
  }

  Future<void> _calculateRoute() async {
    if (!mounted) return;
    if (_remainingJobs.isEmpty || _currentLocation == null) {
      if (mounted) setState(() => _routePoints = []);
      return;
    }

    final activeJob = _remainingJobs.first;
    if (activeJob.latitude == null || activeJob.longitude == null) {
      if (mounted) setState(() => _routePoints = []);
      return;
    }

    if (mounted) setState(() => _isLoadingRoute = true);

    try {
      final waypoints = <LatLng>[
        _currentLocation!,
        LatLng(activeJob.latitude!, activeJob.longitude!),
      ];

      final route = await _routingService.getRouteResult(waypoints);

      if (mounted) {
        setState(() {
          _routePoints = route.points;
          _isRouteFallback = route.isFallback;
          _isLoadingRoute = false;
        });

        // Immediately align bearing with road polyline
        if (_currentLocation != null && _routePoints.isNotEmpty) {
          final roadBearing = _getBearingAlongRoute(_currentLocation!, _routePoints);
          setState(() {
            _currentBearing = roadBearing;
          });
          if (_followRider) {
            _updateCamera();
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error calculating route: $e');
      if (mounted) {
        setState(() {
          _routePoints = [];
          _isRouteFallback = false;
          _isLoadingRoute = false;
        });
      }
    }
  }

  /// Skip current stop: moves it to the end of the route queue so the rider can revisit later
  void _skipCurrentJob() {
    if (_remainingJobs.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This is the only remaining stop on your route.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final currentJob = _remainingJobs.first;
    final meta = _jobMetadata[currentJob.orderId];
    final customerDisplayName = currentJob.customerName ?? meta?['customer_name'] ?? 'Current Customer';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.skip_next_rounded, color: Colors.orange, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Skip This Stop?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          'Move $customerDisplayName to the end of your route so you can complete your other stops first and return here later.',
          style: const TextStyle(fontSize: 14, height: 1.4, color: AppTheme.textLight),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _executeSkip();
            },
            icon: const Icon(Icons.skip_next_rounded, size: 18),
            label: const Text('Skip & Revisit Later', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _executeSkip() async {
    if (_remainingJobs.length <= 1) return;

    final skipped = _remainingJobs.removeAt(0);

    setState(() {
      _remainingJobs.add(skipped);
      // Immediately clear old polyline so stale route isn't shown
      _routePoints = [];
      _isRouteFallback = false;

      // Update bearing arrow to point toward the new first stop
      final newNext = _remainingJobs.first;
      if (_currentLocation != null &&
          newNext.latitude != null &&
          newNext.longitude != null) {
        _currentBearing = _calculateBearing(
          _currentLocation!,
          LatLng(newNext.latitude!, newNext.longitude!),
        );
      }
    });

    final nextJob = _remainingJobs.first;
    final nextMeta = _jobMetadata[nextJob.orderId];
    final nextName = nextJob.customerName ?? nextMeta?['customer_name'] ?? 'next stop';

    // Animate camera to show rider + new destination in frame
    if (_currentLocation != null &&
        nextJob.latitude != null &&
        nextJob.longitude != null) {
      final destLatLng = LatLng(nextJob.latitude!, nextJob.longitude!);
      // Move to midpoint between rider and new stop so both are visible
      final midLat = (_currentLocation!.latitude + destLatLng.latitude) / 2;
      final midLng = (_currentLocation!.longitude + destLatLng.longitude) / 2;
      _mapController.move(LatLng(midLat, midLng), 15.5);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.schedule_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Stop moved to end of route. Now heading to $nextName.'),
            ),
          ],
        ),
        backgroundColor: AppTheme.accentBlue,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );

    // Recalculate road route to new stop order
    await _calculateRoute();
  }

  /// Immediately switch active navigation to focus on a specific stop in the queue
  void _focusOnJob(DispatchJob job) async {
    final index = _remainingJobs.indexOf(job);
    if (index <= 0) return; // Already active destination or not found

    setState(() {
      _remainingJobs.removeAt(index);
      _remainingJobs.insert(0, job);
      _routePoints = [];
      _isRouteFallback = false;
      _isLoadingRoute = true;

      // Update bearing arrow to point toward the new focused stop
      if (_currentLocation != null &&
          job.latitude != null &&
          job.longitude != null) {
        _currentBearing = _calculateBearing(
          _currentLocation!,
          LatLng(job.latitude!, job.longitude!),
        );
      }
    });

    // Animate camera to midpoint between rider and new destination
    if (_currentLocation != null &&
        job.latitude != null &&
        job.longitude != null) {
      final destLatLng = LatLng(job.latitude!, job.longitude!);
      final midLat = (_currentLocation!.latitude + destLatLng.latitude) / 2;
      final midLng = (_currentLocation!.longitude + destLatLng.longitude) / 2;
      _mapController.move(LatLng(midLat, midLng), 15.5);
    }

    final meta = _jobMetadata[job.orderId];
    final customerDisplayName = job.customerName ?? meta?['customer_name'] ?? 'Stop';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Now heading to $customerDisplayName.'),
            ),
          ],
        ),
        backgroundColor: AppTheme.accentBlue,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );

    // Recalculate route for the new order
    await _calculateRoute();
  }

  /// Show sheet when tapping a stop marker on the map to allow quick focus
  void _showFocusPrompt(DispatchJob job, int stopNumber) {
    final meta = _jobMetadata[job.orderId];
    final customerName = job.customerName ?? meta?['customer_name'] ?? 'Customer';
    final isPickup = job.jobType == 'pickup';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).padding.bottom + 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isPickup ? AppTheme.errorRed : AppTheme.teamMemberIconOrange).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'STOP #$stopNumber • ${isPickup ? 'PICKUP' : 'DELIVERY'}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isPickup ? AppTheme.errorRed : AppTheme.teamMemberIconOrange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              customerName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
            ),
            if (job.address != null) ...[
              const SizedBox(height: 4),
              Text(
                AddressInputWidget.formatDisplayAddress(job.address),
                style: const TextStyle(fontSize: 13, color: AppTheme.textLight),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _focusOnJob(job);
                    },
                    icon: const Icon(Icons.navigation_outlined, size: 16),
                    label: const Text('Focus This Stop', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Show sheet displaying all remaining stops with ability to focus on any stop
  void _showStopsQueueSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).padding.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.format_list_bulleted_rounded, color: AppTheme.accentBlue, size: 20),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Route Stops Queue',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.softGray,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_remainingJobs.length} Remaining',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textLight,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Select any stop below to immediately focus navigation on it.',
              style: TextStyle(fontSize: 13, color: AppTheme.textLight),
            ),
            const Divider(height: 24),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.5,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _remainingJobs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final job = _remainingJobs[index];
                  final isCurrent = index == 0;
                  final isPickup = job.jobType == 'pickup';
                  final meta = _jobMetadata[job.orderId];
                  final customerName = job.customerName ?? meta?['customer_name'] ?? 'Customer';
                  final distance = (_currentLocation != null && job.latitude != null && job.longitude != null)
                      ? _calculateDistance(_currentLocation!, LatLng(job.latitude!, job.longitude!))
                      : null;
                  final distanceText = distance == null
                      ? null
                      : (distance < 1000
                          ? '${distance.toStringAsFixed(0)}m away'
                          : '${(distance / 1000).toStringAsFixed(1)}km away');

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isCurrent ? AppTheme.accentBlue.withValues(alpha: 0.05) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isCurrent ? AppTheme.accentBlue : AppTheme.borderGray,
                        width: isCurrent ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? AppTheme.accentBlue
                                : (isPickup ? AppTheme.errorRed : AppTheme.teamMemberIconOrange),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    isPickup ? 'PICKUP' : 'DELIVERY',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isPickup ? AppTheme.errorRed : AppTheme.teamMemberIconOrange,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  if (distanceText != null) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '• $distanceText',
                                      style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                customerName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textDark,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (job.address != null)
                                Text(
                                  AddressInputWidget.formatDisplayAddress(job.address),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textLight,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Navigating',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          )
                        else
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accentBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _focusOnJob(job);
                            },
                            icon: const Icon(Icons.near_me_rounded, size: 13),
                            label: const Text(
                              'Focus',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Complete Stop flow with proximity verification and payment check
  Future<void> _handleCompleteStop(DispatchJob job, double distanceToNext) async {
    // Proximity check warning if rider is farther than 50 meters
    if (distanceToNext >= 50) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.location_searching, color: Colors.orange),
              SizedBox(width: 8),
              Text('Not at Stop Yet'),
            ],
          ),
          content: Text(
            'You are currently ${(distanceToNext).toStringAsFixed(0)}m away (expected within 50m). Mark this stop complete anyway?',
            style: const TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Wait / Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Complete Anyway', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    // Route lists can include unassigned jobs. Claim this stop before saving
    // proof so the private-storage policy can verify the current rider owns it.
    try {
      await _riderService.startJob(job.id);
    } catch (e) {
      if (!mounted) return;
      debugPrint('Could not claim dispatch job before arrival: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This stop could not be assigned to you. Refresh the route and try again.'),
          backgroundColor: AppTheme.errorRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Capture arrival evidence before offering payment or completing the stop.
    // Riders can skip the photo and continue through the same flow.
    final addArrivalPhoto = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.camera_alt_outlined, color: AppTheme.accentBlue),
            SizedBox(width: 8),
            Text('Arrival Photo'),
          ],
        ),
        content: const Text(
          'Take a photo as proof that you arrived at this stop. You can skip this step.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip Photo'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Take Photo'),
          ),
        ],
      ),
    );
    if (addArrivalPhoto == null || !mounted) return;

    if (addArrivalPhoto) {
      final photo = await _captureAndReviewArrivalPhoto();
      if (photo == null || !mounted) return;

      try {
        await _riderService.submitArrivalProof(job.id, photo);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Arrival photo saved.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        debugPrint('Could not save rider arrival proof: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not save the arrival photo. Please try again or skip this photo.'),
            backgroundColor: AppTheme.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    // Payment prompt for deliveries if payment is not completed
    if (job.jobType == 'delivery') {
      try {
        final paymentInfo = await _riderService.getOrderPaymentInfo(job.orderId);
        final paymentStatus = paymentInfo?['payment_status'] as String? ?? 'pending';
        if (paymentStatus != 'paid' && mounted) {
          final double totalAmount = (paymentInfo?['total_amount'] as num?)?.toDouble() ??
              (paymentInfo?['subtotal'] as num?)?.toDouble() ??
              170.0;

          final collectPayment = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                  const SizedBox(height: 8),
                  const Text(
                    'Would you like to collect payment now via Cash or GCash?',
                    style: TextStyle(fontSize: 12, color: AppTheme.textLight),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Skip / Pay Later', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Collect Payment', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );

          if (collectPayment == true && mounted) {
            final order = await _riderService.fetchOrderById(job.orderId);
            if (mounted) {
              await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => RiderPaymentProcessScreen(
                    order: order,
                    orderId: job.orderId,
                    customerName: job.customerName,
                    address: job.address,
                    amount: totalAmount,
                    jobType: job.jobType,
                  ),
                ),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ Non-critical payment check error: $e');
      }
    }

    setState(() => _isCompleting = true);

    try {
      if (job.jobType == 'pickup') {
        await _riderService.completePickup(job.id, job.orderId);
      } else {
        await _riderService.completeDelivery(job.id, job.orderId);
      }

      if (!mounted) return;

      setState(() {
        _isCompleting = false;
        _remainingJobs.removeAt(0);
        _completedStops++;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${job.jobType == 'pickup' ? 'Pickup' : 'Delivery'} completed successfully!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );

      if (_remainingJobs.isEmpty) {
        _locationProvider.stopUploading();
        _showCompletionDialog();
      } else {
        final riderId = SupabaseService.client.auth.currentUser?.id;
        if (riderId != null) {
          _locationProvider.startUploading(
            riderId: riderId,
            dispatchJobId: _remainingJobs.first.id,
            locationStream: _gpsProvider.locationStream
                .where((loc) => loc.latitude != null && loc.longitude != null)
                .map((loc) => LatLng(loc.latitude!, loc.longitude!)),
          );
        }
        await _calculateRoute();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCompleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to complete stop: $e'),
          backgroundColor: AppTheme.errorRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<File?> _captureAndReviewArrivalPhoto() async {
    while (mounted) {
      final photo = await Navigator.of(context).push<File>(
        MaterialPageRoute(builder: (_) => const InAppCameraScreen()),
      );
      if (photo == null || !mounted) return null;

      final action = await showDialog<_ArrivalPhotoReviewAction>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Review arrival photo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Make sure the photo is clear. Retake it if it looks blurry.',
                  style: TextStyle(color: AppTheme.textLight),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: MediaQuery.sizeOf(dialogContext).height * 0.48,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      photo,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text('Could not preview this photo.'),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(
                          dialogContext,
                          _ArrivalPhotoReviewAction.retake,
                        ),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retake'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(
                          dialogContext,
                          _ArrivalPhotoReviewAction.usePhoto,
                        ),
                        icon: const Icon(Icons.check),
                        label: const Text('Use photo'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      if (action == _ArrivalPhotoReviewAction.usePhoto) return photo;

      await PhotoFileService.deleteTemporary(photo);
      if (action == null) return null;
    }
    return null;
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.celebration_rounded, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Text('Route Completed!'),
          ],
        ),
        content: const Text(
          'All stops have been completed. Great job!',
          style: TextStyle(fontSize: 15, color: AppTheme.textLight),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showContactSheet(String? phone, String name) {
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No phone number recorded for this customer.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Contact Customer',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                name,
                style: const TextStyle(fontSize: 14, color: AppTheme.textLight),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.phone_outlined, color: AppTheme.accentBlue),
                ),
                title: Text(
                  phone,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                subtitle: const Text('Tap to call (opens dialer & copies)', style: TextStyle(fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.phone, color: AppTheme.accentBlue),
                  tooltip: 'Call $name',
                  onPressed: () {
                    Navigator.pop(context);
                    PhoneHelper.openDialer(context, phone: phone, contactName: name);
                  },
                ),
                onTap: () {
                  Navigator.pop(context);
                  PhoneHelper.openDialer(context, phone: phone, contactName: name);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
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

    final currentMeta = nextJob != null ? _jobMetadata[nextJob.orderId] : null;
    final customerName = nextJob?.customerName ?? currentMeta?['customer_name'] ?? 'Customer';
    final landmark = nextJob?.landmark ?? currentMeta?['landmark'];
    final phone = currentMeta?['phone'] as String?;

    if (_currentLocation == null) {
      return _buildGpsLoadingView();
    }

    return Scaffold(
      body: Stack(
        children: [
          // Map Layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation!,
              initialZoom: 17.0,
              minZoom: 12.0,
              maxZoom: 19.0,
              onMapReady: () {
                _mapReady = true;
                if (_currentLocation != null) {
                  _updateCamera(forceRecenter: true, initialZoom: 17.0);
                }
              },
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
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) {
                  if (_currentLocation != null) {
                    final dist = _calculateDistance(_currentLocation!, camera.center);
                    if (dist > 50.0 && _followRider) {
                      setState(() {
                        _followRider = false;
                      });
                    }
                  }
                  // Refresh UI when rotated with 2 fingers so the compass needle updates
                  if ((camera.rotation - _lastMapRotation).abs() > 1.0) {
                    setState(() {
                      _lastMapRotation = camera.rotation;
                    });
                  }
                }
              },
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.infinitywash.app',
                tileProvider: CachedTileProvider(),
              ),
              // Delivery radius & meeting radius circles
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
              // Polyline route
              if (_isLoadingRoute)
                const Center(
                  child: Card(
                    margin: EdgeInsets.all(16),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Updating route...',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
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
                      color: _isRouteFallback ? AppTheme.textLight : AppTheme.accentBlue,
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

          // Top Info & Destination Card
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: _buildTopDestinationCard(
              nextJob: nextJob,
              customerName: customerName,
              landmark: landmark,
              phone: phone,
              distanceToNext: distanceToNext,
            ),
          ),

          // Bottom Action Bar
          if (nextJob != null)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: _buildBottomActionBar(
                nextJob: nextJob,
                distanceToNext: distanceToNext,
              ),
            ),

          // Floating Controls (Compass & Recenter)
          Positioned(
            right: 16,
            bottom: nextJob != null ? 100 : 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildCompassButton(),
                if (!_followRider && _currentLocation != null) ...[
                  const SizedBox(height: 10),
                  _buildRecenterButton(),
                ],
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

  /// Modern Destination & Address Card
  Widget _buildTopDestinationCard({
    required DispatchJob? nextJob,
    required String customerName,
    required String? landmark,
    required String? phone,
    required double distanceToNext,
  }) {
    final isPickup = nextJob?.jobType == 'pickup';
    final distanceText = distanceToNext < 1000
        ? '${distanceToNext.toStringAsFixed(0)} m away'
        : '${(distanceToNext / 1000).toStringAsFixed(2)} km away';

    final currentStopNumber = _completedStops + 1;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textDark),
                  tooltip: 'Exit Route',
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'Stop $currentStopNumber of $_totalStops',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildProgressIndicator(),
                    ],
                  ),
                ),
                if (_remainingJobs.length > 1)
                  IconButton(
                    icon: const Icon(Icons.format_list_bulleted_rounded, color: AppTheme.accentBlue),
                    tooltip: 'All Stops & Focus',
                    onPressed: _showStopsQueueSheet,
                  ),
                IconButton(
                  icon: _isLoadingRoute
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, color: AppTheme.accentBlue),
                  tooltip: 'Recalculate Route',
                  onPressed: _isLoadingRoute ? null : _calculateRoute,
                ),
              ],
            ),
          ),

          if (nextJob != null) ...[
            const Divider(height: 16, thickness: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badges: Job Type + Order Number + Distance
                  Row(
                    children: [
                      // Job Type Chip
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: isPickup
                              ? AppTheme.errorRed.withValues(alpha: 0.1)
                              : AppTheme.accentBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isPickup
                                ? AppTheme.errorRed.withValues(alpha: 0.3)
                                : AppTheme.accentBlue.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPickup ? Icons.inventory_2_outlined : Icons.local_shipping_outlined,
                              size: 13,
                              color: isPickup ? AppTheme.errorRed : AppTheme.accentBlue,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isPickup ? 'PICKUP' : 'DELIVERY',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isPickup ? AppTheme.errorRed : AppTheme.accentBlue,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Order ID chip
                      if (nextJob.jobNumber != null || nextJob.orderId.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '#${nextJob.jobNumber ?? (nextJob.orderId.length > 6 ? nextJob.orderId.substring(0, 6).toUpperCase() : nextJob.orderId)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),

                      const Spacer(),

                      // Distance pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.near_me_rounded, size: 12, color: AppTheme.accentBlue),
                            const SizedBox(width: 4),
                            Text(
                              distanceText,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accentBlue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Customer Name
                  Text(
                    customerName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),

                  // Full Address
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.location_on_rounded, size: 16, color: AppTheme.accentBlue),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          AddressInputWidget.formatDisplayAddress(nextJob.address),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade800,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  // Landmark (if present)
                  if (landmark != null && landmark.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(Icons.explore_outlined, size: 15, color: Colors.amber.shade800),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Landmark: $landmark',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 14),

                  // Quick Action Buttons Row
                  Row(
                    children: [
                      // Contact button
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            foregroundColor: AppTheme.accentBlue,
                          ),
                          onPressed: () => _showContactSheet(phone, customerName),
                          icon: const Icon(Icons.phone_outlined, size: 16),
                          label: const Text('Contact', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Details button
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            foregroundColor: AppTheme.textDark,
                          ),
                          onPressed: () {
                            final meta = _jobMetadata[nextJob.orderId];
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RiderJobDetailsScreen(
                                  job: nextJob,
                                  readOnly: true,
                                  preloadedCustomerPhone: meta?['phone'] as String?,
                                  preloadedPaymentStatus: meta?['payment_status'] as String?,
                                  preloadedTotalAmount: meta?['total_amount'] as double?,
                                  preloadedCustomerNotes: meta?['notes'] as String?,
                                  preloadedCustomerId: meta?['customer_id'] as String?,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.info_outline_rounded, size: 16),
                          label: const Text('Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Progress indicator dots or bar
  Widget _buildProgressIndicator() {
    if (_totalStops <= 6) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(_totalStops, (index) {
          final isCompleted = index < _completedStops;
          final isCurrent = index == _completedStops;

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: isCurrent ? 18 : 6,
            height: 5,
            decoration: BoxDecoration(
              color: isCompleted
                  ? Colors.green
                  : isCurrent
                      ? AppTheme.accentBlue
                      : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      );
    } else {
      final progress = (_completedStops + 1) / _totalStops;
      return SizedBox(
        width: 100,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            backgroundColor: Colors.grey.shade200,
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentBlue),
            minHeight: 4,
          ),
        ),
      );
    }
  }

  /// Bottom action bar with Skip and Complete Stop buttons
  Widget _buildBottomActionBar({
    required DispatchJob nextJob,
    required double distanceToNext,
  }) {
    final canSkip = _remainingJobs.length > 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Route Warning Notice (if applicable)
        if (!_isLoadingRoute && (_routePoints.isEmpty || _isRouteFallback))
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade800,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentLocation == null
                        ? 'Acquiring GPS signal...'
                        : _isRouteFallback
                            ? 'Road routing unavailable — showing direct path.'
                            : 'Route line unavailable. Tap refresh to retry.',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

        // Action Buttons Row
        Row(
          children: [
            // Skip Button (Outlined)
            if (canSkip) ...[
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: Colors.orange.shade400, width: 1.5),
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.orange.shade800,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _skipCurrentJob,
                  icon: const Icon(Icons.skip_next_rounded, size: 20),
                  label: const Text(
                    'Skip',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],

            // Complete Stop Button (Primary Blue)
            Expanded(
              flex: 3,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _isCompleting
                    ? null
                    : () => _handleCompleteStop(nextJob, distanceToNext),
                icon: _isCompleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline_rounded, size: 20),
                label: Text(
                  _isCompleting
                      ? 'Completing...'
                      : (distanceToNext < 50 ? 'Complete Stop' : 'Arrive to Complete'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Rider live location marker with directional navigation puck
    if (_currentLocation != null) {
      markers.add(
        Marker(
          point: _currentLocation!,
          width: 64,
          height: 64,
          alignment: Alignment.center,
          rotate: true, // Keep marker upright even if map rotates
          child: _buildRiderMarkerWidget(),
        ),
      );
    }

    // Numbered Stop Markers
    int index = 0;
    for (final job in _remainingJobs) {
      if (job.latitude != null && job.longitude != null) {
        final isCurrent = index == 0;
        final stopNum = index + 1;
        markers.add(
          Marker(
            point: LatLng(job.latitude!, job.longitude!),
            width: 80,
            height: 80,
            alignment: Alignment.center,
            rotate: true, // Keep stop marker upright when map rotates
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (!isCurrent) {
                  _showFocusPrompt(job, stopNum);
                }
              },
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isCurrent
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
                      '$stopNum',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    color: isCurrent ? AppTheme.errorRed : AppTheme.teamMemberIconOrange,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
        );
        index++;
      }
    }

    return markers;
  }

  /// Modern Delivery Rider Badge (Option A: Always Upright, Non-Rotating)
  Widget _buildRiderMarkerWidget() {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer subtle pulse / glow ring
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accentBlue.withValues(alpha: 0.16),
              border: Border.all(
                color: AppTheme.accentBlue.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
          ),
          // Elevated white badge with drop shadow
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              // Inner solid brand-blue core with delivery rider scooter icon
              child: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accentBlue,
                ),
                child: const Center(
                  child: Icon(
                    Icons.two_wheeler_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Floating Compass / Heading-Up Toggle Button
  Widget _buildCompassButton() {
    double rotationRad = 0.0;
    try {
      rotationRad = _mapController.camera.rotationRad;
    } catch (_) {}

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          // Snap map rotation back to True North (0.0°) and recenter on rider
          if (_currentLocation != null) {
            double currentZoom = 17.0;
            try {
              currentZoom = _mapController.camera.zoom;
            } catch (_) {}
            setState(() {
              _followRider = true;
              _lastMapRotation = 0.0;
            });
            _mapController.moveAndRotate(_currentLocation!, currentZoom, 0.0);
          }
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.grey.shade300,
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Rotating Compass Needle pointing to True North
              Transform.rotate(
                angle: -rotationRad,
                child: Icon(
                  Icons.navigation_rounded,
                  size: 22,
                  color: Colors.red.shade600,
                ),
              ),
              Positioned(
                bottom: 3,
                child: Text(
                  'N',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Floating Recenter Button (appears when rider panned away)
  Widget _buildRecenterButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _followRider = true;
          });
          _updateCamera(forceRecenter: true);
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.accentBlue,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentBlue.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.my_location_rounded, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text(
                'Recenter',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Fallback option: allow rider to start route from shop hub if GPS is not yet acquired indoors
  void _useShopLocationFallback() {
    _gpsTimeoutTimer?.cancel();
    setState(() {
      _currentLocation = LocationConstants.shopLocation;
      _gpsTimedOut = false;
      _isMapLoading = true;
    });

    _calculateRoute().then((_) {
      if (mounted) {
        _updateHeading(
          newLocation: _currentLocation,
          oldLocation: null,
        );
        _updateCamera(forceRecenter: true, initialZoom: 17.0);
        setState(() {
          _isMapLoading = false;
        });
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Starting from Shop Hub. Live GPS will update automatically once signal is detected.'),
        duration: Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Retry acquiring GPS coordinates
  void _retryGps() {
    setState(() {
      _gpsTimedOut = false;
      _gpsErrorMessage = null;
    });
    _initializeTracking();
  }

  /// Full-screen loading view displayed before GPS position is locked
  Widget _buildGpsLoadingView() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Starting Route',
          style: TextStyle(
            color: AppTheme.textDark,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: _gpsTimedOut ? _buildGpsTimeoutContent() : _buildGpsSearchingContent(),
        ),
      ),
    );
  }

  /// Content while actively searching for GPS signal
  Widget _buildGpsSearchingContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.accentBlue.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.gps_fixed_rounded,
            size: 56,
            color: AppTheme.accentBlue,
          ),
        ),
        const SizedBox(height: 24),
        const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentBlue),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Acquiring GPS Location...',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Locking onto your live position before loading the navigation map.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.textLight,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 32),
        // Quick shortcut to start from shop hub immediately
        OutlinedButton.icon(
          onPressed: _useShopLocationFallback,
          icon: const Icon(Icons.store_mall_directory_outlined, size: 18),
          label: const Text('Start from Shop Hub Now'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.accentBlue,
            side: const BorderSide(color: AppTheme.accentBlue),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

  /// Content when GPS search times out or encounters an error
  Widget _buildGpsTimeoutContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.gps_not_fixed_rounded,
            size: 56,
            color: Colors.orange,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'GPS Signal Not Found',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _gpsErrorMessage ??
              'Unable to acquire satellite coordinates. This usually happens indoors or under heavy roofs.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.textLight,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 28),

        // Primary action: Start from shop hub
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _useShopLocationFallback,
            icon: const Icon(Icons.store_mall_directory_rounded, size: 20),
            label: const Text('Use Shop Hub as Start Point'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Secondary action: Retry GPS
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _retryGps,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry GPS'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textDark,
              side: BorderSide(color: Colors.grey.shade300),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Cancel
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel & Go Back', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }
}
