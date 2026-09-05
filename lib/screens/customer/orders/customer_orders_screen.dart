import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import 'request_service_flow.dart';

class CustomerOrdersScreen extends StatefulWidget {
  const CustomerOrdersScreen({super.key});

  @override
  State<CustomerOrdersScreen> createState() => _CustomerOrdersScreenState();
}

class _CustomerOrdersScreenState extends State<CustomerOrdersScreen> {
  bool _hasActiveOrder = true; // For prototype demonstration

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('My Orders'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: _hasActiveOrder ? _buildActiveOrderView() : _buildNoOrderView(),
    );
  }

  Widget _buildNoOrderView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(40.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  Icon(Icons.shopping_basket_outlined, size: 100, color: AppTheme.textLight.withOpacity(0.2)),
                  const SizedBox(height: 24),
                  Text(
                    'No active orders',
                    style: AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(color: AppTheme.textLight),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your current laundry requests will appear here.',
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(),
                  const SizedBox(height: 40),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RequestServiceFlow()),
                      );
                    },
                    child: const Text('Request Laundry Service'),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveOrderView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: AppStyles.cardDecoration,
            child: Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Order IW-105', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
                    Text('Sept 04, 2026', style: TextStyle(fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 24),
                _buildStatusStep('Processing', Icons.sync, true),
                _buildConnector(true),
                _buildStatusStep('Ready', Icons.check_circle_outline, false),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Text('Order Details', style: AppTheme.lightTheme.textTheme.titleMedium),
          const SizedBox(height: 16),
          _buildDetailRow('Service Type', 'Pick-up and Delivery'),
          _buildDetailRow('Instructions', 'No fabric softener please.'),
          _buildDetailRow('Estimated Total', '₱350.00'),
          const SizedBox(height: 40),
          OutlinedButton(
            onPressed: () => setState(() => _hasActiveOrder = false),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusStep(String label, IconData icon, bool isActive) {
    Color color = isActive ? AppTheme.accentBlue : AppTheme.textLight.withOpacity(0.3);
    return Row(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 16),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            fontSize: 18,
          ),
        ),
        const Spacer(),
        if (isActive) const Icon(Icons.pending, color: AppTheme.accentBlue),
      ],
    );
  }

  Widget _buildConnector(bool isActive) {
    return Container(
      margin: const EdgeInsets.only(left: 24),
      height: 30,
      width: 2,
      color: isActive ? AppTheme.accentBlue : AppTheme.borderGray,
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTheme.lightTheme.textTheme.bodyMedium),
          Text(value, style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontSize: 14)),
        ],
      ),
    );
  }
}
