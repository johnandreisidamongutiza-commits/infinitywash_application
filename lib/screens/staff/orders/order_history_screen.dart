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
        channel: OrderChannel.walkIn,
        status: OrderStatus.completed,
        paymentStatus: PaymentStatus.paid,
        loads: [
          OrderLoad(
            loadNumber: 1,
            category: 'Regular Clothing',
            weight: 4.0,
            categoryLimit: 8.0,
            unit: 'kg',
            description: 'T-shirts, shorts, sleeveless, socks, underwear',
            isOverLimit: false,
            loadStatus: LoadStatus.folded,
          ),
        ],
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      LaundryOrder(
        id: 'IW-998',
        customerName: 'Bob Brown',
        channel: OrderChannel.online,
        collectionMethod: CollectionMethod.riderPickup,
        returnMethod: ReturnMethod.delivery,
        status: OrderStatus.completed,
        paymentStatus: PaymentStatus.paid,
        loads: [
          OrderLoad(
            loadNumber: 1,
            category: 'Heavy Clothing',
            weight: 7.2,
            categoryLimit: 6.0,
            unit: 'kg',
            description: 'Jeans, cargo, jackets, sweaters, corduroy',
            isOverLimit: true,
            loadStatus: LoadStatus.folded,
          ),
        ],
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
                  decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.check, color: Colors.green),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.customerName, style: AppTheme.lightTheme.textTheme.titleMedium),
                      Text('Order ${order.id} • ${order.weightDisplay}', style: AppTheme.lightTheme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                Text(
                  '₱${order.basePrice.toStringAsFixed(0)}',
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
