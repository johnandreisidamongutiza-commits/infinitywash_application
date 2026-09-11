import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';

class PaymentProcessScreen extends StatefulWidget {
  final LaundryOrder order;
  const PaymentProcessScreen({super.key, required this.order});

  @override
  State<PaymentProcessScreen> createState() => _PaymentProcessScreenState();
}

class _PaymentProcessScreenState extends State<PaymentProcessScreen> {
  String? _selectedMethod;
  bool _isSuccess = false;

  @override
  Widget build(BuildContext context) {
    if (_isSuccess) return _buildSuccessView();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Process Payment'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOrderSummary(),
            const SizedBox(height: 30),
            Text('Select Payment Method', style: AppTheme.lightTheme.textTheme.titleMedium),
            const SizedBox(height: 16),
            _buildMethodCard('Cash', Icons.money),
            const SizedBox(height: 12),
            _buildMethodCard('G-Cash', Icons.account_balance_wallet_outlined),
            const Spacer(),
            ElevatedButton(
              onPressed: _selectedMethod == null ? null : _processPayment,
              child: const Text('Complete Payment'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderSummary() {
    const double total = 170.0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.softGray,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.order.customerName, style: AppTheme.lightTheme.textTheme.titleMedium),
                  Text('Order ${widget.order.id} • ${widget.order.weight.toStringAsFixed(1)} kg', style: AppTheme.lightTheme.textTheme.bodyMedium),
                ],
              ),
              Text('₱${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: AppTheme.accentBlue)),
            ],
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Full Service (Wash, Dry & Fold) • Detergent, Fab Con & Delivery Included',
              style: TextStyle(fontSize: 11, color: AppTheme.textLight),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodCard(String method, IconData icon) {
    bool isSelected = _selectedMethod == method;
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = method),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: isSelected ? AppStyles.selectedCardDecoration : AppStyles.cardDecoration,
        child: Row(
          children: [
            Icon(icon, color: isSelected ? AppTheme.accentBlue : AppTheme.textLight),
            const SizedBox(width: 16),
            Text(method, style: AppTheme.lightTheme.textTheme.titleMedium),
            const Spacer(),
            if (isSelected) const Icon(Icons.check_circle, color: AppTheme.accentBlue),
          ],
        ),
      ),
    );
  }

  void _processPayment() {
    setState(() => _isSuccess = true);
  }

  Widget _buildSuccessView() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, size: 90, color: Colors.green),
              const SizedBox(height: 20),
              Text('Payment Successful', style: AppTheme.lightTheme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('The digital receipt has been generated.', style: AppTheme.lightTheme.textTheme.bodyMedium),
              const SizedBox(height: 30),
              _buildReceiptCard(),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to Payments'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppStyles.cardDecoration,
      child: Column(
        children: [
          const Text('INFINITY WASH', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          const Text('Official Digital Receipt', style: TextStyle(fontSize: 12, letterSpacing: 2, color: AppTheme.textLight)),
          const SizedBox(height: 20),
          _receiptRow('Customer', widget.order.customerName),
          _receiptRow('Order ID', widget.order.id),
          _receiptRow('Weight', '${widget.order.weight.toStringAsFixed(1)} kg'),
          _receiptRow('Package', 'Full Service (Wash, Dry & Fold)'),
          _receiptRow('Detergent & Fab Con', 'INCLUDED (FREE)'),
          _receiptRow('Pick-up & Delivery', 'INCLUDED (FREE)'),
          _receiptRow('Date', 'Sept 04, 2026'),
          _receiptRow('Payment Method', _selectedMethod!),
          const Divider(height: 24),
          _receiptRow('Total Amount Paid', '₱170.00', isBold: true),
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
          Text(label, style: AppTheme.lightTheme.textTheme.bodyMedium),
          Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}
