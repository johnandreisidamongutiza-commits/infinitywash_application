import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import '../../../services/order_service.dart';
import 'check_in_request_screen.dart';

class OrderStatusScreen extends StatefulWidget {
  final LaundryOrder order;
  const OrderStatusScreen({super.key, required this.order});

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen> {
  late OrderStatus _currentStatus;
  late LaundryOrder _currentOrder; // Track current order data
  final OrderService _orderService = OrderService();
  bool _isUpdating = false;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    _currentStatus = _currentOrder.status;
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  /// Start auto-refresh timer (30 seconds for order detail screen)
  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (timer) async {
        if (mounted && !_isUpdating) {
          await _refreshOrderData();
        }
      },
    );
    print('✅ Started order detail auto-refresh timer (30s interval)');
  }

  /// Refresh order data from database
  Future<void> _refreshOrderData() async {
    try {
      final refreshedOrder = await _orderService.getOrderById(_currentOrder.id);
      if (refreshedOrder != null && mounted) {
        setState(() {
          _currentOrder = refreshedOrder;
          _currentStatus = refreshedOrder.status;
        });
        print('🔄 Refreshed order ${_currentOrder.displayNumber} - status: ${_currentStatus.name}');
      }
    } catch (e) {
      print('⚠️ Error refreshing order data: $e');
      // Don't show error to user, just log it
    }
  }

  bool get _needsDelivery {
    return _currentOrder.returnMethod == ReturnMethod.delivery;
  }

  bool get _canMarkReady {
    // Can mark as ready for delivery if processing and needs delivery
    return _currentStatus == OrderStatus.processing && _needsDelivery;
  }

  bool get _canComplete {
    // Can complete directly if:
    // 1. Shop pickup orders that are processing or ready
    // 2. Delivery orders should NOT be completed by staff (rider completes them)
    if (_needsDelivery) {
      return false; // Staff cannot complete delivery orders
    }
    return _currentStatus == OrderStatus.processing ||
           _currentStatus == OrderStatus.ready;
  }

  Future<bool> _showConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Order?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to mark this order as complete?'),
            const SizedBox(height: 16),
            Text(
              'Order: ${_currentOrder.displayNumber}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Customer: ${_currentOrder.customerName}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Complete'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<bool> _showReadyConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ready for Delivery?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mark this order as ready for rider delivery?'),
            const SizedBox(height: 16),
            Text(
              'Order: ${_currentOrder.displayNumber}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Customer: ${_currentOrder.customerName}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accentBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppTheme.accentBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This will notify riders to deliver the order',
                      style: TextStyle(fontSize: 12, color: AppTheme.accentBlue),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Mark Ready'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _markOrderAsComplete() async {
    // Show confirmation dialog
    final confirm = await _showConfirmationDialog();
    if (!confirm) return;

    // Show loading state
    setState(() => _isUpdating = true);

    try {
      // Update order status to completed
      await _orderService.updateOrderStatus(_currentOrder.id, 'completed');

      // Show success message
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order ${_currentOrder.displayNumber} marked as complete ✓'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      // Navigate back with success flag to refresh list
      Navigator.pop(context, true);
    } catch (e) {
      // Handle error
      if (!mounted) return;
      setState(() => _isUpdating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error completing order: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _markOrderAsReady() async {
    // Show confirmation dialog
    final confirm = await _showReadyConfirmationDialog();
    if (!confirm) return;

    // Show loading state
    setState(() => _isUpdating = true);

    try {
      // Update order status to ready for delivery
      await _orderService.updateOrderStatus(_currentOrder.id, 'ready');

      // Show success message
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order ${_currentOrder.displayNumber} marked as ready for delivery ✓'),
          backgroundColor: AppTheme.accentBlue,
          duration: const Duration(seconds: 2),
        ),
      );

      // Navigate back with success flag to refresh list
      Navigator.pop(context, true);
    } catch (e) {
      // Handle error
      if (!mounted) return;
      setState(() => _isUpdating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error marking order as ready: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Order ${_currentOrder.displayNumber}'),
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
            if (_currentOrder.needsCheckIn)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final done = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CheckInRequestScreen(order: _currentOrder),
                      ),
                    );
                    if (done == true && context.mounted) {
                      // Refresh order data before popping
                      await _refreshOrderData();
                      if (context.mounted) {
                        Navigator.pop(context, true);
                      }
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
            if (_canMarkReady && !_currentOrder.needsCheckIn) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isUpdating ? null : _markOrderAsReady,
                  icon: _isUpdating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.local_shipping_outlined, color: Colors.white),
                  label: Text(
                    _isUpdating ? 'Updating...' : 'Mark Ready for Delivery',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    disabledBackgroundColor: Colors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
            if (_canComplete && !_currentOrder.needsCheckIn) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isUpdating ? null : _markOrderAsComplete,
                  icon: _isUpdating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle, color: Colors.white),
                  label: Text(
                    _isUpdating ? 'Completing...' : 'Mark Order as Complete',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    disabledBackgroundColor: Colors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  List<OrderStatus> get _trackerSteps {
    final steps = <OrderStatus>[];
    
    // Add pending_pickup if order was picked up by rider
    if (_currentOrder.collectionMethod == CollectionMethod.riderPickup) {
      steps.add(OrderStatus.pending_pickup);
    }
    
    // Always show processing
    steps.add(OrderStatus.processing);
    
    // For delivery orders, show ready and out_for_delivery steps
    if (_currentOrder.returnMethod == ReturnMethod.delivery) {
      steps.add(OrderStatus.ready);
      steps.add(OrderStatus.out_for_delivery);
    }
    
    // Always end with completed
    steps.add(OrderStatus.completed);
    
    return steps;
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
          else if (steps[i] == OrderStatus.ready)
            _buildStatusStep(OrderStatus.ready, 'Ready for Delivery', Icons.check_circle_outline)
          else if (steps[i] == OrderStatus.out_for_delivery)
            _buildStatusStep(OrderStatus.out_for_delivery, 'Out for Delivery', Icons.local_shipping_outlined)
          else
            _buildStatusStep(OrderStatus.completed, 'Completed', Icons.check_circle),
          if (i < steps.length - 1) _buildConnector(),
        ],
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
        Expanded(
          child: Text(
            label,
            style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
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
          _buildDetailRow('Customer', _currentOrder.customerName),
          const Divider(),
          _buildDetailRow('Collection', _currentOrder.collectionText),
          const Divider(),
          _buildDetailRow('Return', _currentOrder.returnText),
          const Divider(),
          _buildDetailRow(
            'Total Weight',
            _currentOrder.needsCheckIn ? 'Needs check-in' : _currentOrder.weightDisplay,
          ),
          if (_currentOrder.hasMultipleLoads) ...[
            const Divider(),
            _buildDetailRow('Multiple Loads', '${_currentOrder.totalLoads} loads'),
          ],
          const Divider(),
          _buildDetailRow('RFID Tag', _currentOrder.rfidTag ?? 'Not assigned'),
          const Divider(),
          _buildDetailRow('Instructions', _currentOrder.instructions ?? 'None'),
          
          // Load Breakdown Section
          if (_currentOrder.hasMultipleLoads) ...[
            const SizedBox(height: 20),
            const Text(
              'Load Breakdown',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textDark),
            ),
            const SizedBox(height: 12),
            ..._currentOrder.loads.map((load) => _buildLoadItem(load)),
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
    final currentIndex = steps.indexOf(_currentStatus);
    final stepIndex = steps.indexOf(status);
    if (currentIndex < 0 || stepIndex < 0) return false;
    return currentIndex > stepIndex;
  }
}
