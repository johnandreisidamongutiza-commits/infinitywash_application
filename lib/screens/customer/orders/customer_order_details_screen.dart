import 'package:flutter/material.dart';
import '../../../models/order.dart';

/// Customer Order Details Screen
/// Shows detailed information about a specific order
class CustomerOrderDetailsScreen extends StatelessWidget {
  final LaundryOrder order;

  const CustomerOrderDetailsScreen({
    super.key,
    required this.order,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Details'),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order Number
            Card(
              child: ListTile(
                leading: const Icon(Icons.receipt_long),
                title: const Text('Order Number'),
                subtitle: Text(order.orderNumber ?? order.id),
              ),
            ),
            const SizedBox(height: 8),

            // Status
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.circle,
                  color: _getStatusColor(order.status),
                ),
                title: const Text('Status'),
                subtitle: Text(
                  order.status.name.toUpperCase().replaceAll('_', ' '),
                  style: TextStyle(
                    color: _getStatusColor(order.status),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Total Amount
            Card(
              child: ListTile(
                leading: const Icon(Icons.attach_money),
                title: const Text('Total Amount'),
                subtitle: Text(
                  '₱${(order.totalAmount ?? 0.0).toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Created At
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Order Date'),
                subtitle: Text(
                  order.createdAt.toLocal().toString().split('.')[0],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Track Order Button
            if (order.status == OrderStatus.processing || 
                order.status == OrderStatus.out_for_delivery)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // TODO: Navigate to tracking screen
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Tracking feature coming soon!'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.location_on),
                  label: const Text('Track Order'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_approval:
      case OrderStatus.pending_pickup:
        return Colors.orange;
      case OrderStatus.processing:
      case OrderStatus.out_for_delivery:
        return Colors.blue;
      case OrderStatus.ready:
        return Colors.green;
      case OrderStatus.completed:
        return Colors.green;
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
