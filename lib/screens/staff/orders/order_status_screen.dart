import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import 'check_in_request_screen.dart';

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
        title: Text('Order ${widget.order.displayNumber}'),
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
            if (widget.order.needsCheckIn)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final done = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CheckInRequestScreen(order: widget.order),
                      ),
                    );
                    if (done == true && context.mounted) {
                      Navigator.pop(context, true);
                    }
                  },
                  icon: const Icon(Icons.scale_outlined, color: Colors.white),
                  label: const Text(
                    'Check in laundry',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<OrderStatus> get _trackerSteps {
    return [
      if (_currentStatus == OrderStatus.pending_pickup) OrderStatus.pending_pickup,
      OrderStatus.processing,
      if (widget.order.returnMethod == ReturnMethod.delivery) OrderStatus.out_for_delivery,
      OrderStatus.completed,
    ];
  }

  OrderStatus get _trackerStatus {
    if (_currentStatus == OrderStatus.ready) return OrderStatus.processing;
    return _currentStatus;
  }

  Widget _buildStatusTracker() {
    final steps = _trackerSteps;

    return Column(
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          if (steps[i] == OrderStatus.pending_pickup)
            _buildStatusStep(OrderStatus.pending_pickup, 'Waiting for Rider Pickup', Icons.two_wheeler)
          else if (steps[i] == OrderStatus.processing)
            _buildStatusStep(OrderStatus.processing, 'Processing', Icons.sync)
          else if (steps[i] == OrderStatus.out_for_delivery)
            _buildStatusStep(OrderStatus.out_for_delivery, 'Out for Delivery', Icons.local_shipping_outlined)
          else
            _buildStatusStep(OrderStatus.completed, 'Completed', Icons.check_circle_outline),
          if (i < steps.length - 1) _buildConnector(),
        ],
      ],
    );
  }

  Widget _buildStatusStep(OrderStatus status, String label, IconData icon) {
    bool isDone = _isStatusDone(status);
    bool isCurrent = _trackerStatus == status;
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
          _buildDetailRow(
            'Total Weight',
            widget.order.needsCheckIn ? 'Needs check-in' : widget.order.weightDisplay,
          ),
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
    final steps = _trackerSteps;
    final currentIndex = steps.indexOf(_trackerStatus);
    final stepIndex = steps.indexOf(status);
    if (currentIndex < 0 || stepIndex < 0) return false;
    return currentIndex > stepIndex;
  }
}
