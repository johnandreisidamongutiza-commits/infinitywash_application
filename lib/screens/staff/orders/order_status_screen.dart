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
            if (_currentStatus != OrderStatus.completed)
              ElevatedButton(
                onPressed: _advanceStatus,
                child: Text(_getNextButtonText()),
              ),
            if (_currentStatus == OrderStatus.ready)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  'Customer has been notified!',
                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
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
        _buildStatusStep(OrderStatus.washing, 'Washing', Icons.water_drop_outlined),
        _buildConnector(),
        _buildStatusStep(OrderStatus.drying, 'Drying', Icons.air_outlined),
        _buildConnector(),
        _buildStatusStep(OrderStatus.folding, 'Folding', Icons.layers_outlined),
        _buildConnector(),
        _buildStatusStep(OrderStatus.ready, 'Ready', Icons.shopping_basket_outlined),
      ],
    );
  }

  Widget _buildStatusStep(OrderStatus status, String label, IconData icon) {
    bool isDone = _isStatusDone(status);
    bool isCurrent = _currentStatus == status;
    Color color = isDone || isCurrent ? AppTheme.accentBlue : AppTheme.textLight.withOpacity(0.3);

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
          _buildDetailRow('Weight', '${widget.order.weight} kg'),
          const Divider(),
          _buildDetailRow('Type', widget.order.type == OrderType.walkIn ? 'Walk-in' : 'Pick-up'),
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

  void _advanceStatus() {
    setState(() {
      if (_currentStatus.index < OrderStatus.completed.index) {
        _currentStatus = OrderStatus.values[_currentStatus.index + 1];
      }
    });
  }

  String _getNextButtonText() {
    switch (_currentStatus) {
      case OrderStatus.washing: return 'Start Drying';
      case OrderStatus.drying: return 'Start Folding';
      case OrderStatus.folding: return 'Mark as Ready';
      case OrderStatus.ready: return 'Complete Order';
      case OrderStatus.completed: return 'Completed';
    }
  }
}
