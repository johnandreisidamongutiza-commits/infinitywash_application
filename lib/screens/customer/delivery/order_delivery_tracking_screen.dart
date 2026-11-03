import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/location_constants.dart';
import '../../../services/delivery_tracking_service.dart';
import '../../../services/routing_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/phone_helper.dart';
import '../../../widgets/cached_tile_provider.dart';
import '../../../widgets/top_notification.dart';
import '../chats/customer_chat_detail_screen.dart';

/// Dedicated per-order live delivery and pickup tracking screen.
/// Focused entirely on a single order with live GPS, route, and driver controls.
class OrderDeliveryTrackingScreen extends StatefulWidget {
  final ActiveDelivery? delivery;
  final String orderId;

  const OrderDeliveryTrackingScreen({
    super.key,
    this.delivery,
    required this.orderId,
  });

  @override
  State<OrderDeliveryTrackingScreen> createState() => _OrderDeliveryTrackingScreenState();
}

class _OrderDeliveryTrackingScreenState extends State<OrderDeliveryTrackingScreen>
    with WidgetsBindingObserver {
  final DeliveryTrackingService _trackingService = DeliveryTrackingService();
  final RoutingService _routingService = RoutingService();
  final MapController _mapController = MapController();

  ActiveDelivery? _delivery;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  // Real-time tracking coordinates & route
  LatLng? _riderLocation;
  List<LatLng> _routePoints = [];
  double _distanceKm = 0.0;
  double _durationMin = 0.0;

  StreamSubscription<DeliveryPollResult>? _pollSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _delivery = widget.delivery;
    if (_delivery != null) {
      _isLoading = false;
      _initTracking(_delivery!);
    }
    _loadOrderDelivery();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Pause polling when app is in background to save API requests
      _pollSub?.cancel();
      _pollSub = null;
      debugPrint('⏸️ Paused delivery tracking polling (app backgrounded)');
    } else if (state == AppLifecycleState.resumed) {
      // Resume polling when app returns to foreground
      debugPrint('▶️ Resumed delivery tracking polling (app foregrounded)');
      if (_delivery != null && !_delivery!.isCompleted) {
        _initTracking(_delivery!);
      }
    }
  }

  /// Loads the latest delivery info for this specific order from Supabase.
  Future<void> _loadOrderDelivery() async {
    try {
      final updated = await _trackingService.getDeliveryByOrderId(widget.orderId);
      if (!mounted) return;

      if (updated == null && _delivery == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Delivery details could not be found for this order.';
        });
        return;
      }

      if (updated != null) {
        setState(() {
          _delivery = updated;
          _isLoading = false;
          _errorMessage = null;
        });

        // Immediately fetch rider location on manual load/refresh
        final rId = updated.job?.riderId;
        if (rId != null && rId.isNotEmpty && !updated.isCompleted) {
          _trackingService.getLatestRiderLocation(riderId: rId, dispatchJobId: updated.job?.id).then((loc) {
            if (!mounted || loc == null) return;
            setState(() => _riderLocation = loc);
            _calculateRoute(loc, updated.destinationLocation ?? LocationConstants.shopLocation);
            _recenterMap();
          });
        }

        _initTracking(updated);
      }
    } catch (e) {
      if (!mounted) return;
      if (_delivery == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load delivery tracking. Please tap to retry.';
        });
      }
      debugPrint('⚠️ Error loading order delivery: $e');
    }
  }

  /// Sets up efficient 60-second polling for rider GPS and job status for this order.
  void _initTracking(ActiveDelivery delivery) {
    _pollSub?.cancel();
    _pollSub = null;

    final riderId = delivery.job?.riderId;
    final jobId = delivery.job?.id;

    // If job is already completed or cancelled, do not poll
    if (delivery.isCompleted) {
      // One-time coordinate fetch if not yet loaded
      if (riderId != null && _riderLocation == null) {
        _trackingService.getLatestRiderLocation(riderId: riderId, dispatchJobId: jobId).then((loc) {
          if (!mounted || loc == null) return;
          setState(() => _riderLocation = loc);
          _calculateRoute(loc, delivery.destinationLocation ?? LocationConstants.shopLocation);
          _recenterMap();
        });
      }
      return;
    }

    if (jobId != null) {
      _pollSub = _trackingService
          .pollDeliveryUpdates(
            jobId: jobId,
            riderId: riderId,
            interval: const Duration(seconds: 60),
          )
          .listen((result) {
        if (!mounted) return;

        // 1. Update rider location if coordinates are available
        if (result.riderLocation != null) {
          final loc = result.riderLocation!;
          final hasChanged = _riderLocation == null ||
              (_riderLocation!.latitude != loc.latitude || _riderLocation!.longitude != loc.longitude);
          if (hasChanged) {
            setState(() => _riderLocation = loc);
            _calculateRoute(loc, delivery.destinationLocation ?? LocationConstants.shopLocation);
          }
        }

        // 2. Handle dispatch job status updates
        final updatedJob = result.job;
        if (updatedJob != null) {
          final isDone = updatedJob.status == 'pickup_done' ||
              updatedJob.status == 'delivery_done' ||
              updatedJob.status == 'done';
          if (isDone && _delivery?.job?.status != updatedJob.status) {
            showTopNotification(
              context,
              message: delivery.isPickup ? 'Laundry has been picked up!' : 'Order has been delivered!',
              icon: Icons.check_circle,
              backgroundColor: Colors.green,
            );
          }

          // If status changed, refresh delivery details (which auto-stops polling if completed)
          if (_delivery?.job?.status != updatedJob.status) {
            _loadOrderDelivery();
          }
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _recenterMap());
  }

  /// Calculates road route geometry and distance/time.
  Future<void> _calculateRoute(LatLng origin, LatLng destination) async {
    try {
      final result = await _routingService.getRouteResult([origin, destination]);
      if (!mounted) return;
      setState(() {
        _routePoints = result.points;
        _distanceKm = result.distanceKm;
        _durationMin = result.durationMin;
      });
    } catch (e) {
      debugPrint('⚠️ Notice: Could not calculate route: $e');
    }
  }

  /// Smoothly animates map bounds to encompass the rider and destination.
  void _recenterMap() {
    final dest = _delivery?.destinationLocation ?? LocationConstants.shopLocation;
    final rider = _riderLocation;

    if (rider != null) {
      final bounds = LatLngBounds.fromPoints([rider, dest]);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(50),
          maxZoom: 16.5,
        ),
      );
    } else {
      _mapController.move(dest, 15.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _delivery != null
        ? 'Track: ${_delivery!.order.displayNumber}'
        : 'Track Order';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          title,
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: AppTheme.textDark,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentBlue),
                    ),
                  )
                : const Icon(Icons.refresh, color: AppTheme.accentBlue),
            tooltip: 'Refresh Status',
            onPressed: _isRefreshing
                ? null
                : () async {
                    setState(() => _isRefreshing = true);
                    await _loadOrderDelivery();
                    if (mounted) setState(() => _isRefreshing = false);
                  },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentBlue),
              strokeWidth: 3,
            ),
            SizedBox(height: 16),
            Text(
              'Loading live tracking...',
              style: TextStyle(color: AppTheme.textLight, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 56, color: AppTheme.errorRed.withValues(alpha: 0.8)),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textDark, fontSize: 14),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadOrderDelivery,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final delivery = _delivery!;

    return RefreshIndicator(
      onRefresh: _loadOrderDelivery,
      color: AppTheme.accentBlue,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Interactive Map View ──
            _buildInteractiveMap(delivery),
            const SizedBox(height: 20),

            // ── Rider Contact & Information Card ──
            _buildDriverInfo(delivery),
            const SizedBox(height: 20),

            // ── Delivery Progress Stepper ──
            _buildDeliveryProgress(delivery),
            const SizedBox(height: 20),

            // ── Order Details Summary Card ──
            _buildOrderDetailsSummary(delivery),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Interactive OpenStreetMap with live rider marker, route line, and destination.
  Widget _buildInteractiveMap(ActiveDelivery delivery) {
    final dest = delivery.destinationLocation ?? LocationConstants.shopLocation;
    final rider = _riderLocation;

    final markers = <Marker>[
      Marker(
        point: dest,
        width: 48,
        height: 48,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.accentBlue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6),
                ],
              ),
              child: Icon(
                delivery.isPickup ? Icons.storefront : Icons.home_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    ];

    if (rider != null) {
      markers.add(
        Marker(
          point: rider,
          width: 52,
          height: 52,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.orange.shade700,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(color: Colors.orange.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 2),
                  ],
                ),
                child: const Icon(
                  Icons.two_wheeler_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      );
    }

    String statusChipText;
    if (rider != null && _durationMin > 0) {
      statusChipText = 'Rider is ~${_distanceKm.toStringAsFixed(1)} km away • ~${_durationMin.ceil()} mins';
    } else if (rider != null) {
      statusChipText = 'Rider is ~${_distanceKm.toStringAsFixed(1)} km away';
    } else if (delivery.hasAssignedRider) {
      statusChipText = delivery.isInProgress
          ? 'Rider is en route • GPS syncing...'
          : 'Rider assigned • Preparing to depart';
    } else {
      statusChipText = 'Finding nearby rider...';
    }

    return Container(
      height: 290,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.borderGray),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: dest,
                initialZoom: 15.0,
                minZoom: 10.0,
                maxZoom: 18.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.infinitywash.app',
                  tileProvider: CachedTileProvider(),
                ),
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: dest,
                      radius: LocationConstants.customerMeetingRadiusMeters,
                      useRadiusInMeter: true,
                      color: AppTheme.accentBlue.withValues(alpha: 0.15),
                      borderColor: AppTheme.accentBlue.withValues(alpha: 0.4),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 4.5,
                        color: AppTheme.accentBlue,
                      ),
                    ],
                  ),
                MarkerLayer(markers: markers),
              ],
            ),

            // Top Status & ETA Chip
            Positioned(
              top: 14,
              left: 14,
              right: 14,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        rider != null ? Icons.navigation : Icons.schedule,
                        size: 16,
                        color: AppTheme.accentBlue,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          statusChipText,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.lexend(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accentBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Floating Recenter Button
            Positioned(
              bottom: 14,
              right: 14,
              child: FloatingActionButton.small(
                heroTag: 'order_tracking_recenter_btn',
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.accentBlue,
                elevation: 3,
                onPressed: _recenterMap,
                child: const Icon(Icons.my_location, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Driver information with direct In-App Chat and Phone Call integration.
  Widget _buildDriverInfo(ActiveDelivery delivery) {
    if (!delivery.hasAssignedRider) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: AppStyles.cardDecoration,
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(
                color: AppTheme.lightBlue,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_search_rounded, color: AppTheme.accentBlue, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Assigning a Rider...',
                    style: GoogleFonts.lexend(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'We are notifying nearby riders for this order.',
                    style: GoogleFonts.lexend(fontSize: 12, color: AppTheme.textLight),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final riderName = delivery.riderName ?? 'Assigned Rider';
    final vehicle = delivery.vehicleDetails?.isNotEmpty == true
        ? delivery.vehicleDetails!
        : 'Registered Delivery Vehicle';
    final phone = delivery.riderPhone;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppStyles.cardDecoration,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.lightBlue,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.2)),
            ),
            child: Center(
              child: Text(
                riderName.isNotEmpty ? riderName.substring(0, 1).toUpperCase() : 'R',
                style: GoogleFonts.lexend(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: AppTheme.accentBlue,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  riderName,
                  style: GoogleFonts.lexend(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.two_wheeler, size: 14, color: AppTheme.textLight),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        vehicle,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.lexend(fontSize: 12, color: AppTheme.textLight),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // In-App Chat Action
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CustomerChatDetailScreen(
                    recipientName: riderName,
                    recipientRole: delivery.isPickup ? 'Pickup Rider' : 'Delivery Rider',
                    recipientType: ChatRecipientType.rider,
                    orderId: delivery.order.id,
                    phoneNumber: phone,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.accentBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.chat_bubble_outline, color: AppTheme.accentBlue, size: 20),
            ),
          ),
          const SizedBox(width: 8),

          // Call Rider Action (Opens dialer with number pre-filled and copies to clipboard)
          InkWell(
            onTap: () => PhoneHelper.openDialer(context, phone: phone, contactName: riderName),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.phone, color: Colors.green, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens native dialer with pre-filled number and copies to clipboard.
  Future<void> _handlePhoneAction(String? phone, String name) async {
    await PhoneHelper.openDialer(context, phone: phone, contactName: name);
  }

  /// Live delivery progress stepper tailored to pickup vs return delivery.
  Widget _buildDeliveryProgress(ActiveDelivery delivery) {
    final status = delivery.job?.status ?? (delivery.isPickup ? 'pending' : 'in_progress');
    final isPickup = delivery.isPickup;

    final bool step1Done = true;
    final bool step2Done = delivery.hasAssignedRider;
    final bool step3Done = status == 'in_progress' || status == 'pickup_done' || status == 'delivery_done' || status == 'done';
    final bool step4Done = status == 'pickup_done' || status == 'delivery_done' || status == 'done';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPickup ? Icons.shopping_bag_outlined : Icons.local_shipping_outlined,
                size: 20,
                color: AppTheme.accentBlue,
              ),
              const SizedBox(width: 8),
              Text(
                isPickup ? 'Pickup Progress' : 'Delivery Progress',
                style: GoogleFonts.lexend(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildStatusLine(
            isPickup ? 'Request Approved' : 'Laundry Cleaned & Packed',
            'Completed',
            step1Done,
          ),
          _buildStatusLine(
            isPickup ? 'Rider Assigned' : 'Rider Assigned',
            step2Done ? (delivery.riderName ?? 'Assigned') : 'Waiting...',
            step2Done,
          ),
          _buildStatusLine(
            isPickup ? 'Rider Heading to You' : 'Out for Delivery',
            step3Done ? 'In Progress' : 'Waiting...',
            step3Done,
          ),
          _buildStatusLine(
            isPickup ? 'Laundry Picked Up' : 'Delivered to Doorstep',
            step4Done ? 'Completed' : 'Pending',
            step4Done,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusLine(String title, String subtitle, bool isDone, {bool isLast = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(
              isDone ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isDone ? Colors.green : AppTheme.textLight.withValues(alpha: 0.5),
              size: 20,
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 26,
                color: isDone ? Colors.green : AppTheme.borderGray,
                margin: const EdgeInsets.symmetric(vertical: 2),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.lexend(
                  color: isDone ? AppTheme.textDark : AppTheme.textLight,
                  fontWeight: isDone ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: GoogleFonts.lexend(
                  fontSize: 11,
                  color: isDone ? Colors.green.shade700 : AppTheme.textLight,
                ),
              ),
              if (!isLast) const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  /// Summary of the selected order (order code, destination, payment preference).
  Widget _buildOrderDetailsSummary(ActiveDelivery delivery) {
    final order = delivery.order;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                order.displayNumber,
                style: GoogleFonts.lexend(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppTheme.textDark,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  delivery.isPickup ? 'Rider Pickup' : 'Home Delivery',
                  style: GoogleFonts.lexend(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: AppTheme.accentBlue,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24, color: AppTheme.borderGray),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_outlined, size: 18, color: AppTheme.accentBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      delivery.isPickup ? 'Pickup Address' : 'Drop-off Address',
                      style: GoogleFonts.lexend(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.textDark),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      delivery.destinationAddress,
                      style: GoogleFonts.lexend(fontSize: 12, color: AppTheme.textLight),
                    ),
                    if (order.deliveryLandmark != null && order.deliveryLandmark!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Landmark: ${order.deliveryLandmark}',
                        style: GoogleFonts.lexend(fontSize: 11, color: AppTheme.textLight, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (order.paymentPreference != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.payment_outlined, size: 18, color: AppTheme.textLight),
                const SizedBox(width: 8),
                Text(
                  'Payment Preference: ${order.paymentPreference}',
                  style: GoogleFonts.lexend(fontSize: 12, color: AppTheme.textLight),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
