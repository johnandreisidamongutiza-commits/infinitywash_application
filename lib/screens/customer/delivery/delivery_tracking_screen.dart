import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/customer_service.dart';
import '../../../services/delivery_tracking_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/phone_helper.dart';
import '../../../widgets/top_notification.dart';
import '../chats/customer_chat_detail_screen.dart';
import '../orders/customer_orders_screen.dart';
import '../orders/request_service_flow.dart';
import 'order_delivery_tracking_screen.dart';

/// Customer Deliveries Hub: Displays active deliveries and pickups organized per order.
/// Each order has its own card with status, assigned rider, address, and dedicated map tracking.
class DeliveryTrackingScreen extends StatefulWidget {
  final String? initialOrderId;

  const DeliveryTrackingScreen({
    super.key,
    this.initialOrderId,
  });

  @override
  State<DeliveryTrackingScreen> createState() => _DeliveryTrackingScreenState();
}

class _DeliveryTrackingScreenState extends State<DeliveryTrackingScreen> {
  final DeliveryTrackingService _trackingService = DeliveryTrackingService();
  final CustomerService _customerService = CustomerService();

  bool _isLoading = true;
  String? _errorMessage;
  List<ActiveDelivery> _deliveries = [];
  bool _hasHandledInitialOrder = false;

  @override
  void initState() {
    super.initState();
    _loadDeliveries();
  }

  /// Loads all active deliveries and pickups for the authenticated customer.
  Future<void> _loadDeliveries() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final customerId = await _customerService.getCurrentAuthenticatedCustomerId();
      final deliveries = await _trackingService.getActiveDeliveries(customerId);

      if (!mounted) return;

      setState(() {
        _deliveries = deliveries;
        _isLoading = false;
      });

