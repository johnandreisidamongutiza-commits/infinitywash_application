import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class CustomerPaymentScreen extends StatefulWidget {
  const CustomerPaymentScreen({super.key});

  @override
  State<CustomerPaymentScreen> createState() => _CustomerPaymentScreenState();
}

class _CustomerPaymentScreenState extends State<CustomerPaymentScreen> {
  String? _selectedMethod;
  bool _isSuccess = false;

  @override
  Widget build(BuildContext context) {
    if (_isSuccess) return _buildSuccessView();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Payment'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAmountCard(),
            const SizedBox(height: 30),
            Text('Select Payment Method', style: AppTheme.lightTheme.textTheme.titleMedium),
            const SizedBox(height: 16),
            _buildMethodCard('Cash', Icons.money),
            const SizedBox(height: 12),
            _buildMethodCard('G-Cash', Icons.account_balance_wallet_outlined),
            const Spacer(),
            ElevatedButton(
              onPressed: _selectedMethod == null ? null : () => setState(() => _isSuccess = true),
              child: const Text('Pay Now'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.accentBlue,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        children: [
          Text('Total Amount to Pay', style: TextStyle(color: Colors.white70, fontSize: 14)),
          SizedBox(height: 8),
          Text('₱350.00', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
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
            Text(method, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const Spacer(),
            if (isSelected) const Icon(Icons.check_circle, color: AppTheme.accentBlue),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, size: 100, color: Colors.green),
              const SizedBox(height: 24),
              Text('Payment Successful!', style: AppTheme.lightTheme.textTheme.headlineMedium),
              const SizedBox(height: 12),
              const Text('Your digital receipt has been created and your laundry is now being processed.', textAlign: TextAlign.center),
              const SizedBox(height: 40),
              _buildReceiptCard(),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('View Order Status'),
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
      child: const Column(
        children: [
          Text('INFINITY WASH', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Text('Digital Receipt', style: TextStyle(fontSize: 10, letterSpacing: 1.5)),
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text('Order ID'), Text('IW-105', style: TextStyle(fontWeight: FontWeight.bold))],
          ),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text('Amount Paid'), Text('₱350.00', style: TextStyle(fontWeight: FontWeight.bold))],
          ),
        ],
      ),
    );
  }
}
