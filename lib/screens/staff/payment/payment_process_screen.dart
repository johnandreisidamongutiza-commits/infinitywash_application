import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_error.dart';
import '../../../models/order.dart';
import '../../../services/order_service.dart';
import '../../../services/payment_service.dart';
import '../../../services/loyalty_service.dart';
import '../../../services/supabase_service.dart';
import '../../shared/gcash_qr_payment_screen.dart';

class PaymentProcessScreen extends StatefulWidget {
  final LaundryOrder order;
  const PaymentProcessScreen({super.key, required this.order});

  @override
  State<PaymentProcessScreen> createState() => _PaymentProcessScreenState();
}

class _PaymentProcessScreenState extends State<PaymentProcessScreen> {
  final OrderService _orderService = OrderService();
  final PaymentService _paymentService = PaymentService();
  final LoyaltyService _loyaltyService = LoyaltyService();

  String? _selectedMethod;
  bool _isSuccess = false;
  bool _isProcessing = false;
  String? _transactionNumber;

  // Loyalty & RFID
  RealtimeChannel? _rfidScanChannel;
  LoyaltyCardInfo? _loyaltyCardInfo;
  bool _loadingLoyalty = false;
  int _freeLoadsToRedeem = 0;
  String? _lastRealtimeUid;
  DateTime? _lastRealtimeScanAt;

  double get _subtotal => widget.order.totalAmount ?? (widget.order.basePrice > 0 ? widget.order.basePrice : 170.0);
  int get _totalLoads => widget.order.loads.isNotEmpty ? widget.order.loads.length : (_subtotal / 170.0).round().clamp(1, 99);
  int get _maxFreeLoads => _loyaltyCardInfo == null ? 0 : math.min(_loyaltyCardInfo!.freeLoadsAvailable, _totalLoads);
  double get _freeLoadDiscount => _freeLoadsToRedeem * 170.0;
  double get _netAmount => (_subtotal - _freeLoadDiscount).clamp(0.0, double.infinity);

  bool get _isDelivery => widget.order.returnMethod == ReturnMethod.delivery;
  bool get _isPickup => widget.order.collectionMethod == CollectionMethod.riderPickup;
  bool get _isRiderOrder => _isDelivery || _isPickup;
  bool get _isWalkIn => widget.order.channel == OrderChannel.walkIn && !_isRiderOrder;
  bool get _needsCheckIn => widget.order.needsCheckIn || widget.order.loads.isEmpty;

  @override
  void initState() {
    super.initState();
    if (_isWalkIn) {
      _subscribeToLiveRfidScans();
      _loadInitialCustomerLoyaltyCard();
    }
  }

