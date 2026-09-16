import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../services/notification_service.dart';
import '../../../services/service_request_service.dart';
import '../../../services/customer_service.dart';
import '../../../models/order.dart';

import '../orders/request_service_flow.dart';
import '../delivery/delivery_tracking_screen.dart';
import '../orders/customer_orders_screen.dart';
import '../notifications/customer_notifications_screen.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final NotificationService _notificationService = NotificationService();
  final ServiceRequestService _serviceRequestService = ServiceRequestService();
  final CustomerService _customerService = CustomerService();
  int _unreadNotificationsCount = 0;
  
  // Recent activity state
  bool _loadingRecentOrders = false;
  List<LaundryOrder> _recentOrders = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
    _loadRecentOrders();
  }

  Future<void> _loadUnreadCount() async {
    final count = await _notificationService.getUnreadCount();
    if (mounted) {
      setState(() => _unreadNotificationsCount = count);
    }
  }

  /// Load recent customer orders (last 3 orders)
  Future<void> _loadRecentOrders() async {
    setState(() {
      _loadingRecentOrders = true;
      _errorMessage = null;
    });

    try {
      // Get authenticated customer ID
      final customerId = await _customerService.getCurrentAuthenticatedCustomerId();
      
      // Fetch orders for this customer
      final orders = await _serviceRequestService.getOrdersByCustomerId(customerId);
      
      setState(() {
        _recentOrders = orders.take(3).toList(); // Show last 3 orders
        _loadingRecentOrders = false;
      });
      print('✅ Loaded ${orders.length} recent orders for home screen');
    } catch (e) {
      setState(() {
        _loadingRecentOrders = false;
        _errorMessage = e.toString();
      });
      print('❌ Error loading recent orders: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 30),
              _buildStatusCard(),
              const SizedBox(height: 30),
              _buildQuickActions(context),
              const SizedBox(height: 30),
              _buildRecentActivity(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, Customer!',
                style: AppTheme.lightTheme.textTheme.headlineMedium,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Your laundry is our priority. 🫧',
                style: AppTheme.lightTheme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.6)),
              ),
              child: IconButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CustomerNotificationsScreen(
                        onNotificationsCleared: () {
                          _loadUnreadCount(); // Reload count after clearing
                        },
                      ),
                    ),
                  );
                  _loadUnreadCount(); // Reload count when returning
                },
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.notifications_none_rounded, 
                  color: _unreadNotificationsCount > 0 ? AppTheme.errorRed : AppTheme.textDark, 
                  size: 22
                ),
                tooltip: 'Notifications',
              ),
            ),
            if (_unreadNotificationsCount > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.errorRed,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Text(
                    '$_unreadNotificationsCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 8),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.softGray,
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(2),
          child: ClipOval(
            child: Image.asset(
              'assets/images/logo.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.person),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.accentBlue,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentBlue.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Active Order Status',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Processing...',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_laundry_service, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LinearProgressIndicator(
            value: 0.6,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your laundry is being dried. Almost ready!',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: AppTheme.lightTheme.textTheme.titleMedium),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                'New Request',
                Icons.add_shopping_cart,
                AppTheme.lightBlue,
                AppTheme.accentBlue,
                onTap: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RequestServiceFlow()),
                  );
                  // Refresh recent orders after creating a new request
                  if (result == true) {
                    _loadRecentOrders();
                  }
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildActionCard(
                'Track Delivery',
                Icons.delivery_dining,
                AppTheme.teamMemberOrange,
                AppTheme.teamMemberIconOrange,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const DeliveryTrackingScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard(String title, IconData icon, Color bgColor, Color iconColor, {required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: AppStyles.cardDecoration.copyWith(
            color: Colors.transparent, // Let Material handle the background
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(height: 12),
              Text(title, style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivity(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Activity', style: AppTheme.lightTheme.textTheme.titleMedium),
            TextButton(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CustomerOrdersScreen()),
                );
                // Refresh recent orders when returning from orders screen
                if (result == true) {
                  _loadRecentOrders();
                }
              },
              child: const Text('View All', style: TextStyle(color: AppTheme.accentBlue, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Loading state
        if (_loadingRecentOrders)
          Container(
            padding: const EdgeInsets.all(40),
            decoration: AppStyles.cardDecoration,
            child: const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Loading recent orders...', style: TextStyle(color: AppTheme.textLight, fontSize: 12)),
                ],
              ),
            ),
          )
        
        // No recent orders
        else if (_recentOrders.isEmpty)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RequestServiceFlow()),
                );
                // Refresh recent orders after creating a new request
                if (result == true) {
                  _loadRecentOrders();
                }
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: AppStyles.cardDecoration,
                child: Column(
                  children: [
                    Icon(Icons.local_laundry_service_outlined, size: 48, color: AppTheme.textLight.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    const Text(
                      'No recent orders',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textLight),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap to request your first laundry service',
                      style: TextStyle(fontSize: 12, color: AppTheme.textLight),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          )
        
        // Recent orders list
        else
          Column(
            children: _recentOrders.take(3).map((order) => _buildRecentOrderCard(order)).toList(),
          ),
      ],
    );
  }

  /// Build a card for a recent order
  Widget _buildRecentOrderCard(LaundryOrder order) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CustomerOrdersScreen()),
            );
            if (result == true) {
              _loadRecentOrders();
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: AppStyles.cardDecoration,
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _getStatusColor(order.status).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_getStatusIcon(order.status), color: _getStatusColor(order.status), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.orderNumber ?? 'REQ-${order.id.substring(0, 8)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatOrderSubtitle(order),
                            style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(order.status).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_getStatusIcon(order.status), size: 12, color: _getStatusColor(order.status)),
                          const SizedBox(width: 4),
                          Text(
                            _getStatusText(order.status),
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _getStatusColor(order.status)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                // Show additional details for service requests
                if (order.customerDescription != null || order.laundryPhotoUrls?.isNotEmpty == true) ...[
                  const Divider(height: 20),
                  Row(
                    children: [
                      if (order.laundryPhotoUrls?.isNotEmpty == true) ...[
                        const Icon(Icons.photo_camera_outlined, size: 15, color: AppTheme.textLight),
                        const SizedBox(width: 4),
                        Text('${order.laundryPhotoUrls!.length} photo${order.laundryPhotoUrls!.length > 1 ? 's' : ''}', 
                             style: const TextStyle(fontSize: 12, color: AppTheme.textDark, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 12),
                      ],
                      if (order.customerDescription != null) ...[
                        const Icon(Icons.description_outlined, size: 15, color: AppTheme.textLight),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: Text('Description provided', 
                               style: TextStyle(fontSize: 12, color: AppTheme.textLight),
                               overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Format order subtitle with date and service type
  String _formatOrderSubtitle(LaundryOrder order) {
    final date = _formatDate(order.createdAt);
    return '$date • Wash, Dry & Fold';
  }

  /// Format date for display
  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                   'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, ${date.year}';
  }

  /// Get status color for order status
  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_approval:
        return Colors.orange;
      case OrderStatus.processing:
        return AppTheme.accentBlue;
      case OrderStatus.ready:
        return Colors.green;
      case OrderStatus.out_for_delivery:
        return Colors.purple;
      case OrderStatus.completed:
        return Colors.green.shade700;
      case OrderStatus.rejected:
        return Colors.red;
      default:
        return AppTheme.textLight;
    }
  }

  /// Get status icon for order status
  IconData _getStatusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_approval:
        return Icons.pending_outlined;
      case OrderStatus.processing:
        return Icons.sync;
      case OrderStatus.ready:
        return Icons.check_circle_outline;
      case OrderStatus.out_for_delivery:
        return Icons.local_shipping_outlined;
      case OrderStatus.completed:
        return Icons.check_circle;
      case OrderStatus.rejected:
        return Icons.cancel_outlined;
      default:
        return Icons.local_laundry_service;
    }
  }

  /// Get status text for order status
  String _getStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_approval:
        return 'Pending Review';
      case OrderStatus.processing:
        return 'Processing';
      case OrderStatus.ready:
        return 'Ready';
      case OrderStatus.out_for_delivery:
        return 'Out for Delivery';
      case OrderStatus.completed:
        return 'Completed';
      case OrderStatus.rejected:
        return 'Declined';
      default:
        return 'Unknown';
    }
  }
}
