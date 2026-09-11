import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';

class OrderStatusScreen extends StatefulWidget {
  final LaundryOrder order;
  const OrderStatusScreen({super.key, required this.order});

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen> {
  late OrderStatus _currentStatus;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.order.status;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Order ${widget.order.id}'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildStatusTracker(),
            const SizedBox(height: 40),
            _buildOrderDetails(),
            const SizedBox(height: 40),
            if (_currentStatus == OrderStatus.ready)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Customer has been notified!',
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTracker() {
    return Column(
      children: [
        _buildStatusStep(OrderStatus.processing, 'Processing', Icons.sync),
        _buildConnector(),
        _buildStatusStep(OrderStatus.ready, 'Ready for Pickup', Icons.check_circle_outline),
      ],
    );
  }

  Widget _buildStatusStep(OrderStatus status, String label, IconData icon) {
    bool isDone = _isStatusDone(status);
    bool isCurrent = _currentStatus == status;
    Color color = isDone || isCurrent ? AppTheme.accentBlue : AppTheme.textLight.withValues(alpha: 0.3);

    return Row(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 16),
        Text(
          label,
          style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        const Spacer(),
        if (isDone && !isCurrent)
          const Icon(Icons.check_circle, color: Colors.green),
      ],
    );
  }

  Widget _buildConnector() {
    return Container(
      margin: const EdgeInsets.only(left: 24),
      height: 20,
      width: 2,
      color: AppTheme.borderGray,
    );
  }

  Widget _buildOrderDetails() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow('Customer', widget.order.customerName),
          const Divider(),
          _buildDetailRow('Collection', widget.order.collectionText),
          const Divider(),
          _buildDetailRow('Return', widget.order.returnText),
          const Divider(),
          _buildDetailRow('RFID Tag', widget.order.rfidTag ?? 'Not assigned'),
          const Divider(),
          _buildDetailRow('Instructions', widget.order.instructions ?? 'None'),
        ],
      ),
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

  bool _isStatusDone(OrderStatus status) {
    return _currentStatus.index > status.index;
  }
}
