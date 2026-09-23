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
      // Fetch all orders (active and completed)
      final allOrders = await _orderService.fetchOrders(
        limit: 100,
      );

      final unpaid = allOrders.where((o) => o.paymentStatus == PaymentStatus.unpaid).toList();
      final paid = allOrders.where((o) => o.paymentStatus == PaymentStatus.paid).toList();

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

  @override
  Widget build(BuildContext context) {
    final displayedOrders = _showPaid ? _paidOrders : _unpaidOrders;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Payments'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                _buildFilterChip('Unpaid (${_unpaidOrders.length})', !_showPaid, isUnpaid: true),
                const SizedBox(width: 12),
                _buildFilterChip('Paid (${_paidOrders.length})', _showPaid, isUnpaid: false),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : displayedOrders.isEmpty
                    ? RefreshIndicator(
                        onRefresh: _loadOrders,
                        child: ListView(
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.45,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _showPaid ? Icons.check_circle_outline : Icons.payments_outlined,
                                      size: 64,
                                      color: AppTheme.textLight.withValues(alpha: 0.3),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _showPaid ? 'No paid orders yet' : 'No unpaid orders',
                                      style: const TextStyle(fontSize: 16, color: AppTheme.textLight, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _showPaid
                                          ? 'Orders marked as paid will appear here.'
                                          : 'Pay later orders will reflect here.',
                                      style: const TextStyle(fontSize: 13, color: AppTheme.textLight),
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
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                          itemCount: displayedOrders.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 16),
                          itemBuilder: (context, index) => _buildPaymentCard(displayedOrders[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, {required bool isUnpaid}) {
    return GestureDetector(
      onTap: () => setState(() => _showPaid = !isUnpaid),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentBlue : AppTheme.softGray,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textDark,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentCard(LaundryOrder order) {
    final double total = order.totalAmount ?? (order.basePrice > 0 ? order.basePrice : 170.0);
    final isPaid = order.paymentStatus == PaymentStatus.paid;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isPaid ? Colors.green.withValues(alpha: 0.1) : AppTheme.errorRed.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPaid ? Icons.check : Icons.payment,
              color: isPaid ? Colors.green : AppTheme.errorRed,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.customerName,
                  style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  'Order ${order.displayNumber}',
                  style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(color: AppTheme.textLight),
                ),
                if (order.loads.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${order.loads.length} load(s) • ${order.weightDisplay}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₱${total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
              ),
              if (!isPaid) ...[
                const SizedBox(height: 4),
                ElevatedButton(
                  onPressed: () async {
                    final paidSuccess = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(builder: (context) => PaymentProcessScreen(order: order)),
                    );
                    if (paidSuccess == true) {
                      await _loadOrders();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Pay Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ] else ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'PAID',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
