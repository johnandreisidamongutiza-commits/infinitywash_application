import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import '../../../services/rider_service.dart';
import 'rider_payment_process_screen.dart';

/// Dedicated Payment tab screen for Riders to view and collect payments
/// for pickup and delivery orders.
class RiderPaymentScreen extends StatefulWidget {
  final bool isActive;

  const RiderPaymentScreen({super.key, this.isActive = true});

  @override
  State<RiderPaymentScreen> createState() => RiderPaymentScreenState();
}

class RiderPaymentScreenState extends State<RiderPaymentScreen> {
  final RiderService _riderService = RiderService();
  bool _showPaid = false;
  bool _isLoading = true;
  String _searchQuery = '';
  List<LaundryOrder> _unpaidOrders = [];
  List<LaundryOrder> _paidOrders = [];

  @override
  void initState() {
    super.initState();
    // Only load immediately if this screen is already the active tab (e.g. the
    // app launched directly onto the Payment tab). If it starts offstage inside
    // IndexedStack, skip the load here — didUpdateWidget will trigger it the
    // moment isActive flips true, guaranteeing setState never runs mid-layout.
    if (widget.isActive) _loadOrders();
  }

  @override
  void didUpdateWidget(covariant RiderPaymentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload every time the tab becomes active so fresh data is always shown.
    if (widget.isActive && !oldWidget.isActive) {
      _loadOrders();
    }
  }

  void refreshOrders() {
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final allOrders = await _riderService.fetchRiderPaymentOrders(limit: 100);

      final unpaid = allOrders
          .where((o) => o.paymentStatus == PaymentStatus.unpaid)
          .toList();
      final paid = allOrders
          .where((o) => o.paymentStatus == PaymentStatus.paid)
          .toList();

      if (!mounted) return;
      setState(() {
        _unpaidOrders = unpaid;
        _paidOrders = paid;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading rider payment orders: $e');
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

  List<LaundryOrder> _getFilteredOrders() {
    final list = _showPaid ? _paidOrders : _unpaidOrders;
    if (_searchQuery.trim().isEmpty) return list;

    final q = _searchQuery.trim().toLowerCase();
    return list.where((order) {
      final name = order.customerName.toLowerCase();
      final number = order.displayNumber.toLowerCase();
      final phone = (order.customerPhone ?? '').toLowerCase();
      return name.contains(q) || number.contains(q) || phone.contains(q);
    }).toList();
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
          // Filter Chips & Search
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                // Filter Tabs (Unpaid vs Paid)
                Row(
                  children: [
                    Expanded(
                      child: _buildFilterTab(
                        title: 'Unpaid (${_unpaidOrders.length})',
                        isSelected: !_showPaid,
                        isUnpaid: true,
                        onTap: () => setState(() => _showPaid = false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildFilterTab(
                        title: 'Paid (${_paidOrders.length})',
                        isSelected: _showPaid,
                        isUnpaid: false,
                        onTap: () => setState(() => _showPaid = true),
                      ),
                    ),
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
                          primary: false,
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.45,
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
                          primary: false,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: displayedOrders.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final order = displayedOrders[index];
                            return _buildOrderCard(order);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTab({
    required String title,
    required bool isSelected,
    required bool isUnpaid,
    required VoidCallback onTap,
  }) {
    final activeColor = isUnpaid ? AppTheme.accentBlue : Colors.green[700]!;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? activeColor : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  String _getJobStatusLabel(LaundryOrder order) {
    switch (order.status) {
      case OrderStatus.completed:
        return 'Job Completed';
      case OrderStatus.out_for_delivery:
        return 'Out for Delivery';
      case OrderStatus.ready:
        return 'Ready';
      case OrderStatus.pending_pickup:
        return 'Pending Pickup';
      case OrderStatus.processing:
        return 'Processing';
      default:
        return '';
    }
  }

  String _formatDateTime(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} $hour:$minute $period';
  }

  Future<void> _openPaymentProcess(LaundryOrder order, bool isDelivery) async {
    final paid = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => RiderPaymentProcessScreen(
          order: order,
          jobType: isDelivery ? 'delivery' : 'pickup',
        ),
      ),
    );

    if (paid == true) {
      _loadOrders();
    }
  }

  void _showReceiptSheet(LaundryOrder order, double total) {
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
            Text(
              'Order ${order.displayNumber}',
              style: const TextStyle(color: AppTheme.textLight, fontSize: 13),
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
                  _receiptSheetRow('Amount Paid', '₱${total.toStringAsFixed(2)}', isBold: true),
                  _receiptSheetRow('Payment Method', order.paymentMethod ?? 'Cash / GCash'),
                  if (order.paidAt != null)
                    _receiptSheetRow('Paid Date', _formatDateTime(order.paidAt!)),
                  if (order.deliveryAddress != null && order.deliveryAddress!.isNotEmpty)
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
                child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
          Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textLight)),
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

  Widget _buildOrderCard(LaundryOrder order) {
    final isDelivery = order.returnMethod == ReturnMethod.delivery;
    final isPaid = order.paymentStatus == PaymentStatus.paid;
    final total = order.totalAmount ?? (order.basePrice > 0 ? order.basePrice : 170.0);
    final jobStatusLabel = _getJobStatusLabel(order);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (!isPaid) {
            _openPaymentProcess(order, isDelivery);
          } else {
            _showReceiptSheet(order, total);
          }
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPaid ? Colors.grey.shade200 : AppTheme.accentBlue.withValues(alpha: 0.25),
              width: isPaid ? 1 : 1.5,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Badges (Delivery/Pickup, Job status) & Price with chevron
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDelivery ? Colors.purple.shade50 : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isDelivery ? Icons.local_shipping_outlined : Icons.inventory_2_outlined,
                                size: 13,
                                color: isDelivery ? Colors.purple.shade700 : AppTheme.accentBlue,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isDelivery ? 'Delivery' : 'Pickup',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isDelivery ? Colors.purple.shade700 : AppTheme.accentBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (jobStatusLabel.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: order.status == OrderStatus.completed
                                  ? Colors.green.shade50
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              jobStatusLabel,
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '₱${total.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: isPaid ? Colors.green[700] : AppTheme.accentBlue,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: isPaid ? Colors.grey.shade400 : AppTheme.accentBlue,
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Customer name & Order number row
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
              if (order.customerPhone != null && order.customerPhone!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.phone_outlined, size: 13, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      order.customerPhone!,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
              if (order.deliveryAddress != null && order.deliveryAddress!.isNotEmpty) ...[
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

              // Bottom Bar: Status Badge / Action Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
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
                  if (!isPaid)
                    // Flexible + minimumSize/tapTargetSize overrides cancel the global
                    // theme's Size(double.infinity, 56) which forces w=Infinity when
                    // the button is a direct Row child (unconstrained width pass).
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
                          'Collect Payment',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: () => _openPaymentProcess(order, isDelivery),
                      ),
                    )
                  else
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
