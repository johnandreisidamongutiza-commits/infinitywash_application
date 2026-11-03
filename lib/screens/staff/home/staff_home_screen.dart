import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_error.dart';
import '../../../models/order.dart';
import '../orders/orders_screen.dart';
import '../orders/create_order_flow.dart';
import '../orders/order_status_screen.dart';
import '../orders/rfid_checker_screen.dart';
import '../notifications/staff_notifications_screen.dart';
import '../../../services/order_service.dart';
import '../../../services/notification_service.dart';
import '../../../widgets/home_header.dart';
import '../../../services/profile_service.dart';
import '../../../services/profile_local_db.dart';
import '../../../services/supabase_service.dart';
import '../profile/options/account_details_screen.dart';

class StaffHomeScreen extends StatefulWidget {
  const StaffHomeScreen({super.key});

  @override
  State<StaffHomeScreen> createState() => _StaffHomeScreenState();
}

class _StaffHomeScreenState extends State<StaffHomeScreen> {
  final OrderService _orderService = OrderService();
  final NotificationService _notificationService = NotificationService();
  final ProfileService _profileService = ProfileService();
  TodayQueueCounts _queueCounts = const TodayQueueCounts();
  List<LaundryOrder> _processingOrdersList = [];
  int _unreadNotificationCount = 0;
  String? _avatarUrl;
  String? _localAvatarPath;
  bool _isLoading = true;
  String? _error;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadOrders();
    _loadUnreadCount();
    _startAutoRefresh();
    // One-time backlog cleanup: purge laundry photos from completed/cancelled orders to reclaim storage
    _orderService.purgeCompletedOrdersPhotos();
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

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  /// Start auto-refresh timer (45 seconds for staff dashboard)
  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 45),
      (timer) {
        if (mounted && !_isLoading) {
          _loadOrders();
          _loadUnreadCount();
        }
      },
    );
    print('✅ Started staff auto-refresh timer (45s interval)');
  }

  Future<void> _loadUnreadCount() async {
    final count = await _notificationService.getUnreadCount();
    if (mounted) {
      setState(() => _unreadNotificationCount = count);
    }
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _orderService.getTodayQueueCounts(),
        _orderService.fetchOrders(
          statuses: ['processing', 'ready'],
          limit: 10,
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _queueCounts = results[0] as TodayQueueCounts;
        _processingOrdersList = results[1] as List<LaundryOrder>;
        _isLoading = false;
      });

      print('✅ Loaded accurate queue counts: '
          'requests=${_queueCounts.requests}, '
          'processing=${_queueCounts.processing}, '
          'outForDelivery=${_queueCounts.outForDelivery}, '
          'completedToday=${_queueCounts.completedToday}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = mapErrorToMessage(e);
        _isLoading = false;
      });

      print('❌ Error loading staff home data: $e');
    }
  }

  List<LaundryOrder> get _processingOrders => _processingOrdersList;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadOrders,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: 30),
                _buildServiceRequestsButton(context),
                const SizedBox(height: 20),
                _buildTodayQueue(),
                const SizedBox(height: 30),
                _buildQuickActions(context),
                const SizedBox(height: 30),
                _buildCurrentlyProcessing(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return HomeHeader(
      title: 'Hi, Staff!',
      subtitle: 'Let\'s keep things moving today.',
      avatarUrl: _avatarUrl,
      localAvatarPath: _localAvatarPath,
      unreadCount: _unreadNotificationCount,
      onAvatarTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const AccountDetailsScreen(),
          ),
        );
        _loadUserProfile();
      },
      onNotificationTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const StaffNotificationsScreen()),
        ).then((_) {
          _loadUnreadCount();
          _loadUserProfile();
        });
      },
    );
  }

  Widget _buildServiceRequestsButton(BuildContext context) {
    final pendingCount = _queueCounts.requests;
    if (pendingCount == 0) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const OrdersScreen(initialTab: 0)),
        );
        if (mounted) _loadOrders();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.accentBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.online_prediction, color: AppTheme.accentBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'You have $pendingCount new service requests!',
                style: const TextStyle(color: AppTheme.accentBlue, fontWeight: FontWeight.bold),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.accentBlue),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayQueue() {
    final requestCount = _queueCounts.requests;
    final processingCount = _queueCounts.processing;
    final outForDeliveryCount = _queueCounts.outForDelivery;
    final completedCount = _queueCounts.completedToday;

    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: AppStyles.cardDecoration,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: AppStyles.cardDecoration,
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Error loading orders',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadOrders,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Today\'s Queue', style: AppTheme.lightTheme.textTheme.titleMedium),
              InkWell(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const OrdersScreen()),
                  );
                  if (mounted) _loadOrders();
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    'View All',
                    style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.accentBlue,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildQueueCard(
                  requestCount.toString(),
                  'Requests',
                  Icons.online_prediction,
                  AppTheme.lightBlue,
                  AppTheme.accentBlue,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const OrdersScreen(initialTab: 0)),
                    );
                    if (mounted) _loadOrders();
                  },
                ),
              ),
              Expanded(
                child: _buildQueueCard(
                  processingCount.toString(),
                  'Processing',
                  Icons.sync,
                  AppTheme.teamMemberOrange,
                  AppTheme.teamMemberIconOrange,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const OrdersScreen(initialTab: 1)),
                    );
                    if (mounted) _loadOrders();
                  },
                ),
              ),
              Expanded(
                child: _buildQueueCard(
                  outForDeliveryCount.toString(),
                  'Out for Delivery',
                  Icons.local_shipping_outlined,
                  const Color(0xFFE8F5E9),
                  Colors.green,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const OrdersScreen(initialTab: 1)),
                    );
                    if (mounted) _loadOrders();
                  },
                ),
              ),
              Expanded(
                child: _buildQueueCard(
                  completedCount.toString(),
                  'Completed',
                  Icons.verified_outlined,
                  const Color(0xFFE3F2FD),
                  const Color(0xFF1565C0),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const OrdersScreen(initialTab: 2)),
                    );
                    if (mounted) _loadOrders();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQueueCard(
    String count,
    String label,
    IconData icon,
    Color bgColor,
    Color iconColor, {
    VoidCallback? onTap,
  }) {
    final cardContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          count,
          style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 30,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
              fontSize: 9,
              height: 1.1,
            ),
          ),
        ),
      ],
    );

    if (onTap == null) return cardContent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: cardContent,
        ),
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
              child: _buildQuickActionCard(
                context,
                'New Walk-in\nOrder',
                Icons.add_shopping_cart_outlined,
                AppTheme.accentBlue,
                AppTheme.lightBlue,
                () async {
                  print('🔵 HOME: Opening create order flow...');
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CreateOrderFlow()),
                  );
                  print('🔵 HOME: Returned from create order flow, refreshing...');
                  await _loadOrders();
                  print('🔵 HOME: Orders refreshed!');
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildQuickActionCard(
                context,
                'RFID\nChecker',
                Icons.nfc,
                const Color(0xFF00897B),
                const Color(0xFFE0F2F1),
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RfidCheckerScreen()),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildQuickActionCard(
                context,
                'View All\nOrders',
                Icons.assignment_outlined,
                AppTheme.teamMemberIconOrange,
                AppTheme.teamMemberOrange,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const OrdersScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionCard(BuildContext context, String label, IconData icon, Color iconColor, Color bgColor, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
          decoration: AppStyles.cardDecoration,
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDark,
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentlyProcessing(BuildContext context) {
    final processingOrders = _processingOrders;
    final displayOrders = processingOrders.take(3).toList(); // Show only first 3 orders

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Currently Processing',
                style: AppTheme.lightTheme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const OrdersScreen()),
                );
              },
              child: const Text('See All', style: TextStyle(color: AppTheme.accentBlue)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (processingOrders.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
            decoration: AppStyles.cardDecoration,
            child: Column(
              children: [
                Icon(Icons.local_laundry_service_outlined, size: 48, color: AppTheme.textLight.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                Text(
                  'No laundry in the machines right now',
                  textAlign: TextAlign.center,
                  style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textLight.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          )
        else
          // Show only the first 3 orders
          ...displayOrders.map((order) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildProcessingCard(context, order),
          )),
      ],
    );
  }

  Widget _buildProcessingCard(BuildContext context, LaundryOrder order) {
    // Use processing_at timestamp if available, otherwise fall back to created_at
    final startTime = order.processingAt ?? order.createdAt;
    final currentTime = DateTime.now();
    
    // Calculate elapsed time
    final elapsed = currentTime.difference(startTime);
    
    // Debug logging to see what's happening
    print('🔍 Order ${order.displayNumber}:');
    print('  startTime: $startTime');
    print('  currentTime: $currentTime');
    print('  elapsed minutes: ${elapsed.inMinutes}');
    print('  elapsed seconds: ${elapsed.inSeconds}');
    
    String elapsedText;
    if (elapsed.inSeconds < 60) {
      elapsedText = '< 1m ago';
    } else if (elapsed.inHours > 0) {
      elapsedText = '${elapsed.inHours}h ${elapsed.inMinutes % 60}m ago';
    } else {
      elapsedText = '${elapsed.inMinutes}m ago';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => OrderStatusScreen(order: order)),
          );
          if (result == true) {
            await _loadOrders();
          }
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: AppStyles.cardDecoration.copyWith(
            border: Border.all(color: AppTheme.teamMemberIconOrange.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppTheme.teamMemberOrange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.sync, color: AppTheme.teamMemberIconOrange, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            order.displayNumber,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accentBlue,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '•',
                          style: TextStyle(color: AppTheme.textLight.withValues(alpha: 0.5)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            order.customerName,
                            style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (order.needsCheckIn)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Needs check-in',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
                            ),
                          )
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.scale_outlined, size: 14, color: AppTheme.textLight.withValues(alpha: 0.7)),
                              const SizedBox(width: 4),
                              Text(
                                order.weightDisplay,
                                style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                              ),
                            ],
                          ),
                        if (order.rfidTag != null) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.nfc_outlined, size: 14, color: AppTheme.accentBlue.withValues(alpha: 0.7)),
                              const SizedBox(width: 4),
                              Text(
                                order.rfidTag!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.accentBlue,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 14, color: AppTheme.textLight.withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                        Text(
                          'Started $elapsedText',
                          style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
                            fontSize: 11,
                            color: AppTheme.textLight.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textLight),
            ],
          ),
        ),
      ),
    );
  }
}
