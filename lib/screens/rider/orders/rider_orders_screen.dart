import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import '../../../services/rider_service.dart';
import '../route/rider_route_screen.dart';
import 'rider_order_details_screen.dart';

class RiderOrdersScreen extends StatefulWidget {
  const RiderOrdersScreen({super.key});

  @override
  State<RiderOrdersScreen> createState() => RiderOrdersScreenState();
}

class RiderOrdersScreenState extends State<RiderOrdersScreen> with SingleTickerProviderStateMixin {
  final RiderService _riderService = RiderService();
  late TabController _tabController;
  bool _isLoading = false;
  String? _error;
  
  // Active orders
  List<LaundryOrder> _activePickupOrders = [];
  List<LaundryOrder> _activeDeliveryOrders = [];
  
  // Completed orders
  List<LaundryOrder> _completedPickupOrders = [];
  List<LaundryOrder> _completedDeliveryOrders = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Public method to refresh orders - called from RiderMainScreen
  Future<void> refreshOrders() async {
    print('🔵 RIDER: refreshOrders() called');
    await _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load active and completed orders in parallel
      final results = await Future.wait([
        _riderService.fetchActivePickupOrders(),
        _riderService.fetchActiveDeliveryOrders(),
        _riderService.fetchCompletedPickupOrders(),
        _riderService.fetchCompletedDeliveryOrders(),
      ]);

      if (mounted) {
        setState(() {
          _activePickupOrders = results[0];
          _activeDeliveryOrders = results[1];
          _completedPickupOrders = results[2];
          _completedDeliveryOrders = results[3];
          _isLoading = false;
        });

        print('=== Rider Orders Loaded ===');
        print('Active Pickups: ${_activePickupOrders.length}');
        print('Active Deliveries: ${_activeDeliveryOrders.length}');
        print('Completed Pickups: ${_completedPickupOrders.length}');
        print('Completed Deliveries: ${_completedDeliveryOrders.length}');
      }
    } catch (e) {
      print('❌ Error loading rider orders: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Tasks'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadOrders,
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.accentBlue,
          unselectedLabelColor: AppTheme.textLight,
          indicatorColor: AppTheme.accentBlue,
          indicatorWeight: 3,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Pickups'),
                  const SizedBox(width: 4),
                  if (_activePickupOrders.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.errorRed,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_activePickupOrders.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Deliveries'),
                  const SizedBox(width: 4),
                  if (_activeDeliveryOrders.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.teamMemberIconOrange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_activeDeliveryOrders.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Tab(text: 'Completed'),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadOrders,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildActiveOrdersList(_activePickupOrders, isPickup: true),
            _buildActiveOrdersList(_activeDeliveryOrders, isPickup: false),
            _buildCompletedTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveOrdersList(List<LaundryOrder> orders, {required bool isPickup}) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: AppTheme.errorRed,
              ),
              const SizedBox(height: 16),
              const Text(
                'Error loading orders',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textLight,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadOrders,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (orders.isEmpty) {
      return _buildEmptyState(isPickup);
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: orders.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _buildTaskCard(orders[index], isPickup: isPickup),
    );
  }

  Widget _buildCompletedTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              labelColor: AppTheme.accentBlue,
              unselectedLabelColor: AppTheme.textLight,
              indicatorColor: AppTheme.accentBlue,
              indicatorWeight: 2,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.shopping_bag_outlined, size: 16),
                      const SizedBox(width: 6),
                      Text('Pickups (${_completedPickupOrders.length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.delivery_dining, size: 16),
                      const SizedBox(width: 6),
                      Text('Deliveries (${_completedDeliveryOrders.length})'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildCompletedOrdersList(_completedPickupOrders, isPickup: true),
                _buildCompletedOrdersList(_completedDeliveryOrders, isPickup: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedOrdersList(List<LaundryOrder> orders, {required bool isPickup}) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (orders.isEmpty) {
      return _buildCompletedEmptyState(isPickup);
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: orders.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _buildCompletedTaskCard(orders[index], isPickup: isPickup),
    );
  }

  Widget _buildCompletedEmptyState(bool isPickup) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: AppTheme.textLight.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            isPickup ? 'No pickups completed today' : 'No deliveries completed today',
            style: const TextStyle(
              fontSize: 16,
              color: AppTheme.textLight,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Completed tasks will appear here',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedTaskCard(LaundryOrder order, {required bool isPickup}) {
    String name = order.customerName;
    String address = order.deliveryAddress ?? 'Address not provided';
    
    // Determine if loads are TBD (photo request)
    bool hasTBDLoads = order.loads.isEmpty;
    String loadsText = hasTBDLoads ? 'TBD loads • ₱TBD' : '${order.totalLoads} load${order.totalLoads > 1 ? 's' : ''} • ₱${order.basePrice.toStringAsFixed(0)}';
    
    // Get actual completion time from adapter
    final completedTime = _riderService.getOrderCompletionTime(order.id) ?? order.createdAt;
    final timeText = _formatCompletionTime(completedTime);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration.copyWith(
        color: AppTheme.softGray.withValues(alpha: 0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(
                          color: AppTheme.textLight,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isPickup 
                      ? AppTheme.errorRed.withValues(alpha: 0.1) 
                      : AppTheme.teamMemberIconOrange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isPickup ? 'PICKUP' : 'DELIVERY',
                  style: TextStyle(
                    color: isPickup ? AppTheme.errorRed : AppTheme.teamMemberIconOrange,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.textLight),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  address,
                  style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textLight,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                hasTBDLoads ? Icons.help_outline : Icons.local_laundry_service_outlined,
                size: 16,
                color: AppTheme.textLight,
              ),
              const SizedBox(width: 8),
              Text(
                loadsText,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textLight,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.access_time, size: 14, color: Colors.green),
                const SizedBox(width: 6),
                Text(
                  'Completed $timeText',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatCompletionTime(DateTime completedAt) {
    final now = DateTime.now();
    final difference = now.difference(completedAt);
    
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      final hour = completedAt.hour;
      final minute = completedAt.minute;
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return 'at $displayHour:${minute.toString().padLeft(2, '0')} $period';
    } else {
      return 'on ${completedAt.month}/${completedAt.day}';
    }
  }
}

  Widget _buildEmptyState(bool isPickup) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isPickup ? Icons.inbox_outlined : Icons.local_shipping_outlined,
            size: 64,
            color: AppTheme.textLight.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            isPickup ? 'No pickups available' : 'No deliveries pending',
            style: const TextStyle(
              fontSize: 16,
              color: AppTheme.textLight,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isPickup 
                ? 'Check back later for new pickup tasks'
                : 'Check back later for new delivery tasks',
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(LaundryOrder order, {required bool isPickup}) {
    String name = order.customerName;
    String address = order.deliveryAddress ?? 'Address not provided';
    
    // Determine if loads are TBD (photo request)
    bool hasTBDLoads = order.loads.isEmpty;
    String loadsText = hasTBDLoads ? 'TBD loads • ₱TBD' : '${order.totalLoads} load${order.totalLoads > 1 ? 's' : ''} • ₱${order.basePrice.toStringAsFixed(0)}';
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: AppTheme.lightTheme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isPickup 
                      ? AppTheme.errorRed.withValues(alpha: 0.1) 
                      : AppTheme.teamMemberIconOrange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isPickup ? 'PICKUP' : 'DELIVERY',
                  style: TextStyle(
                    color: isPickup ? AppTheme.errorRed : AppTheme.teamMemberIconOrange,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.textLight),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  address,
                  style: AppTheme.lightTheme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                hasTBDLoads ? Icons.help_outline : Icons.local_laundry_service_outlined,
                size: 16,
                color: AppTheme.textLight,
              ),
              const SizedBox(width: 8),
              Text(
                loadsText,
                style: TextStyle(
                  fontSize: 13,
                  color: hasTBDLoads ? AppTheme.teamMemberIconOrange : AppTheme.textDark,
                  fontWeight: hasTBDLoads ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    print('=== View Details clicked ===');
                    print('Order: ${order.orderNumber ?? order.id} - ${order.customerName}');
                    print('Has loads: ${order.loads.isNotEmpty}, Load count: ${order.loads.length}');
                    
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RiderOrderDetailsScreen(
                          order: order,
                          isPickup: isPickup,
                        ),
                      ),
                    );
                    
                    // Refresh orders after returning from details
                    _loadOrders();
                  },
                  child: const Text('View Details'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const RiderRouteScreen()),
                    );
                  },
                  child: const Text('Start'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