      // If an initial order ID was passed, automatically open its dedicated tracking screen
      if (widget.initialOrderId != null && !_hasHandledInitialOrder) {
        _hasHandledInitialOrder = true;
        final match = deliveries.where((d) => d.order.id == widget.initialOrderId).firstOrNull;
        if (match != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _openOrderTracking(match);
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load active deliveries. Please pull down to retry.';
      });
      debugPrint('❌ Error loading customer deliveries hub: $e');
    }
  }

  void _openOrderTracking(ActiveDelivery delivery) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderDeliveryTrackingScreen(
          delivery: delivery,
          orderId: delivery.order.id,
        ),
      ),
    ).then((_) => _loadDeliveries());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Deliveries & Pickups',
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppTheme.textDark,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.accentBlue),
            tooltip: 'Refresh Deliveries',
            onPressed: _loadDeliveries,
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
              'Checking active deliveries...',
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
                onPressed: _loadDeliveries,
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

    if (_deliveries.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadDeliveries,
      color: AppTheme.accentBlue,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // ── Header Summary ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Active Deliveries',
                style: GoogleFonts.lexend(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_deliveries.length} active',
                  style: GoogleFonts.lexend(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accentBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Per-Order Delivery Cards ──
          ..._deliveries.map((delivery) => _buildOrderDeliveryCard(delivery)),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Per-order delivery card displaying rider info, order details, and "Track on Map" action.
  Widget _buildOrderDeliveryCard(ActiveDelivery delivery) {
    final order = delivery.order;
    final isPickup = delivery.isPickup;

    // Status styling
    final String statusLabel;
    final Color statusColor;
    final Color statusBg;

    if (delivery.isCompleted) {
      statusLabel = isPickup ? 'Picked Up' : 'Delivered';
      statusColor = AppTheme.statusCompleted;
      statusBg = AppTheme.statusCompletedBg;
    } else if (delivery.isInProgress) {
      statusLabel = isPickup ? 'Rider Heading to You' : 'Out for Delivery';
      statusColor = AppTheme.statusActive;
      statusBg = AppTheme.statusActiveBg;
    } else if (delivery.hasAssignedRider) {
      statusLabel = 'Rider Assigned';
      statusColor = AppTheme.statusActive;
      statusBg = AppTheme.statusActiveBg;
    } else {
      statusLabel = 'Finding Rider...';
      statusColor = AppTheme.statusActive;
      statusBg = AppTheme.statusActiveBg;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderGray),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openOrderTracking(delivery),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Card Header: Order Code & Live Status Badge ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isPickup
                                ? Colors.indigo.shade50
                                : AppTheme.accentBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isPickup ? Icons.shopping_bag_outlined : Icons.delivery_dining,
                            size: 18,
                            color: isPickup ? Colors.indigo : AppTheme.accentBlue,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.displayNumber,
                              style: GoogleFonts.lexend(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: AppTheme.textDark,
                              ),
                            ),
                            Text(
                              isPickup ? 'Rider Pickup Service' : 'Home Delivery Service',
                              style: GoogleFonts.lexend(
                                fontSize: 11,
                                color: AppTheme.textLight,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (delivery.isInProgress) ...[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            statusLabel,
                            style: GoogleFonts.lexend(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24, color: AppTheme.borderGray),

                // ── Address Row ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.accentBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        delivery.destinationAddress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.lexend(fontSize: 12, color: AppTheme.textDark),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Rider Row (if assigned) ──
                if (delivery.hasAssignedRider) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.softGray.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(
                            color: AppTheme.lightBlue,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              delivery.riderName?.isNotEmpty == true
                                  ? delivery.riderName!.substring(0, 1).toUpperCase()
                                  : 'R',
                              style: GoogleFonts.lexend(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: AppTheme.accentBlue,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                delivery.riderName ?? 'Assigned Rider',
                                style: GoogleFonts.lexend(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: AppTheme.textDark,
                                ),
                              ),
                              Text(
                                delivery.vehicleDetails ?? 'Delivery Vehicle',
                                style: GoogleFonts.lexend(
                                  fontSize: 11,
                                  color: AppTheme.textLight,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Chat button shortcut
                        IconButton(
                          icon: const Icon(Icons.chat_bubble_outline, size: 18, color: AppTheme.accentBlue),
                          tooltip: 'Chat with Rider',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CustomerChatDetailScreen(
                                  recipientName: delivery.riderName ?? 'Rider',
                                  recipientRole: isPickup ? 'Pickup Rider' : 'Delivery Rider',
                                  recipientType: ChatRecipientType.rider,
                                  orderId: order.id,
                                  orderNumber: order.displayNumber,
                                  phoneNumber: delivery.riderPhone,
                                ),
                              ),
                            );
                          },
                        ),

                        // Call rider shortcut
                        IconButton(
                          icon: const Icon(Icons.phone_outlined, size: 18, color: Colors.green),
                          tooltip: 'Call Rider',
                          onPressed: () => PhoneHelper.openDialer(
                            context,
                            phone: delivery.riderPhone,
                            contactName: delivery.riderName ?? 'Rider',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // ── Primary Action: Track on Map Button ──
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () => _openOrderTracking(delivery),
                    icon: const Icon(Icons.navigation_rounded, size: 18),
                    label: Text(
                      'Track Live on Map',
                      style: GoogleFonts.lexend(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Opens native dialer with pre-filled number and copies to clipboard.
  Future<void> _handlePhoneAction(String? phone, String name) async {
    await PhoneHelper.openDialer(context, phone: phone, contactName: name);
  }

  /// Clean empty state when the customer has no active deliveries or pickups.
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppTheme.lightBlue.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delivery_dining_outlined,
                size: 52,
                color: AppTheme.accentBlue,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Active Deliveries',
              style: GoogleFonts.lexend(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You have no laundry scheduled for pickup or out for delivery right now. When a rider is on the way, live tracking will appear here per order.',
              textAlign: TextAlign.center,
              style: GoogleFonts.lexend(
                fontSize: 13,
                color: AppTheme.textLight,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RequestServiceFlow()),
                  ).then((_) => _loadDeliveries());
                },
                icon: const Icon(Icons.add_shopping_cart, size: 20),
                label: const Text('Request Laundry Service', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CustomerOrdersScreen()),
                  );
                },
                icon: const Icon(Icons.assignment_outlined, size: 20),
                label: const Text('View All Orders', style: TextStyle(fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accentBlue,
                  side: const BorderSide(color: AppTheme.accentBlue, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
