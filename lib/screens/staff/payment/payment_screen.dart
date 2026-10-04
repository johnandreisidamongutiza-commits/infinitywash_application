import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import '../../../services/order_service.dart';
import 'payment_process_screen.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final OrderService _orderService = OrderService();
  bool _showPaid = false;
  bool _isLoading = true;
  String _searchQuery = '';
  String _subFilter = 'all'; // 'all', 'walkin', 'rider'
  List<LaundryOrder> _unpaidOrders = [];
  List<LaundryOrder> _paidOrders = [];

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final allOrders = await _orderService.fetchOrders(limit: 100);

      // Only show orders that have been checked in (have loads)
      final checkedInOrders = allOrders.where((o) => o.loads.isNotEmpty).toList();

      final unpaid = checkedInOrders.where((o) => o.paymentStatus == PaymentStatus.unpaid).toList();
      final paid = checkedInOrders.where((o) => o.paymentStatus == PaymentStatus.paid).toList();

      if (!mounted) return;
      setState(() {
        _unpaidOrders = unpaid;
        _paidOrders = paid;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading payment orders: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading payments: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  bool _isRiderOrder(LaundryOrder order) {
    return order.collectionMethod == CollectionMethod.riderPickup ||
        order.returnMethod == ReturnMethod.delivery;
  }

  List<LaundryOrder> _getFilteredOrders() {
    final list = _showPaid ? _paidOrders : _unpaidOrders;

    // Apply sub-filter
    List<LaundryOrder> filtered;
    switch (_subFilter) {
      case 'walkin':
        filtered = list.where((o) => !_isRiderOrder(o)).toList();
        break;
      case 'rider':
        filtered = list.where((o) => _isRiderOrder(o)).toList();
        break;
      default:
        filtered = list;
    }

    // Apply search
    if (_searchQuery.trim().isEmpty) return filtered;
    final q = _searchQuery.trim().toLowerCase();
    return filtered.where((order) {
      final name = order.customerName.toLowerCase();
      final number = order.displayNumber.toLowerCase();
      return name.contains(q) || number.contains(q);
    }).toList();
  }

  double _getTotalUnpaid() {
    return _unpaidOrders.fold(0.0, (sum, o) {
      return sum + (o.totalAmount ?? (o.basePrice > 0 ? o.basePrice : 170.0));
    });
  }

  double _getTotalCollected() {
    return _paidOrders.fold(0.0, (sum, o) {
      return sum + (o.totalAmount ?? (o.basePrice > 0 ? o.basePrice : 170.0));
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayedOrders = _getFilteredOrders();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Payments',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.accentBlue),
            tooltip: 'Refresh',
            onPressed: _loadOrders,
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats Header
          _buildStatsHeader(),

          // Filter & Search Section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                // Main filter tabs (Unpaid / Paid)
                Row(
                  children: [
                    Expanded(
                      child: _buildFilterTab(
                        title: 'Unpaid (${_unpaidOrders.length})',
                        isSelected: !_showPaid,
                        color: AppTheme.accentBlue,
                        onTap: () => setState(() => _showPaid = false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildFilterTab(
                        title: 'Paid (${_paidOrders.length})',
                        isSelected: _showPaid,
                        color: Colors.green[700]!,
                        onTap: () => setState(() => _showPaid = true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Sub-filter chips (All / Walk-in / Rider)
                Row(
                  children: [
                    _buildSubFilterChip('All', 'all'),
                    const SizedBox(width: 8),
                    _buildSubFilterChip('Walk-in', 'walkin'),
                    const SizedBox(width: 8),
                    _buildSubFilterChip('Rider', 'rider'),
                  ],
                ),
                const SizedBox(height: 12),
                // Search Input
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search by customer name or order #',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                    prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.textLight),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setState(() => _searchQuery = ''),
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey[100],
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Orders List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.accentBlue),
                  )
                : displayedOrders.isEmpty
                    ? RefreshIndicator(
                        onRefresh: _loadOrders,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.35,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _showPaid
                                          ? Icons.receipt_long_outlined
                                          : Icons.check_circle_outline,
                                      size: 64,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _showPaid
                                          ? 'No paid orders found'
                                          : 'No unpaid orders. All caught up!',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Pull down to refresh',
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadOrders,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: displayedOrders.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) => _buildPaymentCard(displayedOrders[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ─── Stats Header ──────────────────────────────────────────────
  Widget _buildStatsHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatItem(
              icon: Icons.pending_actions,
              iconColor: Colors.amber.shade700,
              iconBg: Colors.amber.shade50,
              label: 'Unpaid',
              value: '₱${_getTotalUnpaid().toStringAsFixed(0)}',
              subValue: '${_unpaidOrders.length} orders',
            ),
          ),
          Container(
            width: 1,
            height: 44,
            color: Colors.grey.shade200,
          ),
          Expanded(
            child: _buildStatItem(
              icon: Icons.check_circle_outline,
              iconColor: Colors.green.shade700,
              iconBg: Colors.green.shade50,
              label: 'Collected',
              value: '₱${_getTotalCollected().toStringAsFixed(0)}',
              subValue: '${_paidOrders.length} orders',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required String value,
    required String subValue,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
            Text(
              subValue,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Filter Tab ─────────────────────────────────────────────────
  Widget _buildFilterTab({
    required String title,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? color : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Sub-filter Chip ────────────────────────────────────────────
  Widget _buildSubFilterChip(String label, String filter) {
    final isSelected = _subFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _subFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  // ─── Payment Card ───────────────────────────────────────────────
  Widget _buildPaymentCard(LaundryOrder order) {
    final double total = order.totalAmount ?? (order.basePrice > 0 ? order.basePrice : 170.0);
    final isPaid = order.paymentStatus == PaymentStatus.paid;
    final isRider = _isRiderOrder(order);
    final isDelivery = order.returnMethod == ReturnMethod.delivery;
    final isPickup = order.collectionMethod == CollectionMethod.riderPickup;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (isPaid) {
            _showReceiptSheet(order, total);
          } else if (!isRider) {
            _openPaymentProcess(order);
          }
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPaid
                  ? Colors.grey.shade200
                  : (isRider
                      ? Colors.grey.shade200
                      : AppTheme.accentBlue.withValues(alpha: 0.25)),
              width: isPaid ? 1 : 1.5,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Badges & Price
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildOrderTypeBadge(
                          isDelivery: isDelivery,
                          isPickup: isPickup,
                        ),
                        if (_getOrderStatusLabel(order).isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: order.status == OrderStatus.completed
                                  ? Colors.green.shade50
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _getOrderStatusLabel(order),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: order.status == OrderStatus.completed
                                    ? Colors.green.shade800
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '₱${total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: isPaid ? Colors.green[700] : AppTheme.accentBlue,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Customer name & order number
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      order.customerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    order.displayNumber,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: AppTheme.textLight,
                    ),
                  ),
                ],
              ),

              // Weight & loads info
              if (order.loads.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.scale_outlined, size: 13, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      '${order.loads.length} load(s) • ${order.weightDisplay}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],

              // Address for delivery orders
              if (isDelivery &&
                  order.deliveryAddress != null &&
                  order.deliveryAddress!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 13, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        order.deliveryAddress!,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Bottom Bar: Status + Action
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Payment status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isPaid ? Colors.green.shade50 : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isPaid ? Icons.check_circle : Icons.schedule,
                          size: 13,
                          color: isPaid ? Colors.green.shade700 : Colors.amber.shade800,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isPaid ? 'Paid' : 'Payment Due',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isPaid ? Colors.green.shade700 : Colors.amber.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Action area
                  if (!isPaid) ...[
                    if (isRider)
                      // Rider order: show "Rider Will Collect" muted indicator + override
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.two_wheeler, size: 13, color: Colors.purple.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  'Rider Collects',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _openPaymentProcess(order),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Override',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      // Walk-in order: prominent "Pay Now" button
                      Flexible(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            minimumSize: const Size(0, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.payments_outlined, size: 16),
                          label: const Text(
                            'Pay Now',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          onPressed: () => _openPaymentProcess(order),
                        ),
                      ),
                  ] else ...[
                    Row(
                      children: [
                        if (order.paymentMethod != null)
                          Text(
                            'Via ${order.paymentMethod}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                          ),
                        const SizedBox(width: 4),
                        const Icon(Icons.verified, size: 16, color: Colors.green),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Order Type Badge ───────────────────────────────────────────
  Widget _buildOrderTypeBadge({required bool isDelivery, required bool isPickup}) {
    final String label;
    final IconData icon;
    final Color color;
    final Color bgColor;

    if (isDelivery) {
      label = 'Delivery';
      icon = Icons.local_shipping_outlined;
      color = Colors.indigo.shade700;
      bgColor = Colors.indigo.shade50;
    } else if (isPickup) {
      label = 'Rider Pickup';
      icon = Icons.two_wheeler;
      color = Colors.purple.shade700;
      bgColor = Colors.purple.shade50;
    } else {
      label = 'Walk-in';
      icon = Icons.storefront_outlined;
      color = AppTheme.accentBlue;
      bgColor = Colors.blue.shade50;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Order Status Label ─────────────────────────────────────────
  String _getOrderStatusLabel(LaundryOrder order) {
    switch (order.status) {
      case OrderStatus.completed:
        return 'Completed';
      case OrderStatus.out_for_delivery:
        return 'Out for Delivery';
      case OrderStatus.ready:
        return 'Ready';
      case OrderStatus.processing:
        return 'Processing';
      default:
        return '';
    }
  }

  // ─── Format DateTime ────────────────────────────────────────────
  String _formatDateTime(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} $hour:$minute $period';
  }

  // ─── Open Payment Process ───────────────────────────────────────
  Future<void> _openPaymentProcess(LaundryOrder order) async {
    final paidSuccess = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => PaymentProcessScreen(order: order)),
    );
    if (paidSuccess == true) {
      await _loadOrders();
    }
  }

  // ─── Receipt Bottom Sheet ───────────────────────────────────────
  void _showReceiptSheet(LaundryOrder order, double total) {
    final isDelivery = order.returnMethod == ReturnMethod.delivery;
    final isPickup = order.collectionMethod == CollectionMethod.riderPickup;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: Colors.green, size: 48),
            ),
            const SizedBox(height: 12),
            const Text(
              'Payment Confirmed',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Order ${order.displayNumber}',
                  style: const TextStyle(color: AppTheme.textLight, fontSize: 13),
                ),
                const SizedBox(width: 8),
                _buildOrderTypeBadge(
                  isDelivery: isDelivery,
                  isPickup: isPickup,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  _receiptSheetRow('Customer', order.customerName),
                  _receiptSheetRow(
                    'Amount Paid',
                    '₱${total.toStringAsFixed(2)}',
                    isBold: true,
                  ),
                  _receiptSheetRow(
                    'Payment Method',
                    order.paymentMethod ?? 'Cash / GCash',
                  ),
                  if (order.paidAt != null)
                    _receiptSheetRow('Paid Date', _formatDateTime(order.paidAt!)),
                  if (order.loads.isNotEmpty)
                    _receiptSheetRow(
                      'Details',
                      '${order.loads.length} load(s) • ${order.weightDisplay}',
                    ),
                  if (isDelivery &&
                      order.deliveryAddress != null &&
                      order.deliveryAddress!.isNotEmpty)
                    _receiptSheetRow('Address', order.deliveryAddress!),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Close',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptSheetRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppTheme.textLight),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: isBold ? AppTheme.accentBlue : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
