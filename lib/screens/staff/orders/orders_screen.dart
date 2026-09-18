import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import 'create_order_flow.dart';
import 'order_status_screen.dart';
import 'review_request_screen.dart';
import 'rejected_requests_screen.dart';
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
  List<LaundryOrder> _pendingRequests = [];
  List<LaundryOrder> _activeOrders = [];
  List<LaundryOrder> _historyOrders = [];
  List<LaundryOrder> _rejectedOrders = [];
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
      // Load pending requests (pending_approval)
      final pendingRequests = await _orderService.fetchOrders(
        statuses: ['pending_approval'],
        limit: 50,
      );

      // Load active orders (pending_pickup, processing, ready, out_for_delivery)
      final activeOrders = await _orderService.fetchOrders(
        statuses: ['pending_pickup', 'processing', 'ready', 'out_for_delivery'],
        limit: 50,
      );

      // Load completed orders for history
      final historyOrders = await _orderService.fetchOrders(
        statuses: ['completed'],
        limit: 50,
      );

      // Load rejected requests
      final rejectedOrders = await _orderService.fetchOrders(
        statuses: ['rejected'],
        limit: 50,
      );

      setState(() {
        _pendingRequests = pendingRequests;
        _activeOrders = activeOrders;
        _historyOrders = historyOrders;
        _rejectedOrders = rejectedOrders;
        _isLoading = false;
      });

      print('✅ Loaded ${pendingRequests.length} pending requests, ${activeOrders.length} active orders, ${historyOrders.length} history orders, and ${rejectedOrders.length} rejected requests');
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
    final requestCount = _pendingRequests.length;
    final rejectedCount = _rejectedOrders.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Orders'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Badge(
                isLabelVisible: rejectedCount > 0,
                backgroundColor: Colors.red,
                label: Text(
                  '$rejectedCount',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                child: const Icon(
                  Icons.do_disturb_alt_outlined,
                  color: AppTheme.textDark,
                ),
              ),
              tooltip: 'Rejected Requests',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RejectedRequestsScreen(),
                  ),
                );
                // Refresh list on return in case status changed
                _loadOrders();
              },
            ),
          ),
        ],
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
      body: RefreshIndicator(
        onRefresh: _loadOrders,
        child: TabBarView(
          controller: _tabController,
          children: [
            KeepAlive(keepAlive: true, child: _buildRequestsTab()),
            KeepAlive(keepAlive: true, child: _buildActiveTab()),
            KeepAlive(keepAlive: true, child: _buildHistoryTab()),
          ],
        ),
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
    final requests = _pendingRequests;

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
    final hasPhotos = request.laundryPhotoUrls != null && request.laundryPhotoUrls!.isNotEmpty;
    final photoCount = request.laundryPhotoUrls?.length ?? 0;
    final isRiderPickup = request.collectionMethod == CollectionMethod.riderPickup;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ReviewRequestScreen(request: request),
              ),
            );
            if (result == true) {
              await _loadOrders();
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        request.orderNumber ?? request.id,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentBlue, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: (isRiderPickup ? AppTheme.accentBlue : Colors.teal).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        request.collectionText.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isRiderPickup ? AppTheme.accentBlue : Colors.teal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'PENDING',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(request.customerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                if (request.customerPhone != null && request.customerPhone!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined, size: 14, color: AppTheme.textLight),
                      const SizedBox(width: 4),
                      Text(
                        request.customerPhone!,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                      ),
                    ],
                  ),
                ],
                if (request.deliveryAddress != null && request.deliveryAddress!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textLight),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          request.deliveryAddress!,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (hasPhotos) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.photo_library_outlined, size: 14, color: AppTheme.accentBlue),
                      const SizedBox(width: 4),
                      Text(
                        '$photoCount photo${photoCount > 1 ? 's' : ''} attached',
                        style: const TextStyle(fontSize: 11, color: AppTheme.accentBlue, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ReviewRequestScreen(request: request),
                        ),
                      );
                      
                      // Refresh if order was updated
                      if (result == true) {
                        await _loadOrders();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('REVIEW REQUEST', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward, size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => OrderStatusScreen(order: order)),
        );
        if (result == true) {
          await _loadOrders();
        }
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
              children: [
                Flexible(
                  child: Text(
                    order.displayNumber,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
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
              order.needsCheckIn
                  ? 'Needs check-in'
                  : '${order.loads.length} load(s) • ${order.weightDisplay}',
              style: TextStyle(
                fontSize: 12,
                color: order.needsCheckIn ? Colors.orange : AppTheme.textLight,
                fontWeight: order.needsCheckIn ? FontWeight.w600 : FontWeight.normal,
              ),
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
      case OrderStatus.ready:
        color = Colors.blue;
        label = 'Processing';
        break;
      case OrderStatus.out_for_delivery:
        color = Colors.purple;
        label = 'Out for Delivery';
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