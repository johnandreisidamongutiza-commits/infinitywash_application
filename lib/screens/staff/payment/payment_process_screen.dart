import 'dart:io';

import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_error.dart';
import '../../../models/order.dart';
import '../../../services/order_service.dart';
import '../../../services/payment_service.dart';
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
  String? _selectedMethod;
  bool _isSuccess = false;
  bool _isProcessing = false;
  String? _transactionNumber;

  double get _totalAmount => widget.order.totalAmount ?? (widget.order.basePrice > 0 ? widget.order.basePrice : 170.0);

  bool get _isDelivery => widget.order.returnMethod == ReturnMethod.delivery;
  bool get _isPickup => widget.order.collectionMethod == CollectionMethod.riderPickup;
  bool get _isRiderOrder => _isDelivery || _isPickup;

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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildOrderSummary(),
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
              const Spacer(),
              _buildActionButton(),
            ],
          ),
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
              Text(
                '₱${_totalAmount.toStringAsFixed(2)}',
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
            : (_selectedMethod == 'GCash' ? _startGcashPayment : _processPayment),
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
                        : 'Complete Payment (₱${_totalAmount.toStringAsFixed(2)})',
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

  /// GCash: show the admin-uploaded QR first, then capture/upload the
  /// payment receipt before recording the payment.
  Future<void> _startGcashPayment() async {
    final receipt = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (context) => GcashQrPaymentScreen(
          title: 'Pay with GCash',
          orderLabel: widget.order.displayNumber,
          amount: _totalAmount,
          customerName: widget.order.customerName,
        ),
      ),
    );
    if (receipt == null || !mounted) return;
    await _processPayment(gcashReceiptFile: receipt);
  }

  Future<void> _processPayment({File? gcashReceiptFile}) async {
    if (_selectedMethod == null) return;

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

      final String txNumber;
      if (_selectedMethod == 'GCash' && gcashReceiptFile != null) {
        // GCash receipt flow: uploads the receipt and records the payment
        // as 'pending' (for review on the admin website) while marking the
        // order paid immediately.
        txNumber = await _paymentService.submitGcashPayment(
          orderId: widget.order.id,
          amount: _totalAmount,
          receiptFile: gcashReceiptFile,
          assignedStaffId: assignedStaffId,
        );
      } else {
        txNumber = await _orderService.recordPayment(
          orderId: widget.order.id,
          amount: _totalAmount,
          paymentMethod: _selectedMethod!,
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
                  _selectedMethod == 'GCash'
                      ? 'GCash receipt uploaded. Payment is marked as paid and pending admin verification.'
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
          _receiptRow('Payment Method', _selectedMethod ?? 'Cash'),
          const Divider(height: 20),
          _receiptRow('Total Amount Paid', '₱${_totalAmount.toStringAsFixed(2)}', isBold: true),
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
