import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';

class OrderHistoryScreen extends StatelessWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Mock data for history
    final List<LaundryOrder> history = [
      LaundryOrder(
        id: 'IW-999',
        customerName: 'Jane Smith',
        type: OrderType.walkIn,
        status: OrderStatus.completed,
        paymentStatus: PaymentStatus.paid,
        weight: 4.0,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      LaundryOrder(
        id: 'IW-998',
        customerName: 'Bob Brown',
        type: OrderType.pickUpAndDelivery,
        status: OrderStatus.completed,
        paymentStatus: PaymentStatus.paid,
        weight: 7.2,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Past Orders'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: history.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final order = history[index];
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: AppStyles.cardDecoration,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.check, color: Colors.green),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.customerName, style: AppTheme.lightTheme.textTheme.titleMedium),
                      Text('Order ${order.id} • ${order.weight} kg', style: AppTheme.lightTheme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                Text(
                  '₱${(order.weight * 50).toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