  @override
  void dispose() {
    _rfidScanChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToLiveRfidScans() {
    try {
      _rfidScanChannel = SupabaseService.client
          .channel('payment_process_rfid_scans')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'scanned_rfid_events',
            callback: (payload) {
              final uid = payload.newRecord['uid'];
              if (uid is! String || uid.trim().isEmpty || !mounted) return;

              final cleanUid = uid.trim().toUpperCase();
              final now = DateTime.now();
              if (_lastRealtimeUid == cleanUid &&
                  _lastRealtimeScanAt != null &&
                  now.difference(_lastRealtimeScanAt!) <
                      const Duration(milliseconds: 1500)) {
                return;
              }
              _lastRealtimeUid = cleanUid;
              _lastRealtimeScanAt = now;
              _lookupLoyaltyCard(cleanUid);
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Could not listen for RFID scans in payment process: $e');
    }
  }

  Future<void> _loadInitialCustomerLoyaltyCard() async {
    final customerId = widget.order.customerId;
    if (customerId == null || customerId.isEmpty) return;
    setState(() => _loadingLoyalty = true);
    try {
      final card = await _loyaltyService.getLinkedCard(customerId);
      if (mounted && card != null) {
        setState(() {
          _loyaltyCardInfo = card;
          _loadingLoyalty = false;
        });
      } else if (mounted) {
        setState(() => _loadingLoyalty = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loadingLoyalty = false);
    }
  }

  Future<void> _lookupLoyaltyCard(String uid) async {
    final cleanUid = uid.trim().toUpperCase();
    if (cleanUid.isEmpty) return;

    setState(() => _loadingLoyalty = true);
    try {
      final card = await _loyaltyService.lookupCardByUid(cleanUid);
      if (!mounted) return;
      if (card == null) {
        setState(() => _loadingLoyalty = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Card "$cleanUid" is not registered in the system.'),
            backgroundColor: Colors.orange[800],
          ),
        );
        return;
      }

      setState(() {
        _loyaltyCardInfo = card;
        _freeLoadsToRedeem = 0;
        _loadingLoyalty = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loyalty Card detected: ${card.ownerName} (${card.pointsBalance} pts)'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _loadingLoyalty = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error looking up card: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showManualUidDialog() {
    final controller = TextEditingController(text: _loyaltyCardInfo?.uid ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter Loyalty Card UID', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: 'e.g. 5A92B3C1',
            prefixIcon: const Icon(Icons.credit_card),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentBlue),
            onPressed: () {
              final uid = controller.text.trim();
              Navigator.pop(ctx);
              if (uid.isNotEmpty) {
                _lookupLoyaltyCard(uid);
              }
            },
            child: const Text('Lookup', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isSuccess) return _buildSuccessView();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Process Payment',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_needsCheckIn)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.scale_outlined, color: Colors.amber.shade900, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Check-In & Weighing Required',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'This laundry has not been checked in and weighed yet. Final price and load count are pending.',
                                    style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    _buildOrderSummary(),
                    if (_isWalkIn) ...[
                      const SizedBox(height: 16),
                      _buildLoyaltyCardSection(),
                    ],
                    const SizedBox(height: 20),
                    if (_netAmount > 0.0) ...[
                      const Text(
                        'Select Payment Method',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildMethodCard(
                        method: 'Cash',
                        title: 'Cash',
                        subtitle: 'Collect exact amount from customer',
                        icon: Icons.payments_outlined,
                        badgeText: 'Instant',
                        color: Colors.green[700]!,
                      ),
                      const SizedBox(height: 12),
                      _buildMethodCard(
                        method: 'GCash',
                        title: 'GCash QR',
                        subtitle: 'Customer scans QR & uploads receipt',
                        icon: Icons.qr_code_scanner,
                        badgeText: 'QR Code',
                        color: AppTheme.accentBlue,
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline, color: Colors.green.shade700, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Order is 100% covered by $_freeLoadsToRedeem Free Load(s). No cash or GCash payment required.',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    offset: const Offset(0, -3),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: _buildActionButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _buildOrderTypeBadge(),
                  const SizedBox(width: 8),
                  Text(
                    widget.order.displayNumber,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppTheme.textLight,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_freeLoadsToRedeem > 0)
                    Text(
                      '₱${_subtotal.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 13,
                        decoration: TextDecoration.lineThrough,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  Text(
                    '₱${_netAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: AppTheme.accentBlue,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            widget.order.customerName,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.black87,
            ),
          ),
          if (_isDelivery &&
              widget.order.deliveryAddress != null &&
              widget.order.deliveryAddress!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.order.deliveryAddress!,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.softGray,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${widget.order.loads.length} load(s) • ${widget.order.weightDisplay}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                ),
                const Text(
                  'Full Service',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                ),
              ],
            ),
          ),
          if (_freeLoadsToRedeem > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.loyalty_outlined, size: 15, color: Colors.green.shade700),
                      const SizedBox(width: 6),
                      Text(
                        'Loyalty Free Load ($_freeLoadsToRedeem)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                      ),
                    ],
                  ),
                  Text(
                    '-₱${_freeLoadDiscount.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoyaltyCardSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _loyaltyCardInfo != null ? Colors.green.shade200 : Colors.grey.shade200,
          width: _loyaltyCardInfo != null ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _loyaltyCardInfo != null ? Colors.green.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.credit_card,
                  size: 20,
                  color: _loyaltyCardInfo != null ? Colors.green.shade700 : AppTheme.accentBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _loyaltyCardInfo != null ? 'Loyalty Card Connected' : 'Loyalty Card (Tap RFID to Redeem)',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      _loyaltyCardInfo != null
                          ? 'UID: ${_loyaltyCardInfo!.uid} • ${_loyaltyCardInfo!.pointsBalance} pts'
                          : 'Tap card on scanner or enter UID',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _showManualUidDialog,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _loyaltyCardInfo != null ? 'Change' : 'Enter UID',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (_loadingLoyalty) ...[
            const SizedBox(height: 12),
            const Center(
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ] else if (_loyaltyCardInfo != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            if (_loyaltyCardInfo!.freeLoadsAvailable <= 0) ...[
              Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Needs ${_loyaltyCardInfo!.pointsToNextRedemption} more pts for next free load (has ${_loyaltyCardInfo!.pointsBalance} pts).',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Redeem Free Load',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                      ),
                      Text(
                        '${_loyaltyCardInfo!.freeLoadsAvailable} free load(s) available',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.softGray,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 16),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: _freeLoadsToRedeem > 0
                              ? () => setState(() => _freeLoadsToRedeem--)
                              : null,
                        ),
                        Text(
                          '$_freeLoadsToRedeem',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 16),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: _freeLoadsToRedeem < _maxFreeLoads
                              ? () => setState(() => _freeLoadsToRedeem++)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildOrderTypeBadge() {
    final String label;
    final IconData icon;
    final Color color;
    final Color bgColor;

    if (_isDelivery) {
      label = 'Delivery';
      icon = Icons.local_shipping_outlined;
      color = Colors.indigo.shade700;
      bgColor = Colors.indigo.shade50;
    } else if (_isPickup) {
      label = 'Rider Pickup';
      icon = Icons.two_wheeler;
      color = Colors.purple.shade700;
      bgColor = Colors.purple.shade50;
    } else {
      label = 'Walk-in';
      icon = Icons.storefront_outlined;
      color = AppTheme.accentBlue;
      bgColor = Colors.blue.shade50;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodCard({
    required String method,
    required String title,
    required String subtitle,
    required IconData icon,
    required String badgeText,
    required Color color,
  }) {
    bool isSelected = _selectedMethod == method;
    return GestureDetector(
      onTap: _isProcessing ? null : () => setState(() => _selectedMethod = method),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.accentBlue : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.accentBlue.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.1) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? color : Colors.grey.shade600,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? AppTheme.accentBlue : Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isSelected ? AppTheme.accentBlue : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    if (_needsCheckIn) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey.shade400,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: null,
          icon: const Icon(Icons.scale_outlined, color: Colors.white),
          label: const Text(
            'Check In & Weigh Laundry First',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      );
    }

    final isFullFreeLoad = _netAmount == 0.0 && _freeLoadsToRedeem > 0;
    final canSubmit = isFullFreeLoad || (_selectedMethod != null && !_isProcessing);

    final String buttonLabel;
    if (isFullFreeLoad) {
      buttonLabel = 'Redeem Free Load & Settle (₱0.00)';
    } else if (_selectedMethod == 'GCash') {
      buttonLabel = 'Next: Show GCash QR (₱${_netAmount.toStringAsFixed(2)})';
    } else {
      buttonLabel = 'Complete Payment (₱${_netAmount.toStringAsFixed(2)})';
    }

    final IconData buttonIcon;
    if (isFullFreeLoad) {
      buttonIcon = Icons.loyalty_outlined;
    } else if (_selectedMethod == 'GCash') {
      buttonIcon = Icons.qr_code;
    } else {
      buttonIcon = Icons.check;
    }

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isFullFreeLoad ? Colors.green.shade700 : AppTheme.accentBlue,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
        ),
        onPressed: (!canSubmit || _isProcessing)
            ? null
            : (_selectedMethod == 'GCash' && !isFullFreeLoad ? _startGcashPayment : () => _processPayment()),
        child: _isProcessing
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(buttonIcon, color: Colors.white),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      buttonLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// GCash: show the admin-uploaded QR first, then capture/upload the
  /// payment receipt before recording the payment.
  Future<void> _startGcashPayment() async {
    final receipt = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (context) => GcashQrPaymentScreen(
          title: 'Pay with GCash',
          orderLabel: widget.order.displayNumber,
          amount: _netAmount,
          customerName: widget.order.customerName,
        ),
      ),
    );
    if (receipt == null || !mounted) return;
    await _processPayment(gcashReceiptFile: receipt);
  }

  Future<void> _processPayment({File? gcashReceiptFile}) async {
    if (_needsCheckIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot collect payment before laundry is checked in and weighed.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final isFullFreeLoad = _netAmount == 0.0 && _freeLoadsToRedeem > 0;
    if (!isFullFreeLoad && _selectedMethod == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // Find staff ID
      final currentUser = SupabaseService.currentUser;
      String? assignedStaffId;
      if (currentUser != null) {
        final profile = await SupabaseService.client
            .from('profiles')
            .select('id')
            .eq('supabase_user_id', currentUser.id)
            .maybeSingle();

        if (profile != null) {
          final employee = await SupabaseService.client
              .from('employees')
              .select('id')
              .eq('profile_id', profile['id'])
              .maybeSingle();

          if (employee != null) {
            assignedStaffId = employee['id'] as String;
          }
        }
      }

      // 1. Redeem points if free loads used
      if (_freeLoadsToRedeem > 0 && _loyaltyCardInfo != null) {
        await _loyaltyService.redeemPoints(
          cardId: _loyaltyCardInfo!.cardId,
          customerId: widget.order.customerId,
          freeLoadsToRedeem: _freeLoadsToRedeem,
          orderId: widget.order.id,
          orderNumber: widget.order.orderNumber,
        );

        // Update order discount and free loads
        await SupabaseService.client.from('orders').update({
          'discount_amount': _freeLoadDiscount,
          'free_loads_redeemed': _freeLoadsToRedeem,
          'total_amount': _netAmount,
        }).eq('id', widget.order.id);
      }

      // 2. Record payment
      final String txNumber;
      if (isFullFreeLoad) {
        txNumber = await _orderService.recordPayment(
          orderId: widget.order.id,
          amount: 0.0,
          paymentMethod: 'Loyalty Free Load',
          assignedStaffId: assignedStaffId,
        );
      } else if (_selectedMethod == 'GCash' && gcashReceiptFile != null) {
        txNumber = await _paymentService.submitGcashPayment(
          orderId: widget.order.id,
          amount: _netAmount,
          receiptFile: gcashReceiptFile,
          assignedStaffId: assignedStaffId,
        );
      } else {
        txNumber = await _orderService.recordPayment(
          orderId: widget.order.id,
          amount: _netAmount,
          paymentMethod: _selectedMethod ?? 'Cash',
          assignedStaffId: assignedStaffId,
        );
      }

      if (!mounted) return;

      setState(() {
        _isProcessing = false;
        _transactionNumber = txNumber;
        _isSuccess = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment failed. ${mapErrorToMessage(e)}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Widget _buildSuccessView() {
    final isFullFreeLoad = _netAmount == 0.0 && _freeLoadsToRedeem > 0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle, size: 76, color: Colors.green),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Payment Successful',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 6),
                Text(
                  isFullFreeLoad
                      ? 'Order fully redeemed via Loyalty Free Load.'
                      : (_selectedMethod == 'GCash'
                          ? 'GCash receipt uploaded. Payment is marked as paid and pending admin verification.'
                          : 'Cash payment recorded successfully.'),
                  style: const TextStyle(fontSize: 13, color: AppTheme.textLight),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                _buildReceiptCard(),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      'Back to Payments',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
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

  Widget _buildReceiptCard() {
    final now = DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final nowStr = '${months[now.month - 1]} ${now.day.toString().padLeft(2, '0')}, ${now.year}';

    final String orderType;
    if (_isDelivery) {
      orderType = 'Delivery';
    } else if (_isPickup) {
      orderType = 'Rider Pickup';
    } else {
      orderType = 'Walk-in';
    }

    final String paymentMethodDisplay;
    if (_freeLoadsToRedeem > 0) {
      if (_netAmount == 0.0) {
        paymentMethodDisplay = 'Loyalty Free Load ($_freeLoadsToRedeem Load${_freeLoadsToRedeem > 1 ? "s" : ""})';
      } else {
        paymentMethodDisplay = 'Free Load ($_freeLoadsToRedeem) + ${_selectedMethod ?? "Cash"}';
      }
    } else {
      paymentMethodDisplay = _selectedMethod ?? 'Cash';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          const Text('INFINITY WASH', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const Text(
            'Official Digital Receipt',
            style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: AppTheme.textLight),
          ),
          const Divider(height: 24),
          _receiptRow('Customer', widget.order.customerName),
          _receiptRow('Order No.', widget.order.displayNumber),
          if (_transactionNumber != null)
            _receiptRow('Ref #', _transactionNumber!),
          _receiptRow('Order Type', orderType),
          _receiptRow('Weight', widget.order.weightDisplay),
          _receiptRow('Package', 'Full Service (Wash, Dry & Fold)'),
          _receiptRow('Detergent & Fab Con', 'INCLUDED (FREE)'),
          _receiptRow('Pick-up & Delivery', _isRiderOrder ? 'INCLUDED (FREE)' : 'N/A'),
          _receiptRow('Date', nowStr),
          _receiptRow('Payment Method', paymentMethodDisplay),
          if (_freeLoadsToRedeem > 0) ...[
            const Divider(height: 20),
            _receiptRow('Subtotal', '₱${_subtotal.toStringAsFixed(2)}'),
            _receiptRow('Loyalty Free Load', '-₱${_freeLoadDiscount.toStringAsFixed(2)}'),
          ],
          const Divider(height: 20),
          _receiptRow('Total Amount Paid', '₱${_netAmount.toStringAsFixed(2)}', isBold: true),
        ],
      ),
    );
  }

  Widget _receiptRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textLight)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: isBold ? AppTheme.accentBlue : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
