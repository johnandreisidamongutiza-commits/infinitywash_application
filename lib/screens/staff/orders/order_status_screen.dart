import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_error.dart';
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
  late LaundryOrder _currentOrder;
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

  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (timer) async {
        if (mounted && !_isUpdating) {
          await _refreshOrderData();
        }
      },
    );
  }

  Future<void> _refreshOrderData() async {
    try {
      final refreshedOrder = await _orderService.getOrderById(_currentOrder.id);
      if (refreshedOrder != null && mounted) {
        setState(() {
          _currentOrder = refreshedOrder;
          _currentStatus = refreshedOrder.status;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing order data: $e');
    }
  }

  bool get _needsDelivery => _currentOrder.returnMethod == ReturnMethod.delivery;

  bool get _canMarkReady => _currentStatus == OrderStatus.processing && _needsDelivery;

  bool get _canComplete {
    if (_needsDelivery) return false;
    return _currentStatus == OrderStatus.processing || _currentStatus == OrderStatus.ready;
  }

  bool get _isPendingPickup => _currentStatus == OrderStatus.pending_pickup;
  bool get _isOutForDelivery => _currentStatus == OrderStatus.out_for_delivery;

  // ───────────────────────────────────────────────────────────────────────────
  // Parsing Helpers for clean metadata separation
  // ─────────────────────────────────────────────────────────────────────────
  String? _getDisplayAddress() {
    if (_currentOrder.deliveryAddress != null && _currentOrder.deliveryAddress!.trim().isNotEmpty) {
      return _currentOrder.deliveryAddress!.trim();
    }
    final instr = _currentOrder.instructions ?? '';
    final match = RegExp(r'(?:Pickup Address|Delivery Address|Address):\s*([^(\n|]+)', caseSensitive: false).firstMatch(instr);
    if (match != null) {
      return match.group(1)?.trim();
    }
    return null;
  }

  String? _getDisplayLandmark() {
    if (_currentOrder.deliveryLandmark != null && _currentOrder.deliveryLandmark!.trim().isNotEmpty) {
      return _currentOrder.deliveryLandmark!.trim();
    }
    final instr = _currentOrder.instructions ?? '';
    final match = RegExp(r'Landmark:\s*([^|\n)]+)', caseSensitive: false).firstMatch(instr);
    if (match != null) {
      return match.group(1)?.trim();
    }
    return null;
  }

  String? _getDisplayPaymentPreference() {
    if (_currentOrder.paymentPreference != null && _currentOrder.paymentPreference!.trim().isNotEmpty) {
      return _currentOrder.paymentPreference!.trim();
    }
    final instr = _currentOrder.instructions ?? '';
    final match = RegExp(r'Payment:\s*([^|\n)]+)', caseSensitive: false).firstMatch(instr);
    if (match != null) {
      return match.group(1)?.trim();
    }
    return _currentOrder.paymentMethod;
  }

  String? _getCleanInstructions() {
    final instr = _currentOrder.instructions;
    if (instr == null || instr.trim().isEmpty) return null;
    final cleaned = instr
        .replaceAll(RegExp(r'(?:Pickup Address|Delivery Address|Address):\s*[^(\n|]+', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(?Landmark:[^|\n)]+\)?', caseSensitive: false), '')
        .replaceAll(RegExp(r'\|?\s*Payment:[^|\n)]+\)?', caseSensitive: false), '')
        .replaceAll(RegExp(r'[()|]'), '')
        .trim();
    return cleaned.isNotEmpty ? cleaned : null;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Action Handlers
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> _showConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Complete Order?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to mark this order as completed and released?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order: ${_currentOrder.displayNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Customer: ${_currentOrder.customerName}', style: const TextStyle(fontWeight: FontWeight.w500)),
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
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Complete & Release'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<bool> _showReadyConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ready for Delivery?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mark this order as packed and ready for rider dispatch?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order: ${_currentOrder.displayNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Customer: ${_currentOrder.customerName}'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.accentBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppTheme.accentBlue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Riders will be notified to pick up this package for delivery.',
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Mark Ready'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _markOrderAsComplete() async {
    final confirm = await _showConfirmationDialog();
    if (!confirm) return;

    setState(() => _isUpdating = true);
    try {
      await _orderService.updateOrderStatus(_currentOrder.id, 'completed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order ${_currentOrder.displayNumber} marked as complete ✓'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapErrorToMessage(e)),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _markOrderAsReady() async {
    final confirm = await _showReadyConfirmationDialog();
    if (!confirm) return;

    setState(() => _isUpdating = true);
    try {
      await _orderService.updateOrderStatus(_currentOrder.id, 'ready');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order ${_currentOrder.displayNumber} marked as ready for delivery ✓'),
          backgroundColor: AppTheme.accentBlue,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapErrorToMessage(e)),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<bool> _showForceCompletePickupDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 26),
            SizedBox(width: 8),
            Text('Complete Pickup Manually?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The rider hasn\'t marked this pickup as complete in the app.',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Only proceed if the laundry is physically at the shop.',
                      style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600),
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
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Complete Pickup'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _forceCompletePickup() async {
    final confirm = await _showForceCompletePickupDialog();
    if (!confirm) return;

    setState(() => _isUpdating = true);
    try {
      await _orderService.staffCompletePickup(
        orderId: _currentOrder.id,
        staffId: 'current_staff_id',
        notes: 'Pickup manually completed by staff (rider did not mark complete)',
      );
      await _refreshOrderData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Pickup completed. You can now check in the laundry.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _isUpdating = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapErrorToMessage(e)),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<bool> _showForceCompleteDeliveryDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.purple, size: 26),
            SizedBox(width: 8),
            Text('Complete Delivery Manually?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The rider hasn\'t marked this delivery as complete.',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Only proceed if the customer has confirmed receipt of laundry.',
                      style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600),
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
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Complete Delivery'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _forceCompleteDelivery() async {
    final confirm = await _showForceCompleteDeliveryDialog();
    if (!confirm) return;

    setState(() => _isUpdating = true);
    try {
      await _orderService.staffCompleteDelivery(
        orderId: _currentOrder.id,
        staffId: 'current_staff_id',
        notes: 'Delivery manually completed by staff (rider did not mark complete)',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Delivery completed. Order is now complete.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapErrorToMessage(e)),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Horizontal Stepper Calculations
  // ─────────────────────────────────────────────────────────────────────────
  List<_HorizontalStep> _calculateSteps() {
    final channel = _currentOrder.channel;
    final collection = _currentOrder.collectionMethod;
    final returnM = _currentOrder.returnMethod;
    final status = _currentStatus;
    final needsCheckIn = _currentOrder.needsCheckIn;
    final isDone = status == OrderStatus.completed;

    final steps = <_HorizontalStep>[];

    // Case 1: Walk-in + Shop Pickup
    if (channel == OrderChannel.walkIn && collection == CollectionMethod.dropOff && returnM == ReturnMethod.shopPickup) {
      steps.add(_HorizontalStep(
        label: 'Placed',
        icon: Icons.storefront_outlined,
        isCompleted: true,
        isActive: false,
      ));
      steps.add(_HorizontalStep(
        label: 'Washing',
        icon: Icons.local_laundry_service_outlined,
        isCompleted: status == OrderStatus.ready || isDone,
        isActive: status == OrderStatus.processing,
      ));
      steps.add(_HorizontalStep(
        label: 'Ready',
        icon: Icons.shopping_bag_outlined,
        isCompleted: isDone,
        isActive: status == OrderStatus.ready,
      ));
      steps.add(_HorizontalStep(
        label: 'Done',
        icon: Icons.check_circle_outline,
        isCompleted: isDone,
        isActive: isDone,
      ));
    }
    // Case 2: Walk-in + Home Delivery
    else if (channel == OrderChannel.walkIn && collection == CollectionMethod.dropOff && returnM == ReturnMethod.delivery) {
      steps.add(_HorizontalStep(
        label: 'Placed',
        icon: Icons.storefront_outlined,
        isCompleted: true,
        isActive: false,
      ));
      steps.add(_HorizontalStep(
        label: 'Washing',
        icon: Icons.local_laundry_service_outlined,
        isCompleted: status == OrderStatus.ready || status == OrderStatus.out_for_delivery || isDone,
        isActive: status == OrderStatus.processing,
      ));
      steps.add(_HorizontalStep(
        label: 'Ready',
        icon: Icons.inventory_2_outlined,
        isCompleted: status == OrderStatus.out_for_delivery || isDone,
        isActive: status == OrderStatus.ready,
      ));
      steps.add(_HorizontalStep(
        label: 'Transit',
        icon: Icons.local_shipping_outlined,
        isCompleted: isDone,
        isActive: status == OrderStatus.out_for_delivery,
      ));
      steps.add(_HorizontalStep(
        label: 'Done',
        icon: Icons.check_circle_outline,
        isCompleted: isDone,
        isActive: isDone,
      ));
    }
    // Case 3 & 4: Online with Rider Pickup (Shop Pickup or Delivery)
    else if (collection == CollectionMethod.riderPickup) {
      steps.add(_HorizontalStep(
        label: 'Pickup',
        icon: Icons.two_wheeler_outlined,
        isCompleted: status != OrderStatus.pending_pickup && status != OrderStatus.pending_approval,
        isActive: status == OrderStatus.pending_pickup,
      ));
      steps.add(_HorizontalStep(
        label: 'Check-in',
        icon: Icons.scale_outlined,
        isCompleted: !needsCheckIn && status != OrderStatus.pending_pickup,
        isActive: needsCheckIn && status == OrderStatus.processing,
      ));
      steps.add(_HorizontalStep(
        label: 'Washing',
        icon: Icons.local_laundry_service_outlined,
        isCompleted: (!needsCheckIn && (status == OrderStatus.ready || status == OrderStatus.out_for_delivery || isDone)),
        isActive: !needsCheckIn && status == OrderStatus.processing,
      ));
      if (returnM == ReturnMethod.delivery) {
        steps.add(_HorizontalStep(
          label: 'Ready',
          icon: Icons.inventory_2_outlined,
          isCompleted: status == OrderStatus.out_for_delivery || isDone,
          isActive: status == OrderStatus.ready,
        ));
        steps.add(_HorizontalStep(
          label: 'Transit',
          icon: Icons.local_shipping_outlined,
          isCompleted: isDone,
          isActive: status == OrderStatus.out_for_delivery,
        ));
      } else {
        steps.add(_HorizontalStep(
          label: 'Ready',
          icon: Icons.shopping_bag_outlined,
          isCompleted: isDone,
          isActive: status == OrderStatus.ready,
        ));
      }
      steps.add(_HorizontalStep(
        label: 'Done',
        icon: Icons.check_circle_outline,
        isCompleted: isDone,
        isActive: isDone,
      ));
    }
    // Case 5 & 6: Online with Drop-off (Delivery or Shop Pickup)
    else {
      steps.add(_HorizontalStep(
        label: 'Drop-off',
        icon: Icons.storefront_outlined,
        isCompleted: !needsCheckIn,
        isActive: needsCheckIn,
      ));
      steps.add(_HorizontalStep(
        label: 'Check-in',
        icon: Icons.scale_outlined,
        isCompleted: !needsCheckIn,
        isActive: needsCheckIn,
      ));
      steps.add(_HorizontalStep(
        label: 'Washing',
        icon: Icons.local_laundry_service_outlined,
        isCompleted: (!needsCheckIn && (status == OrderStatus.ready || status == OrderStatus.out_for_delivery || isDone)),
        isActive: !needsCheckIn && status == OrderStatus.processing,
      ));
      if (returnM == ReturnMethod.delivery) {
        steps.add(_HorizontalStep(
          label: 'Ready',
          icon: Icons.inventory_2_outlined,
          isCompleted: status == OrderStatus.out_for_delivery || isDone,
          isActive: status == OrderStatus.ready,
        ));
        steps.add(_HorizontalStep(
          label: 'Transit',
          icon: Icons.local_shipping_outlined,
          isCompleted: isDone,
          isActive: status == OrderStatus.out_for_delivery,
        ));
      } else {
        steps.add(_HorizontalStep(
          label: 'Ready',
          icon: Icons.shopping_bag_outlined,
          isCompleted: isDone,
          isActive: status == OrderStatus.ready,
        ));
      }
      steps.add(_HorizontalStep(
        label: 'Done',
        icon: Icons.check_circle_outline,
        isCompleted: isDone,
        isActive: isDone,
      ));
    }

    return steps;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Order ${_currentOrder.displayNumber}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.textDark),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, size: 19, color: AppTheme.accentBlue),
            tooltip: 'Copy Order Number',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _currentOrder.displayNumber));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Order number copied to clipboard ✓'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 22, color: AppTheme.textDark),
            tooltip: 'Refresh',
            onPressed: _refreshOrderData,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTagsRow(),
                  const SizedBox(height: 12),
                  _buildHorizontalStepperCard(),
                  const SizedBox(height: 14),
                  _buildPhaseStatusBanner(),
                  const SizedBox(height: 14),
                  _buildCustomerCard(),
                  if (_currentOrder.collectionMethod == CollectionMethod.riderPickup ||
                      _currentOrder.returnMethod == ReturnMethod.delivery ||
                      _getDisplayAddress() != null) ...[
                    const SizedBox(height: 14),
                    _buildLogisticsCard(),
                  ],
                  const SizedBox(height: 14),
                  _buildPaymentCard(),
                  const SizedBox(height: 14),
                  _buildLaundrySpecsCard(),
                  const SizedBox(height: 80), // extra padding for bottom bar
                ],
              ),
            ),
          ),
          _buildStickyBottomBar(),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // UI Sub-components
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTagsRow() {
    final isWalkIn = _currentOrder.channel == OrderChannel.walkIn;
    final isRiderPickup = _currentOrder.collectionMethod == CollectionMethod.riderPickup;
    final isDelivery = _currentOrder.returnMethod == ReturnMethod.delivery;
    final isPaid = _currentOrder.paymentStatus == PaymentStatus.paid;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildTag(
            icon: isWalkIn ? Icons.storefront : Icons.phone_android,
            label: isWalkIn ? 'Walk-in' : 'Online Booking',
            color: Colors.blue.shade700,
            bgColor: Colors.blue.shade50,
          ),
          const SizedBox(width: 8),
          _buildTag(
            icon: isRiderPickup ? Icons.two_wheeler : Icons.input,
            label: isRiderPickup ? 'Rider Pickup' : 'Drop-off',
            color: isRiderPickup ? Colors.purple.shade700 : Colors.teal.shade700,
            bgColor: isRiderPickup ? Colors.purple.shade50 : Colors.teal.shade50,
          ),
          const SizedBox(width: 8),
          _buildTag(
            icon: isDelivery ? Icons.local_shipping : Icons.shopping_bag_outlined,
            label: isDelivery ? 'Home Delivery' : 'Shop Pickup',
            color: isDelivery ? Colors.indigo.shade700 : Colors.amber.shade900,
            bgColor: isDelivery ? Colors.indigo.shade50 : Colors.amber.shade50,
          ),
          const SizedBox(width: 8),
          _buildTag(
            icon: isPaid ? Icons.check_circle : Icons.schedule,
            label: isPaid ? 'Paid' : 'Unpaid',
            color: isPaid ? Colors.green.shade700 : Colors.orange.shade800,
            bgColor: isPaid ? Colors.green.shade50 : Colors.orange.shade50,
          ),
        ],
      ),
    );
  }

  Widget _buildTag({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalStepperCard() {
    final steps = _calculateSteps();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: const Color(0xFFEDF2F7)),
      ),
      child: Row(
        children: List.generate(steps.length, (index) {
          final step = steps[index];
          final isLast = index == steps.length - 1;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Node circle
                      _buildStepNode(step),
                      const SizedBox(height: 6),
                      // Step text label
                      Text(
                        step.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: step.isActive
                              ? FontWeight.bold
                              : (step.isCompleted ? FontWeight.w600 : FontWeight.normal),
                          color: step.isActive
                              ? AppTheme.accentBlue
                              : (step.isCompleted ? const Color(0xFF334155) : const Color(0xFF94A3B8)),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 14,
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 18),
                    color: (steps[index + 1].isCompleted || steps[index + 1].isActive)
                        ? AppTheme.accentBlue
                        : const Color(0xFFE2E8F0),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepNode(_HorizontalStep step) {
    if (step.isActive) {
      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.accentBlue, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accentBlue.withValues(alpha: 0.28),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Icon(step.icon, size: 18, color: AppTheme.accentBlue),
        ),
      );
    } else if (step.isCompleted) {
      return Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: AppTheme.accentBlue,
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Icon(Icons.check, size: 16, color: Colors.white),
        ),
      );
    } else {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        ),
        child: Center(
          child: Icon(step.icon, size: 15, color: const Color(0xFF94A3B8)),
        ),
      );
    }
  }

  Widget _buildPhaseStatusBanner() {
    IconData icon;
    Color color;
    Color bgColor;
    String title;
    String subtitle;

    if (_currentOrder.needsCheckIn) {
      icon = Icons.scale_outlined;
      color = const Color(0xFF0284C7);
      bgColor = const Color(0xFFF0F9FF);
      title = 'Check-In & Weighing Required';
      subtitle = 'Laundry has arrived at the shop. Please weigh and assign RFID tags.';
    } else if (_isPendingPickup) {
      icon = Icons.two_wheeler;
      color = Colors.orange.shade800;
      bgColor = Colors.orange.shade50;
      title = 'Waiting for Rider Pickup';
      subtitle = 'Rider has been dispatched to collect the laundry from customer.';
    } else if (_currentStatus == OrderStatus.processing) {
      icon = Icons.local_laundry_service;
      color = AppTheme.accentBlue;
      bgColor = const Color(0xFFEFF6FF);
      title = 'Processing: Washing & Drying';
      subtitle = 'Clothes are being processed in-store by laundry staff.';
    } else if (_currentStatus == OrderStatus.ready) {
      if (_needsDelivery) {
        icon = Icons.inventory_2_outlined;
        color = Colors.indigo.shade700;
        bgColor = Colors.indigo.shade50;
        title = 'Ready for Rider Delivery';
        subtitle = 'Laundry is packed and ready to be picked up by delivery rider.';
      } else {
        icon = Icons.shopping_bag_outlined;
        color = Colors.amber.shade900;
        bgColor = Colors.amber.shade50;
        title = 'Ready for Customer Pickup';
        subtitle = 'Laundry is ready on the shelf waiting for customer claim at counter.';
      }
    } else if (_isOutForDelivery) {
      icon = Icons.local_shipping_outlined;
      color = Colors.purple.shade700;
      bgColor = Colors.purple.shade50;
      title = 'Out for Delivery';
      subtitle = 'Rider is on the way to deliver the cleaned laundry to customer.';
    } else if (_currentStatus == OrderStatus.completed) {
      icon = Icons.check_circle_outline;
      color = Colors.green.shade700;
      bgColor = Colors.green.shade50;
      title = 'Order Completed';
      subtitle = 'Laundry was claimed/delivered and payment has been verified.';
    } else {
      icon = Icons.info_outline;
      color = Colors.grey.shade700;
      bgColor = Colors.grey.shade100;
      title = _currentOrder.statusText;
      subtitle = 'Order status updated.';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: color.withValues(alpha: 0.85),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard() {
    final phone = _currentOrder.customerPhone;
    final initial = _currentOrder.customerName.trim().isNotEmpty
        ? _currentOrder.customerName.trim().substring(0, 1).toUpperCase()
        : 'C';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardBoxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Customer Information',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.accentBlue.withValues(alpha: 0.12),
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accentBlue,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentOrder.customerName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (phone != null && phone.isNotEmpty) ? phone : 'No phone number provided',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              if (phone != null && phone.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.copy, size: 18, color: AppTheme.accentBlue),
                  tooltip: 'Copy Phone',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: phone));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Phone number copied ✓'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogisticsCard() {
    final address = _getDisplayAddress();
    final landmark = _getDisplayLandmark();
    final instructions = _getCleanInstructions();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardBoxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping_outlined, size: 17, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              Text(
                _currentOrder.returnMethod == ReturnMethod.delivery ? 'Delivery Logistics' : 'Pickup Logistics',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (address != null && address.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined, size: 20, color: Colors.redAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Service Address',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        address,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (landmark != null && landmark.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300, width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag_outlined, size: 15, color: Colors.amber.shade900),
                  const SizedBox(width: 6),
                  Text(
                    'Landmark: $landmark',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (instructions != null && instructions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notes, size: 15, color: Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      instructions,
                      style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentCard() {
    final isPaid = _currentOrder.paymentStatus == PaymentStatus.paid;
    final total = _currentOrder.totalAmount ?? _currentOrder.basePrice;
    final preference = _getDisplayPaymentPreference() ?? 'Cash';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardBoxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Payment & Billing',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: isPaid ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isPaid ? Colors.green.shade300 : Colors.orange.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPaid ? Icons.check_circle : Icons.schedule,
                      size: 13,
                      color: isPaid ? Colors.green.shade700 : Colors.orange.shade800,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isPaid ? 'PAID' : 'UNPAID',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isPaid ? Colors.green.shade700 : Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '₱${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  preference,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLaundrySpecsCard() {
    final weightStr = _currentOrder.needsCheckIn ? 'Needs Check-in' : _currentOrder.weightDisplay;
    final loadsCount = _currentOrder.totalLoads;
    final rfid = _currentOrder.rfidTag;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardBoxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Laundry Specifications',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSpecStat(
                  icon: Icons.scale_outlined,
                  label: 'Total Weight',
                  value: weightStr,
                  color: AppTheme.accentBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSpecStat(
                  icon: Icons.layers_outlined,
                  label: 'Total Loads',
                  value: loadsCount > 0 ? '$loadsCount loads' : 'Pending',
                  color: Colors.purple.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.nfc, size: 17, color: Color(0xFF64748B)),
                const SizedBox(width: 8),
                const Text(
                  'RFID Tag:',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    (rfid != null && rfid.isNotEmpty) ? rfid : 'Not Assigned',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: (rfid != null && rfid.isNotEmpty) ? AppTheme.textDark : Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_currentOrder.loads.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Load Breakdown',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
            ),
            const SizedBox(height: 10),
            ..._currentOrder.loads.map((load) => _buildLoadCard(load)),
          ],
          if (_currentStatus != OrderStatus.completed &&
              _currentStatus != OrderStatus.cancelled &&
              _currentOrder.laundryPhotoUrls != null &&
              _currentOrder.laundryPhotoUrls!.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Customer Laundry Photos',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 75,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _currentOrder.laundryPhotoUrls!.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final url = _currentOrder.laundryPhotoUrls![index];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      url,
                      width: 75,
                      height: 75,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 75,
                        height: 75,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image, size: 24, color: Colors.grey),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpecStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadCard(OrderLoad load) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.accentBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '${load.loadNumber}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  load.category,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                ),
                const SizedBox(height: 2),
                Text(
                  '${load.weight.toStringAsFixed(1)} ${load.unit}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          if (load.isOverLimit)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'OVER LIMIT',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange.shade900),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStickyBottomBar() {
    Widget actionButton;

    if (_currentOrder.needsCheckIn) {
      actionButton = ElevatedButton.icon(
        onPressed: () async {
          final done = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => CheckInRequestScreen(order: _currentOrder),
            ),
          );
          if (done == true && mounted) {
            await _refreshOrderData();
            if (mounted) Navigator.pop(context, true);
          }
        },
        icon: const Icon(Icons.scale_outlined, color: Colors.white, size: 20),
        label: const Text(
          'Check In & Weigh Laundry',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accentBlue,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      );
    } else if (_canMarkReady) {
      actionButton = ElevatedButton.icon(
        onPressed: _isUpdating ? null : _markOrderAsReady,
        icon: _isUpdating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.local_shipping_outlined, color: Colors.white, size: 20),
        label: Text(
          _isUpdating ? 'Updating...' : 'Mark Ready for Delivery',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accentBlue,
          disabledBackgroundColor: Colors.grey,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      );
    } else if (_canComplete) {
      actionButton = ElevatedButton.icon(
        onPressed: _isUpdating ? null : _markOrderAsComplete,
        icon: _isUpdating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.check_circle, color: Colors.white, size: 20),
        label: Text(
          _isUpdating ? 'Completing...' : 'Mark Order as Complete',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          disabledBackgroundColor: Colors.grey,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      );
    } else if (_isPendingPickup) {
      actionButton = OutlinedButton.icon(
        onPressed: _isUpdating ? null : _forceCompletePickup,
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
        label: Text(
          _isUpdating ? 'Completing...' : 'Force Complete Pickup (Staff Override)',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.orange),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.orange, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 13),
        ),
      );
    } else if (_isOutForDelivery) {
      actionButton = OutlinedButton.icon(
        onPressed: _isUpdating ? null : _forceCompleteDelivery,
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.purple, size: 18),
        label: Text(
          _isUpdating ? 'Completing...' : 'Force Complete Delivery (Staff Override)',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.purple),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.purple, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 13),
        ),
      );
    } else {
      actionButton = Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade300),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
            const SizedBox(width: 8),
            Text(
              'Order is Complete',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.green.shade800,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: actionButton,
        ),
      ),
    );
  }

  BoxDecoration _cardBoxDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFEDF2F7)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
}

class _HorizontalStep {
  final String label;
  final IconData icon;
  final bool isCompleted;
  final bool isActive;

  _HorizontalStep({
    required this.label,
    required this.icon,
    required this.isCompleted,
    required this.isActive,
  });
}
