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
    final isDelivery = widget.order.returnMethod == ReturnMethod.delivery;
    final isCurrentlyPendingPickup = _currentStatus == OrderStatus.pending_pickup;

    return Column(
      children: [
        if (isCurrentlyPendingPickup) ...[
          _buildStatusStep(OrderStatus.pending_pickup, 'Waiting for Rider Pickup', Icons.two_wheeler),
          _buildConnector(),
        ],
        _buildStatusStep(OrderStatus.processing, 'Processing', Icons.sync),
        _buildConnector(),
        _buildStatusStep(
          OrderStatus.ready,
          isDelivery ? 'Ready for Delivery' : 'Ready for Pickup',
          Icons.inventory_2_outlined,
        ),
        if (isDelivery) ...[
          _buildConnector(),
          _buildStatusStep(OrderStatus.out_for_delivery, 'Out for Delivery', Icons.local_shipping_outlined),
        ],
        _buildConnector(),
        _buildStatusStep(OrderStatus.completed, 'Completed', Icons.check_circle_outline),
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
          _buildDetailRow('Total Weight', widget.order.weightDisplay),
          if (widget.order.hasMultipleLoads) ...[
            const Divider(),
            _buildDetailRow('Multiple Loads', '${widget.order.totalLoads} loads'),
          ],
          const Divider(),
          _buildDetailRow('RFID Tag', widget.order.rfidTag ?? 'Not assigned'),
          const Divider(),
          _buildDetailRow('Instructions', widget.order.instructions ?? 'None'),
          
          // Load Breakdown Section
          if (widget.order.hasMultipleLoads) ...[
            const SizedBox(height: 20),
            const Text(
              'Load Breakdown',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textDark),
            ),
            const SizedBox(height: 12),
            ...widget.order.loads.map((load) => _buildLoadItem(load)),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadItem(OrderLoad load) {
    final Color statusColor = _getLoadStatusColor(load.loadStatus);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.softGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                load.statusIcon,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Load ${load.loadNumber}: ${load.category}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        load.statusText,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${load.weight.toStringAsFixed(1)} ${load.unit}',
                      style: TextStyle(fontSize: 12, color: load.isOverLimit ? Colors.orange : AppTheme.textLight),
                    ),
                    if (load.isOverLimit) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'OVER LIMIT',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange),
                        ),
                      ),
                    ],
                  ],
                ),
                if (load.notes != null && load.notes!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    load.notes!,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textLight, fontStyle: FontStyle.italic),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getLoadStatusColor(LoadStatus? status) {
    if (status == null) return Colors.grey;
    switch (status) {
      case LoadStatus.queued:
        return Colors.grey;
      case LoadStatus.washing:
        return AppTheme.accentBlue;
      case LoadStatus.drying:
        return Colors.orange;
      case LoadStatus.folded:
        return Colors.green;
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTheme.lightTheme.textTheme.bodyMedium),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  bool _isStatusDone(OrderStatus status) {
    return _currentStatus.index > status.index;
  }
}
