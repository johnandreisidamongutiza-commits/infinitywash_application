import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import 'create_order_flow.dart';
import 'order_status_screen.dart';
import 'order_history_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  // Mock data
  final List<LaundryOrder> _orders = [
    LaundryOrder(
      id: 'IW-001',
      customerName: 'John Doe',
      type: OrderType.walkIn,
      status: OrderStatus.washing,
      paymentStatus: PaymentStatus.unpaid,
      weight: 5.5,
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
    ),
    LaundryOrder(
      id: 'IW-002',
      customerName: 'Sarah Smith',
      type: OrderType.pickUpAndDelivery,
      status: OrderStatus.ready,
      paymentStatus: PaymentStatus.paid,
      weight: 3.2,
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Orders'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const OrderHistoryScreen()),
              );
            },
            icon: const Icon(Icons.history, color: AppTheme.accentBlue),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: _orders.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) => _buildOrderCard(_orders[index]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateOrderFlow()),
          );
        },
        backgroundColor: AppTheme.accentBlue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildOrderCard(LaundryOrder order) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => OrderStatusScreen(order: order)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: AppStyles.cardDecoration,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(order.id, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
                _buildStatusBadge(order.status),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 20, color: AppTheme.textLight),
                const SizedBox(width: 8),
                Text(order.customerName, style: AppTheme.lightTheme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${order.weight} kg', style: AppTheme.lightTheme.textTheme.bodyMedium),
                Text(
                  order.paymentStatus == PaymentStatus.paid ? 'PAID' : 'UNPAID',
                  style: TextStyle(
                    color: order.paymentStatus == PaymentStatus.paid ? Colors.green : AppTheme.errorRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(OrderStatus status) {
    Color color;
    switch (status) {
      case OrderStatus.washing: color = Colors.blue; break;
      case OrderStatus.drying: color = Colors.orange; break;
      case OrderStatus.folding: color = Colors.purple; break;
      case OrderStatus.ready: color = AppTheme.errorRed; break;
      case OrderStatus.completed: color = Colors.green; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
