import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_error.dart';
import '../../../models/dispatch_job.dart';
import '../../../services/rider_service.dart';
import '../../../services/supabase_service.dart';
import '../../../config/location_constants.dart';
import '../../../state/gps_provider.dart';
import '../../../widgets/cached_tile_provider.dart';
import '../../../widgets/address_input_widget.dart';
import '../route/rider_active_route_screen.dart';
import '../chats/rider_chat_detail_screen.dart';

/// Details screen for a specific dispatch job
/// Shows job information, location on map, and action buttons with a modern card-based theme
class RiderJobDetailsScreen extends StatefulWidget {
  final DispatchJob job;
  /// When true (e.g. opened from the active route Details button), the bottom
  /// action panel (Start Job / Skip Order / Continue Tracking) is hidden so
  /// the screen is a read-only information view only.
  final bool readOnly;
  final String? preloadedCustomerPhone;
  final String? preloadedPaymentStatus;
  final double? preloadedTotalAmount;
  final String? preloadedCustomerNotes;
  final String? preloadedCustomerId;

  const RiderJobDetailsScreen({
    super.key,
    required this.job,
    this.readOnly = false,
    this.preloadedCustomerPhone,
    this.preloadedPaymentStatus,
    this.preloadedTotalAmount,
    this.preloadedCustomerNotes,
    this.preloadedCustomerId,
  });

  @override
  State<RiderJobDetailsScreen> createState() => _RiderJobDetailsScreenState();
}

class _RiderJobDetailsScreenState extends State<RiderJobDetailsScreen> {
  final MapController _mapController = MapController();
  final RiderService _riderService = RiderService();
  final GpsProvider _gpsProvider = GpsProvider();

  LatLng? _riderLocation;
  LatLng? _resolvedJobLocation;
  bool _isStarting = false;
  bool _isSkipping = false;
  bool _takenByOther = false;
  bool _isLoadingDetails = true;

  // Extra order metadata fetched from Supabase
  String? _customerId;
  String? _customerPhone;
  String? _customerNotes;
  String? _paymentStatus;
  double? _totalAmount;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
    _verifyJobAvailable();

    final hasPreloaded = widget.preloadedCustomerPhone != null ||
        widget.preloadedPaymentStatus != null ||
        widget.preloadedTotalAmount != null ||
        widget.preloadedCustomerNotes != null ||
        widget.preloadedCustomerId != null;

