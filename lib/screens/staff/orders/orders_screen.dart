import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import 'create_order_flow.dart';
import 'order_status_screen.dart';
import '../../../services/mock_data_service.dart';
import '../../../services/order_service.dart';

class OrdersScreen extends StatefulWidget {
  final int initialTab;
  const OrdersScreen({super.key, this.initialTab = 1});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final OrderService _orderService = OrderService();
  List<LaundryOrder> _activeOrders = [];
  List<LaundryOrder> _historyOrders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
    _loadOrders();
  }

  /// Load real orders from database
  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load active orders (processing, ready, out_for_delivery)
      final activeOrders = await _orderService.fetchOrders(
        statuses: ['processing', 'ready', 'out_for_delivery'],
        limit: 50,
      );

      // Load completed orders for history
      final historyOrders = await _orderService.fetchOrders(
        statuses: ['completed'],
        limit: 50,
      );

      setState(() {
        _activeOrders = activeOrders;
        _historyOrders = historyOrders;
        _isLoading = false;
      });

      print('✅ Loaded ${activeOrders.length} active orders and ${historyOrders.length} history orders');
    } catch (e) {
      print('❌ Error loading orders: $e');
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading orders: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requestCount = MockDataService().pendingRequests.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Orders'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: AppTheme.softGray,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppTheme.accentBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.textLight,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              dividerHeight: 0,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Requests'),
                      if (requestCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$requestCount',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Tab(text: 'Active'),
                const Tab(text: 'History'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRequestsTab(),
          _buildActiveTab(),
          _buildHistoryTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateOrderFlow()),
          );
          
          // Refresh orders after creating a new order
          if (result == true) {
            await _loadOrders();
          }
        },
        backgroundColor: AppTheme.accentBlue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // ========== REQUESTS TAB ==========

  Widget _buildRequestsTab() {
    final requests = MockDataService().pendingRequests;

    if (requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.online_prediction, size: 80, color: AppTheme.textLight.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text('No pending online requests', style: TextStyle(color: AppTheme.textLight)),
            const SizedBox(height: 8),
            Text(
              'New requests from customers will appear here.',
              style: TextStyle(color: AppTheme.textLight.withValues(alpha: 0.5), fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: requests.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _buildRequestCard(requests[index]),
    );
  }

  Widget _buildRequestCard(LaundryOrder request) {
    // Simplified version - keeping basic structure
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.id,
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
          ),
          const SizedBox(height: 8),
          Text(request.customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              // Handle request review
            },
            child: const Text('REVIEW REQUEST'),
          ),
        ],
      ),
    );
  }

  // ========== ACTIVE TAB ==========

  Widget _buildActiveTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_activeOrders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined, size: 80, color: AppTheme.textLight.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text('No active orders', style: TextStyle(color: AppTheme.textLight)),
            const SizedBox(height: 8),
            Text(
              'New orders will appear here when created.',
              style: TextStyle(color: AppTheme.textLight.withValues(alpha: 0.5), fontSize: 12),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: _activeOrders.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) => _buildOrderCard(_activeOrders[index]),
      ),
    );
  }

  // ========== HISTORY TAB ==========

  Widget _buildHistoryTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_historyOrders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 80, color: AppTheme.textLight.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text('No order history', style: TextStyle(color: AppTheme.textLight)),
            const SizedBox(height: 8),
            Text(
              'Completed orders will appear here.',
              style: TextStyle(color: AppTheme.textLight.withValues(alpha: 0.5), fontSize: 12),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: _historyOrders.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) => _buildOrderCard(_historyOrders[index]),
      ),
    );
  }

  // ========== HELPER METHODS ==========

  Widget _buildOrderCard(LaundryOrder order) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => OrderStatusScreen(order: order)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  order.orderNumber ?? order.id,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
                ),
                _buildStatusBadge(order.status),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              order.customerName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '${order.loads.length} load(s) • ${order.weightDisplay}',
              style: TextStyle(fontSize: 12, color: AppTheme.textLight),
            ),
            if (order.rfidTag != null) ...[
              const SizedBox(height: 4),
              Text(
                'RFID: ${order.rfidTag}',
                style: TextStyle(fontSize: 12, color: AppTheme.accentBlue),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(OrderStatus status) {
    Color color;
    String label;

    switch (status) {
      case OrderStatus.processing:
        color = Colors.blue;
        label = 'Processing';
        break;
      case OrderStatus.ready:
        color = Colors.green;
        label = 'Ready';
        break;
      case OrderStatus.completed:
        color = Colors.grey;
        label = 'Completed';
        break;
      default:
        color = AppTheme.textLight;
        label = status.toString().split('.').last;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }
}