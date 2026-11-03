import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../services/notification_service.dart';
import '../../../services/service_request_service.dart';
import '../../../services/customer_service.dart';
import '../../../models/order.dart';

import '../orders/request_service_flow.dart';
import '../delivery/order_delivery_tracking_screen.dart';
import '../orders/customer_orders_screen.dart';
import '../notifications/customer_notifications_screen.dart';
import '../orders/customer_order_details_screen.dart';
import '../../../widgets/legal_consent_banner.dart';
import '../../../widgets/home_header.dart';
import '../../../services/profile_service.dart';
import '../../../services/profile_local_db.dart';
import '../../../services/supabase_service.dart';
import '../profile/options/account_details_screen.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final NotificationService _notificationService = NotificationService();
  final ServiceRequestService _serviceRequestService = ServiceRequestService();
  final CustomerService _customerService = CustomerService();
  final ProfileService _profileService = ProfileService();
  int _unreadNotificationsCount = 0;
  String? _avatarUrl;
  String? _localAvatarPath;
  
  // Recent activity state
  bool _loadingRecentOrders = false;
  List<LaundryOrder> _recentOrders = [];
  String? _selectedMonitorOrderId;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadUnreadCount();
    _loadRecentOrders();
  }

  Future<void> _loadUserProfile() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId != null) {
      try {
        final cached = await ProfileLocalDatabase.instance.getAvatar(userId);
        if (cached != null && mounted) {
          setState(() {
            _avatarUrl = cached.avatarUrl;
            _localAvatarPath = cached.localPath;
          });
        }
      } catch (_) {}
    }

    try {
      final profile = await _profileService.getProfile();
      if (mounted) {
        setState(() {
          _avatarUrl = profile['avatar_url'] as String?;
        });
      }
    } catch (_) {}
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
    });

    try {
      // Get authenticated customer ID
      final customerId = await _customerService.getCurrentAuthenticatedCustomerId();
      
      // Fetch orders for this customer
      final orders = await _serviceRequestService.getOrdersByCustomerId(customerId);
      
      setState(() {
        _recentOrders = orders; // Full list for active order detection; recent activity uses .take(3)
        if (!_monitorableOrders.any((order) => order.id == _selectedMonitorOrderId)) {
          _selectedMonitorOrderId = null;
        }
        _loadingRecentOrders = false;
      });
      debugPrint('✅ Loaded ${orders.length} recent orders for home screen');
    } catch (e) {
      setState(() {
        _loadingRecentOrders = false;
      });
      debugPrint('❌ Error loading recent orders: $e');
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
              // Soft, non-blocking re-consent prompt when a newer
              // version of the Terms / Privacy Policy is published.
              const LegalConsentBanner(),
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
    return HomeHeader(
      title: 'Hello, Customer!',
      subtitle: 'Your laundry is our priority.',
      avatarUrl: _avatarUrl,
      localAvatarPath: _localAvatarPath,
      unreadCount: _unreadNotificationsCount,
      onAvatarTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const CustomerAccountDetailsScreen(),
          ),
        );
        _loadUserProfile();
      },
      onNotificationTap: () async {
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
        _loadUserProfile();
      },
    );
  }

  // ── Active order helpers ──────────────────────────────────────────

  List<LaundryOrder> get _monitorableOrders => _recentOrders.where((order) =>
      order.status != OrderStatus.completed &&
      order.status != OrderStatus.cancelled &&
      order.status != OrderStatus.rejected).toList();

  /// Find the most relevant active order from loaded orders.
  /// Priority: in-progress statuses first, then pending requests.
  LaundryOrder? get _activeOrder {
    for (final order in _monitorableOrders) {
      if (order.id == _selectedMonitorOrderId) return order;
    }

    // Priority 1: actively in-progress orders
    const inProgressStatuses = [
      OrderStatus.processing,
      OrderStatus.out_for_delivery,
      OrderStatus.ready,
      OrderStatus.pending_pickup,
    ];
    for (final order in _recentOrders) {
      if (inProgressStatuses.contains(order.status)) return order;
    }
    // Priority 2: pending approval requests
    for (final order in _recentOrders) {
      if (order.status == OrderStatus.pending_approval) return order;
    }
    return _monitorableOrders.isEmpty ? null : _monitorableOrders.first;
  }

  /// Status-specific display title for the active order card.
  String _activeStatusTitle(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_approval:
        return 'Request Pending';
      case OrderStatus.pending_pickup:
        return 'Waiting for Pickup';
      case OrderStatus.processing:
        return 'Washing & Drying...';
      case OrderStatus.ready:
        return 'Ready for Pickup';
      case OrderStatus.out_for_delivery:
        return 'Out for Delivery';
      default:
        return 'Processing...';
    }
  }

  /// Status-specific icon for the active order card.
  IconData _activeStatusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_approval:
        return Icons.schedule_rounded;
      case OrderStatus.pending_pickup:
        return Icons.local_shipping_outlined;
      case OrderStatus.processing:
        return Icons.local_laundry_service;
      case OrderStatus.ready:
        return Icons.check_circle_outline_rounded;
      case OrderStatus.out_for_delivery:
        return Icons.delivery_dining_rounded;
      default:
        return Icons.local_laundry_service;
    }
  }

  /// Progress fraction (0.0 – 1.0) mapped to order status.
  double _activeStatusProgress(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_approval:
        return 0.15;
      case OrderStatus.pending_pickup:
        return 0.35;
      case OrderStatus.processing:
        return 0.60;
      case OrderStatus.ready:
        return 0.80;
      case OrderStatus.out_for_delivery:
        return 0.92;
      default:
        return 0.5;
    }
  }

  /// Human-friendly subtitle describing what is happening.
  String _activeStatusSubtitle(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_approval:
        return 'Your laundry request is awaiting staff review.';
      case OrderStatus.pending_pickup:
        return 'A rider has been assigned to collect your laundry.';
      case OrderStatus.processing:
        return 'Your laundry is currently being washed and dried.';
      case OrderStatus.ready:
        return 'Your laundry is clean, folded, and ready!';
      case OrderStatus.out_for_delivery:
        return 'Your rider is on the way with your clean laundry.';
      default:
        return 'Your order is being processed.';
    }
  }

  Widget _buildStatusCard() {
    final activeOrder = _activeOrder;

    return GestureDetector(
      onTap: () async {
        if (activeOrder != null) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CustomerOrderDetailsScreen(order: activeOrder),
            ),
          );
          _loadRecentOrders();
        } else {
          // No active order — navigate to request flow
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const RequestServiceFlow()),
          );
          if (result == true) _loadRecentOrders();
        }
      },
      child: Container(
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
        child: activeOrder != null
            ? _buildActiveOrderContent(activeOrder)
            : _buildNoActiveOrderContent(),
      ),
    );
  }

  /// Content when there IS an active order.
  Widget _buildActiveOrderContent(LaundryOrder order) {
    final status = order.status;
    final monitorableOrders = _monitorableOrders;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Row(
                children: [
                  Icon(Icons.track_changes_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      'Active Order Monitoring',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (monitorableOrders.length > 1) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: order.id,
                    dropdownColor: AppTheme.accentBlue,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                    isDense: true,
                    items: monitorableOrders.map((item) => DropdownMenuItem<String>(
                      value: item.id,
                      child: Text(item.displayNumber, overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (orderId) {
                      if (orderId != null) setState(() => _selectedMonitorOrderId = orderId);
                    },
                  ),
                ),
              ),
            ] else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  order.displayNumber,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                _activeStatusTitle(status),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(_activeStatusIcon(status), color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 20),
        LinearProgressIndicator(
          value: _activeStatusProgress(status),
          backgroundColor: Colors.white.withValues(alpha: 0.2),
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 12),
        Text(
          _activeStatusSubtitle(status),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }

  /// Content when there are NO active orders.
  Widget _buildNoActiveOrderContent() {
    return Column(
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
            const Flexible(
              child: Text(
                'All Caught Up!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'No active orders right now. Ready for fresh laundry?',
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text(
                'Request Laundry Service',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
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
                  final activeOrder = _recentOrders.cast<LaundryOrder?>().firstWhere(
                    (o) =>
                        o != null &&
                        (o.status == OrderStatus.out_for_delivery ||
                            o.status == OrderStatus.pending_pickup),
                    orElse: () => null,
                  );
                  if (activeOrder != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OrderDeliveryTrackingScreen(
                          orderId: activeOrder.id,
                        ),
                      ),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CustomerOrdersScreen(),
                      ),
                    );
                  }
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
            width: double.infinity,
            padding: const EdgeInsets.all(36),
            decoration: AppStyles.cardDecoration,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
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
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                decoration: AppStyles.cardDecoration,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.lightBlue.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.local_laundry_service_outlined,
                        size: 36,
                        color: AppTheme.accentBlue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No recent orders',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap to request your first laundry service',
                      style: TextStyle(fontSize: 13, color: AppTheme.textLight),
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
    final description = order.customerDescription?.trim();
    final hasDescription = description != null && description.isNotEmpty;

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
            width: double.infinity,
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
                            order.displayNumber,
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
                if (hasDescription || order.laundryPhotoUrls?.isNotEmpty == true) ...[
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
                      if (hasDescription) ...[
                        const Icon(Icons.description_outlined, size: 15, color: AppTheme.textLight),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            description,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
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
  Color _getStatusColor(OrderStatus status) => AppTheme.statusColor(status);

  /// Get status icon for order status
  IconData _getStatusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_approval:
        return Icons.pending_outlined;
      case OrderStatus.pending_pickup:
        return Icons.two_wheeler;
      case OrderStatus.processing:
        return Icons.sync;
      case OrderStatus.ready:
        return Icons.sync;
      case OrderStatus.out_for_delivery:
        return Icons.local_shipping_outlined;
      case OrderStatus.completed:
        return Icons.check_circle;
      case OrderStatus.rejected:
        return Icons.cancel_outlined;
      case OrderStatus.cancelled:
        return Icons.block;
    }
  }

  /// Get status text for order status
  String _getStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_approval:
        return 'Pending Review';
      case OrderStatus.pending_pickup:
        return 'Waiting for Pickup';
      case OrderStatus.processing:
        return 'Processing';
      case OrderStatus.ready:
        return 'Processing';
      case OrderStatus.out_for_delivery:
        return 'Out for Delivery';
      case OrderStatus.completed:
        return 'Completed';
      case OrderStatus.rejected:
        return 'Declined';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }
}
