import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';

class CustomerPaymentScreen extends StatefulWidget {
  final String orderId;
  final double weight;
  final double servicePrice;
  final double deliveryFee;
  final double? totalAmount;
  final VoidCallback? onPaymentSuccess;

  const CustomerPaymentScreen({
    super.key,
    this.orderId = 'IW-105',
    this.weight = 5.5,
    this.servicePrice = 170.0,
    this.deliveryFee = 0.0,
    this.totalAmount,
    this.onPaymentSuccess,
  });

  @override
  State<CustomerPaymentScreen> createState() => _CustomerPaymentScreenState();
}

class _CustomerPaymentScreenState extends State<CustomerPaymentScreen> {
  String _selectedMethod = 'G-Cash';
  bool _isSuccess = false;
  final TextEditingController _refController = TextEditingController(text: '902834195723');

  double get _finalTotal => widget.totalAmount ?? (widget.servicePrice + widget.deliveryFee);
  String get _orderDisplay => LaundryOrder.formatDisplayNumber(id: widget.orderId);

  @override
  void dispose() {
    _refController.dispose();
    super.dispose();
  }

  void _completePayment() {
    setState(() => _isSuccess = true);
    widget.onPaymentSuccess?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_isSuccess) return _buildSuccessView();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Complete Payment'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAmountCard(),
            const SizedBox(height: 24),

            // Per-kilo bill breakdown
            _buildBreakdownCard(),
            const SizedBox(height: 24),

            Text('Payment Method', style: AppTheme.lightTheme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildMethodCard(
              'G-Cash',
              Icons.account_balance_wallet_outlined,
              'Instant confirmation via GCash QR or number',
            ),
            const SizedBox(height: 10),
            _buildMethodCard(
              'Cash on Delivery',
              Icons.payments_outlined,
              'Pay rider in cash upon doorstep delivery',
            ),
            const SizedBox(height: 20),

            if (_selectedMethod == 'G-Cash') ...[
              _buildGcashInstructions(),
              const SizedBox(height: 20),
              Text('GCash Reference Number', style: AppTheme.lightTheme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _refController,
                decoration: InputDecoration(
                  hintText: 'Enter 12-digit GCash reference #',
                  filled: true,
                  fillColor: AppTheme.softGray,
                  prefixIcon: const Icon(Icons.receipt_long, color: AppTheme.accentBlue),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter reference from your GCash SMS or receipt.',
                style: TextStyle(fontSize: 11, color: AppTheme.textLight),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.green, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'You chose Cash on Delivery. Please prepare ₱${_finalTotal.toStringAsFixed(2)} when the rider arrives with your clean clothes.',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textDark, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: _completePayment,
              child: Text(
                _selectedMethod == 'G-Cash'
                    ? 'Confirm GCash Payment (₱${_finalTotal.toStringAsFixed(2)})'
                    : 'Confirm Cash on Delivery',
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.accentBlue,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentBlue.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Verified Bill',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Order #$_orderDisplay',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '₱${_finalTotal.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Based on store verified weight: ${widget.weight.toStringAsFixed(1)} kg',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.softGray,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Itemized Calculation',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Full Service Wash, Dry & Fold (${widget.weight.toStringAsFixed(1)} kg)',
                style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
              ),
              Text(
                '₱${widget.servicePrice.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Detergent + Fab Con',
                style: TextStyle(fontSize: 13, color: AppTheme.textDark),
              ),
              Text(
                'INCLUDED',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Pick Up & Delivery',
                style: TextStyle(fontSize: 13, color: AppTheme.textDark),
              ),
              Text(
                'INCLUDED (FREE)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Amount',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
              Text(
                '₱${_finalTotal.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMethodCard(String method, IconData icon, String subtitle) {
    final bool isSelected = _selectedMethod == method;
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = method),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.accentBlue : AppTheme.borderGray,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.accentBlue.withValues(alpha: 0.1) : AppTheme.softGray,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: isSelected ? AppTheme.accentBlue : AppTheme.textLight, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(method, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.textLight)),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? AppTheme.accentBlue : AppTheme.borderGray,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGcashInstructions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF007DFE).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF007DFE).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF007DFE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.qr_code_2, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Send via GCash Send Money / QR',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF005AB5)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Account Name:', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
              Text('INFINITYWASH HUB', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('GCash Mobile Number:', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
              Text('0917-555-WASH (9274)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, size: 54, color: Colors.green),
                ),
                const SizedBox(height: 20),
                Text('Payment Confirmed!', style: AppTheme.lightTheme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  _selectedMethod == 'G-Cash'
                      ? 'Your GCash payment has been verified. Your clean laundry is ready for dispatch.'
                      : 'Cash on delivery recorded. Please prepare payment upon delivery.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textLight, fontSize: 13),
                ),
                const SizedBox(height: 28),
                _buildReceiptCard(),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to Active Orders'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.softGray,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Column(
        children: [
          const Text('INFINITYWASH LAUNDRY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Text('Official E-Receipt', style: TextStyle(fontSize: 10, letterSpacing: 1.5, color: AppTheme.textLight)),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Order Number', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
              Text('#$_orderDisplay', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Verified Weight', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
              Text('${widget.weight.toStringAsFixed(1)} kg • Full Service (₱${widget.servicePrice.toStringAsFixed(0)})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Payment Mode', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
              Text(_selectedMethod, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          if (_selectedMethod == 'G-Cash') ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Reference No.', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
                Text(_refController.text.isNotEmpty ? _refController.text : '902834195723',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.accentBlue)),
              ],
            ),
          ],
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Paid', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text('₱${_finalTotal.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
            ],
          ),
        ],
      ),
    );
  }
}