    if (hasPreloaded) {
      _customerPhone = widget.preloadedCustomerPhone;
      _paymentStatus = widget.preloadedPaymentStatus;
      _totalAmount = widget.preloadedTotalAmount;
      _customerNotes = widget.preloadedCustomerNotes;
      _customerId = widget.preloadedCustomerId;
      _isLoadingDetails = false;
      // Silently sync any additional fields or coordinates in the background
      _loadOrderDetails();
    } else {
      _loadOrderDetails();
    }
  }

  Future<void> _loadOrderDetails() async {
    try {
      final orderRes = await SupabaseService.client
          .from('orders')
          .select('customer_id, customers(pin_latitude, pin_longitude, phone), customer_notes, payment_status, total_amount, subtotal, delivery_fee')
          .eq('id', widget.job.orderId)
          .maybeSingle();

      if (orderRes != null && mounted) {
        final cust = orderRes['customers'] as Map<String, dynamic>?;
        final lat = (cust?['pin_latitude'] as num?)?.toDouble();
        final lng = (cust?['pin_longitude'] as num?)?.toDouble();

        // Resolve total amount — fallback to subtotal + delivery_fee if total_amount is 0/null
        double? resolvedTotal = (orderRes['total_amount'] as num?)?.toDouble();
        if (resolvedTotal == null || resolvedTotal <= 0) {
          final subtotal = (orderRes['subtotal'] as num?)?.toDouble() ?? 0;
          final deliveryFee = (orderRes['delivery_fee'] as num?)?.toDouble() ?? 0;
          final computed = subtotal + deliveryFee;
          if (computed > 0) resolvedTotal = computed;
        }

        setState(() {
          if (widget.job.latitude == null || widget.job.longitude == null) {
            if (lat != null && lng != null) {
              _resolvedJobLocation = LatLng(lat, lng);
            }
          }
          _customerId = orderRes['customer_id']?.toString() ?? _customerId;
          _customerPhone = (cust?['phone'] as String?) ?? _customerPhone;
          _customerNotes = (orderRes['customer_notes'] as String?) ?? _customerNotes;
          _paymentStatus = (orderRes['payment_status'] as String?) ?? _paymentStatus;
          _totalAmount = resolvedTotal ?? _totalAmount;
          _isLoadingDetails = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingDetails = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingDetails = false);
    }
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
      _gpsProvider.attachDialogContext(context);
      await _gpsProvider.initialize();
      _gpsProvider.locationStream.listen((location) {
        if (mounted && location.latitude != null && location.longitude != null) {
          final newLoc = LatLng(location.latitude!, location.longitude!);
          if (_riderLocation == null ||
              const Distance().as(LengthUnit.Meter, _riderLocation!, newLoc) >= 6.0) {
            setState(() {
              _riderLocation = newLoc;
            });
          }
        }
      });
    } catch (e) {
      debugPrint('❌ Error initializing GPS: $e');
    }
  }

  Future<void> _startJob() async {
    setState(() => _isStarting = true);

    try {
      await _riderService.startJob(widget.job.id);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => RiderActiveRouteScreen(
              jobs: [widget.job],
              initialRiderLocation: _gpsProvider.currentLocation,
            ),
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
            content: Text(mapErrorToMessage(e)),
            backgroundColor: AppTheme.errorRed,
          ),
        );
        setState(() => _isStarting = false);
      }
    }
  }

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openCustomerChat(String customerName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RiderChatDetailScreen(
          customerName: customerName,
          customerId: _customerId ?? '',
          orderId: widget.job.orderId,
          phoneNumber: _customerPhone,
          jobType: widget.job.jobType,
          address: widget.job.address,
          landmark: widget.job.landmark,
          isDispatchChat: false,
        ),
      ),
    );
  }

  void _showContactSheet(String phone, String name) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.borderGray,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Contact $name',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: AppTheme.lightBlue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.phone, color: AppTheme.accentBlue),
              ),
              title: const Text('Phone Call', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text(phone, style: const TextStyle(fontSize: 13, color: AppTheme.textLight)),
              trailing: IconButton(
                icon: const Icon(Icons.copy, size: 18, color: AppTheme.accentBlue),
                tooltip: 'Copy Phone',
                onPressed: () {
                  Navigator.pop(context);
                  _copyToClipboard(phone, 'Phone number copied');
                },
              ),
            ),
            const Divider(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.chat_bubble_outline, color: Colors.teal.shade800),
              ),
              title: const Text('In-App Chat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text('Direct message regarding Order #${widget.job.jobNumber ?? widget.job.orderId}', style: const TextStyle(fontSize: 13, color: AppTheme.textLight)),
              trailing: const Icon(Icons.chevron_right, color: AppTheme.textLight),
              onTap: () {
                Navigator.pop(context);
                _openCustomerChat(name);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts.last[0]).toUpperCase();
  }

  String _calculateDistance(LatLng from, LatLng to) {
    final distance = const Distance().as(LengthUnit.Kilometer, from, to);
    if (distance < 1) {
      return '${(distance * 1000).toStringAsFixed(0)}m away';
    }
    return '${distance.toStringAsFixed(1)}km away';
  }

  String _formatStatus(String status) {
    return status.split('_').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final jobLocation = widget.job.latitude != null && widget.job.longitude != null
        ? LatLng(widget.job.latitude!, widget.job.longitude!)
        : _resolvedJobLocation;

    final isPickup = widget.job.jobType == 'pickup';
    final customerName = widget.job.customerName ?? 'Customer';
    final address = AddressInputWidget.formatDisplayAddress(widget.job.address);

    return Scaffold(
      backgroundColor: AppTheme.softGray,
      appBar: AppBar(
        title: Column(
          children: [
            const Text(
              'Job Details',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            if (widget.job.jobNumber != null)
              Text(
                widget.job.jobNumber!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textLight,
                ),
              ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 19, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Map preview card
            _buildMapSection(jobLocation, isPickup),

            // 2. Customer Information Card
            _buildCustomerCard(customerName),

            // 3. Location & Landmark Card
            _buildLocationCard(address, jobLocation),

            // 4. Job & Order Info Card (with loading state)
            _buildOrderInfoCard(isPickup),
          ],
        ),
      ),
      // Hide action buttons when opened in read-only mode (e.g. from active route)
      bottomNavigationBar: widget.readOnly ? null : _buildBottomActions(),
    );
  }

  /// 1. Map section with framed rounded card and floating badges
  Widget _buildMapSection(LatLng? jobLocation, bool isPickup) {
    if (jobLocation == null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.location_off_outlined, color: Colors.amber.shade800, size: 24),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No map pin for this job — use the address and landmark details below.',
                style: TextStyle(fontSize: 13, color: AppTheme.textDark, height: 1.3),
              ),
            ),
          ],
        ),
      );
    }

    final statusColor = widget.job.status == 'in_progress'
        ? AppTheme.statusActive
        : (widget.job.status == 'pending' ? AppTheme.statusActive : AppTheme.statusCompleted);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: jobLocation,
                initialZoom: 14.5,
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
                      point: LocationConstants.shopLocation,
                      radius: LocationConstants.deliveryRadiusMeters,
                      useRadiusInMeter: true,
                      color: AppTheme.accentBlue.withValues(alpha: 0.08),
                      borderColor: AppTheme.accentBlue.withValues(alpha: 0.25),
                      borderStrokeWidth: 1.5,
                    ),
                    CircleMarker(
                      point: jobLocation,
                      radius: LocationConstants.customerMeetingRadiusMeters,
                      useRadiusInMeter: true,
                      color: Colors.green.withValues(alpha: 0.2),
                      borderColor: Colors.green.shade700,
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: jobLocation,
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.location_on,
                        color: isPickup ? AppTheme.errorRed : AppTheme.teamMemberIconOrange,
                        size: 38,
                      ),
                    ),
                    if (_riderLocation != null)
                      Marker(
                        point: _riderLocation!,
                        width: 44,
                        height: 44,
                        child: _buildRiderMarkerWidget(),
                      ),
                  ],
                ),
              ],
            ),

            // Top-left: Job Type badge
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isPickup ? AppTheme.errorRed : AppTheme.teamMemberIconOrange,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPickup ? Icons.shopping_bag_outlined : Icons.local_shipping_outlined,
                      size: 13,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isPickup ? 'PICKUP' : 'DELIVERY',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Top-right: Status chip
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _formatStatus(widget.job.status),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom-right: Distance indicator
            if (_riderLocation != null)
              Positioned(
                bottom: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.straighten, size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        _calculateDistance(_riderLocation!, jobLocation),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Bottom-left: Recenter button
            Positioned(
              bottom: 12,
              left: 12,
              child: Material(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                elevation: 2,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _mapController.move(jobLocation, 15.0),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.my_location, size: 13, color: AppTheme.accentBlue),
                        SizedBox(width: 4),
                        Text(
                          'Center',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Modern Delivery Rider Badge (Option A: Always Upright, Non-Rotating)
  Widget _buildRiderMarkerWidget() {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer subtle pulse / glow ring
          Container(
            width: 40,
            height: 40,
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
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              // Inner solid brand-blue core with delivery rider scooter icon
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accentBlue,
                ),
                child: const Center(
                  child: Icon(
                    Icons.two_wheeler_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 2. Customer Information Card
  Widget _buildCustomerCard(String customerName) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: AppStyles.cardDecoration,
      child: Row(
        children: [
          // Initials Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.lightBlue,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.25)),
            ),
            child: Center(
              child: Text(
                _getInitials(customerName),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
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
                const Text(
                  'CUSTOMER',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textLight,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  customerName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                if (_customerPhone != null && _customerPhone!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    _customerPhone!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textLight,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => _openCustomerChat(customerName),
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.chat_bubble_outline, size: 18, color: Colors.teal.shade800),
                ),
                tooltip: 'Chat Customer',
              ),
              if (_customerPhone != null && _customerPhone!.isNotEmpty) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () => _showContactSheet(_customerPhone!, customerName),
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: AppTheme.lightBlue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.phone, size: 18, color: AppTheme.accentBlue),
                  ),
                  tooltip: 'Contact Customer',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 3. Location & Landmark Card
  Widget _buildLocationCard(String address, LatLng? jobLocation) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.lightBlue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.location_on, size: 18, color: AppTheme.accentBlue),
              ),
              const SizedBox(width: 10),
              const Text(
                'Address & Destination',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const Spacer(),
              if (address.isNotEmpty)
                InkWell(
                  onTap: () => _copyToClipboard(address, 'Address copied to clipboard'),
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Row(
                      children: [
                        Icon(Icons.copy, size: 12, color: AppTheme.accentBlue),
                        SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.accentBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            address.isNotEmpty ? address : 'No address specified',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.textDark,
              height: 1.35,
            ),
          ),

          // Highlighted Landmark tag
          if (widget.job.landmark != null && widget.job.landmark!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag_rounded, size: 14, color: Colors.amber.shade900),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Landmark: ${widget.job.landmark!}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Coordinates pill
          if (widget.job.latitude != null && widget.job.longitude != null) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => _copyToClipboard(
                '${widget.job.latitude}, ${widget.job.longitude}',
                'Coordinates copied',
              ),
              borderRadius: BorderRadius.circular(6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.gps_fixed, size: 12, color: AppTheme.textLight),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.job.latitude!.toStringAsFixed(6)}, ${widget.job.longitude!.toStringAsFixed(6)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textLight,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 4. Job & Order Info Card
  Widget _buildOrderInfoCard(bool isPickup) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.lightBlue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.receipt_long, size: 18, color: AppTheme.accentBlue),
              ),
              const SizedBox(width: 10),
              const Text(
                'Job Information',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildInfoRowItem('Job Number', widget.job.jobNumber ?? 'N/A'),
          const Divider(height: 18, color: AppTheme.borderGray),
          _buildInfoRowItem(
            'Job Type',
            isPickup ? 'Pickup from customer' : 'Delivery to customer',
          ),
          const Divider(height: 18, color: AppTheme.borderGray),
          _buildInfoRowItem('Status', _formatStatus(widget.job.status)),

          // Payment & notes — show loading placeholder or real data
          if (_isLoadingDetails) ...[
            const Divider(height: 18, color: AppTheme.borderGray),
            _buildLoadingPlaceholder(),
          ] else ...[
            if (_paymentStatus != null) ...[
              const Divider(height: 18, color: AppTheme.borderGray),
              _buildPaymentStatusRow(_paymentStatus!, _totalAmount),
            ],
            if (_customerNotes != null && _customerNotes!.isNotEmpty) ...[
              const Divider(height: 18, color: AppTheme.borderGray),
              const Text(
                'Customer Instructions',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textLight,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.softGray,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.6)),
                ),
                child: Text(
                  _customerNotes!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textDark,
                    fontStyle: FontStyle.italic,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRowItem(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.textLight,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textDark,
          ),
        ),
      ],
    );
  }

  /// Lightweight loading placeholder for async order metadata
  Widget _buildLoadingPlaceholder() {
    return Row(
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(
              AppTheme.accentBlue.withValues(alpha: 0.5),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'Loading details…',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textLight,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentStatusRow(String status, double? total) {
    final isPaid = status.toLowerCase() == 'paid';
    final hasAmount = total != null && total > 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Payment Status',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.textLight,
          ),
        ),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isPaid ? Colors.green.shade50 : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isPaid ? Colors.green.shade200 : Colors.amber.shade300,
                ),
              ),
              child: Text(
                isPaid ? 'PAID' : 'PENDING',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isPaid ? Colors.green.shade700 : Colors.amber.shade900,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              hasAmount ? '₱${total.toStringAsFixed(2)}' : 'Not set',
              style: TextStyle(
                fontSize: 13,
                fontWeight: hasAmount ? FontWeight.bold : FontWeight.w500,
                color: hasAmount ? AppTheme.textDark : AppTheme.textLight,
                fontStyle: hasAmount ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Fixed Bottom Action Bar
  Widget _buildBottomActions() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
        border: Border(
          top: BorderSide(color: AppTheme.borderGray.withValues(alpha: 0.6)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_takenByOther)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.errorRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.do_not_disturb_on, color: AppTheme.errorRed, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Job already taken by another rider',
                    style: TextStyle(
                      color: AppTheme.errorRed,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // Primary action: Start Job or Continue Tracking
            if (widget.job.status == 'pending')
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isStarting ? null : _startJob,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _isStarting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_arrow_rounded, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Start Job',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                ),
              )
            else if (widget.job.status == 'in_progress')
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RiderActiveRouteScreen(
                          jobs: [widget.job],
                          initialRiderLocation: _gpsProvider.currentLocation,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.navigation_rounded, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Continue Tracking',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),

            // Secondary action: Skip Order
            if ((widget.job.status == 'pending' || widget.job.status == 'in_progress') && !_takenByOther) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  onPressed: _isSkipping ? null : _showSkipBottomSheet,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                    side: BorderSide(color: Colors.orange.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSkipping
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.orange.shade800),
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.skip_next, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Skip Order',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  void _showSkipBottomSheet() {
    String? selectedReason;
    final reasons = [
      'Too far away',
      'Customer unreachable',
      'Schedule conflict',
      'Vehicle issue',
      'Other',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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
                    color: AppTheme.borderGray,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.skip_next, color: Colors.orange.shade700, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Skip This Order?',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        Text(
                          'This will release the job so another rider can take it.',
                          style: TextStyle(fontSize: 13, color: AppTheme.textLight),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Reason for skipping (optional):',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: reasons.map((reason) {
                  final isSelected = selectedReason == reason;
                  return ChoiceChip(
                    label: Text(reason),
                    selected: isSelected,
                    onSelected: (selected) {
                      setSheetState(() {
                        selectedReason = selected ? reason : null;
                      });
                    },
                    selectedColor: Colors.orange.shade100,
                    checkmarkColor: Colors.orange.shade700,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.orange.shade700 : AppTheme.textDark,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected ? Colors.orange.shade300 : AppTheme.borderGray,
                      ),
                    ),
                    backgroundColor: Colors.white,
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textLight,
                        side: const BorderSide(color: AppTheme.borderGray),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _skipJob(selectedReason);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Skip Order', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _skipJob(String? reason) async {
    setState(() => _isSkipping = true);

    try {
      await _riderService.skipJob(widget.job.id, reason: reason);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.skip_next, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Order skipped — it\'s now available for other riders.'),
                ),
              ],
            ),
            backgroundColor: Colors.orange.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to skip order: $e'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
        setState(() => _isSkipping = false);
      }
    }
  }

  @override
  void dispose() {
    _gpsProvider.stopTracking();
    super.dispose();
  }
}
