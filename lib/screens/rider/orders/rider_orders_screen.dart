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

class RiderOrdersScreenState extends State<RiderOrdersScreen> {
  final RiderService _riderService = RiderService();
  bool _showNew = true;
  bool _isLoading = false;
  String? _error;
  List<LaundryOrder> _pickupOrders = [];
  List<LaundryOrder> _deliveryOrders = [];

  @override
  void initState() {
    super.initState();
    _loadOrders();
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
      // Load both pickup and delivery orders in parallel
      final results = await Future.wait([
        _riderService.fetchPickupOrders(),
        _riderService.fetchDeliveryOrders(),
      ]);

      if (mounted) {
        setState(() {
          _pickupOrders = results[0];
          _deliveryOrders = results[1];
          _isLoading = false;
        });

        print('=== Rider Orders Loaded ===');
        print('Pickups: ${_pickupOrders.length}');
        for (var order in _pickupOrders) {
          print('- ${order.orderNumber ?? order.id}: ${order.customerName}, status: ${order.status}');
        }
        print('Deliveries: ${_deliveryOrders.length}');
        for (var order in _deliveryOrders) {
          print('- ${order.orderNumber ?? order.id}: ${order.customerName}, status: ${order.status}');
        }
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

  List<LaundryOrder> get _currentOrders {
    return _showNew ? _pickupOrders : _deliveryOrders;
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
      ),
      body: RefreshIndicator(
        onRefresh: _loadOrders,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  _buildFilterChip('Pick-ups (${_pickupOrders.length})', _showNew),
                  const SizedBox(width: 12),
                  _buildFilterChip('Deliveries (${_deliveryOrders.length})', !_showNew),
                ],
              ),
            ),
            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
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

    final orders = _currentOrders;
    if (orders.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: orders.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _buildTaskCard(orders[index]),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _showNew ? Icons.inbox_outlined : Icons.local_shipping_outlined,
            size: 64,
            color: AppTheme.textLight.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _showNew ? 'No pickups available' : 'No deliveries pending',
            style: const TextStyle(
              fontSize: 16,
              color: AppTheme.textLight,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _showNew 
                ? 'Check back later for new pickup tasks'
                : 'Complete pickups will appear here',
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected) {
    return GestureDetector(
      onTap: () => setState(() => _showNew = label.contains('Pick-ups')),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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

  Widget _buildTaskCard(LaundryOrder order) {
    String name = order.customerName;
    String address = order.deliveryAddress ?? 'Address not provided';
    bool isPickup = _showNew;
    
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
