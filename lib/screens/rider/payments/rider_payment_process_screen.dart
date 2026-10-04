import 'dart:io';

import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import '../../../services/order_service.dart';
import '../../../services/payment_service.dart';
import '../../../services/rider_service.dart';
import '../../../services/supabase_service.dart';
import '../../shared/gcash_qr_payment_screen.dart';

/// Screen for riders to collect payment (Cash or GCash) from customers
/// during pickup or delivery.
class RiderPaymentProcessScreen extends StatefulWidget {
  final LaundryOrder? order;
  final String? orderId;
  final String? orderNumber;
  final String? customerName;
  final String? customerPhone;
  final String? address;
  final double? amount;
  final String? weightDisplay;
  final String? jobType; // 'pickup' or 'delivery'

  const RiderPaymentProcessScreen({
    super.key,
    this.order,
    this.orderId,
    this.orderNumber,
    this.customerName,
    this.customerPhone,
    this.address,
    this.amount,
    this.weightDisplay,
    this.jobType,
  });

  @override
  State<RiderPaymentProcessScreen> createState() => _RiderPaymentProcessScreenState();
}

class _RiderPaymentProcessScreenState extends State<RiderPaymentProcessScreen> {
  final OrderService _orderService = OrderService();
  final PaymentService _paymentService = PaymentService();
  final RiderService _riderService = RiderService();

  String? _selectedMethod = 'Cash'; // Default to Cash for rider on-site collections
  bool _isSuccess = false;
  bool _isProcessing = false;
  String? _transactionNumber;

  String get _effectiveOrderId => widget.order?.id ?? widget.orderId ?? '';

  String get _effectiveOrderNumber =>
      widget.order?.displayNumber ?? widget.orderNumber ?? 'ORD';

  String get _effectiveCustomerName =>
      widget.order?.customerName ?? widget.customerName ?? 'Customer';

  String get _effectiveAddress =>
      widget.order?.deliveryAddress ?? widget.address ?? '';

  double get _effectiveAmount {
    if (widget.order?.totalAmount != null && widget.order!.totalAmount! > 0) {
      return widget.order!.totalAmount!;
    }
    if (widget.amount != null && widget.amount! > 0) {
      return widget.amount!;
    }
    if (widget.order != null && widget.order!.basePrice > 0) {
      return widget.order!.basePrice;
    }
    return 170.0; // Standard base minimum if no load price set yet
  }

  String get _effectiveWeightDisplay =>
      widget.order?.weightDisplay ?? widget.weightDisplay ?? 'Standard Load';

  @override
  Widget build(BuildContext context) {
    if (_isSuccess) return _buildSuccessView();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Collect Payment',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context, false),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildOrderSummaryCard(),
              const SizedBox(height: 24),
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
                title: 'Cash on Hand',
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
              const Spacer(),
              _buildActionButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderSummaryCard() {
    final isDelivery = (widget.jobType ?? '').toLowerCase() == 'delivery' ||
        (widget.order?.returnMethod == ReturnMethod.delivery);

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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDelivery ? Colors.purple.shade50 : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isDelivery ? Icons.local_shipping_outlined : Icons.inventory_2_outlined,
                          size: 14,
                          color: isDelivery ? Colors.purple.shade700 : AppTheme.accentBlue,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isDelivery ? 'Delivery' : 'Pickup',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDelivery ? Colors.purple.shade700 : AppTheme.accentBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _effectiveOrderNumber,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppTheme.textLight,
                    ),
                  ),
                ],
              ),
              Text(
                '₱${_effectiveAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: AppTheme.accentBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _effectiveCustomerName,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.black87,
            ),
          ),
          if (_effectiveAddress.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _effectiveAddress,
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
                  'Details: $_effectiveWeightDisplay',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                ),
                const Text(
                  'Laundry Service',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                ),
              ],
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
    final isSelected = _selectedMethod == method;

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
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accentBlue,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
        ),
        onPressed: (_selectedMethod == null || _isProcessing)
            ? null
            : (_selectedMethod == 'GCash' ? _startGcashPayment : () => _processPayment()),
        child: _isProcessing
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _selectedMethod == 'GCash' ? Icons.qr_code : Icons.check,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _selectedMethod == 'GCash'
                        ? 'Next: Show GCash QR'
                        : 'Complete Cash Payment (₱${_effectiveAmount.toStringAsFixed(2)})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// Launch GCash QR flow
  Future<void> _startGcashPayment() async {
    final receipt = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (context) => GcashQrPaymentScreen(
          title: 'Pay with GCash',
          orderLabel: _effectiveOrderNumber,
          amount: _effectiveAmount,
          customerName: _effectiveCustomerName,
        ),
      ),
    );

    if (receipt == null || !mounted) return;
    await _processPayment(gcashReceiptFile: receipt);
  }

  /// Process the payment (Cash or GCash)
  Future<void> _processPayment({File? gcashReceiptFile}) async {
    if (_selectedMethod == null || _effectiveOrderId.isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // Resolve rider's employee ID
      final riderEmployeeId = await _riderService.getCurrentRiderEmployeeId();
      String? processedBy = riderEmployeeId;

      // Fallback: If not found in employees table, use current user's profile ID
      if (processedBy == null) {
        final currentUser = SupabaseService.currentUser;
        if (currentUser != null) {
          final profile = await SupabaseService.client
              .from('profiles')
              .select('id')
              .eq('supabase_user_id', currentUser.id)
              .maybeSingle();
          processedBy = profile?['id'] as String?;
        }
      }

      final String txNumber;
      if (_selectedMethod == 'GCash' && gcashReceiptFile != null) {
        txNumber = await _paymentService.submitGcashPayment(
          orderId: _effectiveOrderId,
          amount: _effectiveAmount,
          receiptFile: gcashReceiptFile,
          assignedStaffId: processedBy,
        );
      } else {
        txNumber = await _orderService.recordPayment(
          orderId: _effectiveOrderId,
          amount: _effectiveAmount,
          paymentMethod: 'Cash',
          assignedStaffId: processedBy,
        );
      }

      if (!mounted) return;

      setState(() {
        _isProcessing = false;
        _transactionNumber = txNumber;
        _isSuccess = true;
      });
    } catch (e) {
      print('❌ Payment processing failed: $e');
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildSuccessView() {
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
                  'Payment Collected!',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 6),
                Text(
                  _selectedMethod == 'GCash'
                      ? 'GCash receipt uploaded. Payment is marked as paid.'
                      : 'Cash payment recorded successfully.',
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
                    onPressed: () => Navigator.pop(context, true), // Returns true to trigger refresh
                    child: const Text(
                      'Done',
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
          _receiptRow('Customer', _effectiveCustomerName),
          _receiptRow('Order No.', _effectiveOrderNumber),
          if (_transactionNumber != null)
            _receiptRow('Transaction #', _transactionNumber!),
          _receiptRow('Date', nowStr),
          _receiptRow('Payment Method', _selectedMethod ?? 'Cash'),
          const Divider(height: 20),
          _receiptRow('Total Amount', '₱${_effectiveAmount.toStringAsFixed(2)}', isBold: true),
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
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: isBold ? AppTheme.accentBlue : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
