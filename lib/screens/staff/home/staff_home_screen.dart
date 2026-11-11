import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
import '../../../widgets/skeleton_loading.dart';
import '../../../services/profile_service.dart';
import '../../../services/profile_local_db.dart';
import '../../../services/supabase_service.dart';
import '../../../services/data_change_monitor.dart';
import '../../../services/sound_service.dart';
import '../profile/options/account_details_screen.dart';

class StaffHomeScreen extends StatefulWidget {
  final bool isActive;

  const StaffHomeScreen({super.key, this.isActive = true});

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
  bool _isLoading = false;
  bool _ordersDirty = false;
  bool _hasLoadedOrders = false;
  String? _error;
  bool _hasCheckedInitialPendingOrders = false;

  @override
  void initState() {
    super.initState();
    DataChangeMonitor.instance.start();
    DataChangeMonitor.instance.ordersVersion.addListener(_onOrdersChanged);
    _loadUserProfile();
    if (widget.isActive) _loadOrders();
    _loadUnreadCount();
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
    DataChangeMonitor.instance.ordersVersion.removeListener(_onOrdersChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StaffHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive &&
        (!_hasLoadedOrders || _ordersDirty)) {
      _loadOrders(force: !_hasLoadedOrders);
    }
  }

  void _onOrdersChanged() {
    _ordersDirty = true;
    if (widget.isActive) _loadOrders(force: false);
  }

  Future<void> _loadUnreadCount() async {
    final count = await _notificationService.getUnreadCount();
    if (mounted) {
      setState(() => _unreadNotificationCount = count);
    }
  }

  Future<void> _loadOrders({bool force = true}) async {
    if (!force && !_ordersDirty && _hasLoadedOrders) return;
    if (_isLoading) {
      _ordersDirty = true;
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    _ordersDirty = false;

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
        _hasLoadedOrders = true;
      });

      if (!_hasCheckedInitialPendingOrders) {
        _hasCheckedInitialPendingOrders = true;
        if (_queueCounts.requests > 0) {
          SoundService.instance.playNotificationSound();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showPendingOrderModal(context, _queueCounts.requests);
            }
          });
        }
      }

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
        _hasLoadedOrders = false;
      });

      print('❌ Error loading staff home data: $e');
    }

    if (_ordersDirty && widget.isActive) _loadOrders(force: false);
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

  Future<void> _showPendingOrderModal(BuildContext context, int count) async {
    final title = count == 1 ? 'New Order Request' : 'New Order Requests';
    final countLabel = count == 1 ? '1 New' : '$count New';
    final message = count == 1
        ? 'There is 1 new pending order request waiting for review.'
        : 'There are $count new pending order requests waiting for review.';

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(22.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.assignment_late_outlined,
                      color: AppTheme.primaryBlue,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.lexend(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.lightBlue,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            countLabel,
                            style: GoogleFonts.lexend(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accentBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(
                      Icons.close,
                      color: AppTheme.textLight,
                      size: 20,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.softGray,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.borderGray.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: AppTheme.accentBlue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message,
                        style: GoogleFonts.lexend(
                          fontSize: 13,
                          color: AppTheme.textDark,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.textLight,
                          side: const BorderSide(color: AppTheme.borderGray),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Later',
                          style: GoogleFonts.lexend(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const OrdersScreen(initialTab: 0),
                            ),
                          ).then((_) {
                            if (mounted) _loadOrders();
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Review Now',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.lexend(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
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
          color: AppTheme.primaryBlue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.online_prediction, color: AppTheme.primaryBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'You have $pendingCount new service requests!',
                style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.primaryBlue),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Today\'s Queue', style: AppTheme.lightTheme.textTheme.titleMedium),
            const SizedBox(height: 20),
            SkeletonShimmer(
              child: Row(
                children: List.generate(
                  4,
                  (index) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: index == 3 ? 0 : 8),
                      child: Column(
                        children: const [
                          SkeletonBlock(width: 45, height: 45, borderRadius: 24),
                          SizedBox(height: 8),
                          SkeletonBlock(width: 30, height: 18),
                          SizedBox(height: 7),
                          SkeletonBlock(width: 52, height: 11),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
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
                  AppTheme.primaryBlue,
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
                AppTheme.primaryBlue,
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
                'Loyalty Card\nChecker',
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
                              color: AppTheme.primaryBlue,
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
                              Icon(Icons.nfc_outlined, size: 14, color: AppTheme.primaryBlue.withValues(alpha: 0.7)),
                              const SizedBox(width: 4),
                              Text(
                                order.rfidTag!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.primaryBlue,
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
