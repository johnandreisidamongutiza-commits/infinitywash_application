import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_error.dart';
import '../../../widgets/top_notification.dart';
import '../../../models/order.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/service_request_service.dart';
import '../../../services/customer_service.dart';
import '../../../services/feedback_service.dart';
import '../../../services/payment_service.dart';
import '../../shared/gcash_qr_payment_screen.dart';
import 'request_service_flow.dart';
import 'customer_order_details_screen.dart';
import '../chats/customer_chat_detail_screen.dart';

class CustomerOrdersScreen extends StatefulWidget {
  const CustomerOrdersScreen({super.key});

  @override
  State<CustomerOrdersScreen> createState() => _CustomerOrdersScreenState();
}

class _CustomerOrdersScreenState extends State<CustomerOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ServiceRequestService _serviceRequestService = ServiceRequestService();
  final CustomerService _customerService = CustomerService();
  final FeedbackService _feedbackService = FeedbackService();

  // Loading and data state
  bool _isLoading = false;
  List<LaundryOrder> _customerOrders = [];
  String? _errorMessage;

  // Feedback cache: orderId -> hasFeedback
  final Map<String, bool> _feedbackStatus = {};

  // Auto-refresh timer
  Timer? _autoRefreshTimer;

  // Search state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ─────────────────────────────────────────────────────────────────────────
  // Filtered getters
  // ─────────────────────────────────────────────────────────────────────────
  List<LaundryOrder> get _allRequestOrders => _customerOrders
      .where((o) => o.status == OrderStatus.pending_approval)
      .toList();

  List<LaundryOrder> get _allActiveOrders => _customerOrders
      .where((o) =>
          o.status == OrderStatus.pending_pickup ||
          o.status == OrderStatus.processing ||
          o.status == OrderStatus.ready ||
          o.status == OrderStatus.out_for_delivery)
      .toList();

  List<LaundryOrder> get _allHistoryOrders => _customerOrders
      .where((o) =>
          o.status == OrderStatus.completed ||
          o.status == OrderStatus.rejected ||
          o.status == OrderStatus.cancelled)
      .toList();

  bool _matchesSearch(LaundryOrder order) {
    if (_searchQuery.trim().isEmpty) return true;
    final q = _searchQuery.trim().toLowerCase();

    // 1. Order & Request IDs
    if (order.displayNumber.toLowerCase().contains(q)) return true;
    if (order.orderNumber != null &&
        order.orderNumber!.toLowerCase().contains(q)) {
      return true;
    }
    if (order.id.toLowerCase().contains(q)) return true;

    // 2. Service / Category names & load descriptions
    for (final load in order.loads) {
      if (load.category.toLowerCase().contains(q)) return true;
      if (load.description.toLowerCase().contains(q)) return true;
      if (load.notes != null && load.notes!.toLowerCase().contains(q)) return true;
    }

    // 3. Status label
    if (_statusLabel(order.status).toLowerCase().contains(q)) return true;

    // 4. Customer description, notes, instructions, delivery info
    if (order.customerDescription != null &&
        order.customerDescription!.toLowerCase().contains(q)) {
      return true;
    }
    if (order.instructions != null &&
        order.instructions!.toLowerCase().contains(q)) {
      return true;
    }
    if (order.deliveryAddress != null &&
        order.deliveryAddress!.toLowerCase().contains(q)) {
      return true;
    }
    if (order.deliveryLandmark != null &&
        order.deliveryLandmark!.toLowerCase().contains(q)) {
      return true;
    }
    if (order.paymentPreference != null &&
        order.paymentPreference!.toLowerCase().contains(q)) {
      return true;
    }
    if (order.paymentMethod != null &&
        order.paymentMethod!.toLowerCase().contains(q)) {
      return true;
    }

    return false;
  }

  List<LaundryOrder> get _requestOrders =>
      _allRequestOrders.where(_matchesSearch).toList();

  List<LaundryOrder> get _activeOrders =>
      _allActiveOrders.where(_matchesSearch).toList();

  List<LaundryOrder> get _historyOrders =>
      _allHistoryOrders.where(_matchesSearch).toList();

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
    _loadCustomerOrders();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Business Logic
  // ─────────────────────────────────────────────────────────────────────────

  /// Start auto-refresh timer (60 seconds for order list)
  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (timer) {
        if (mounted && !_isLoading) {
          _loadCustomerOrders();
        }
      },
    );
    print('✅ Started auto-refresh timer (60s interval)');
  }

  /// Load customer orders from database
  Future<void> _loadCustomerOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final customerId =
          await _customerService.getCurrentAuthenticatedCustomerId();
      final orders =
          await _serviceRequestService.getOrdersByCustomerId(customerId);
      await _loadFeedbackStatus(orders);

      if (!mounted) return;
      setState(() {
        _customerOrders = orders;
        _isLoading = false;
      });
      print('✅ Loaded ${orders.length} customer orders');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load orders: ${e.toString()}';
      });
      print('❌ Error loading customer orders: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = mapErrorToMessage(e);
      });
    }
  }

  /// Load feedback status for orders
  Future<void> _loadFeedbackStatus(List<LaundryOrder> orders) async {
    final completedOrders =
        orders.where((o) => o.status == OrderStatus.completed);
    for (final order in completedOrders) {
      try {
        final feedback = await _feedbackService.getFeedbackForOrder(order.id);
        _feedbackStatus[order.id] = feedback != null;
      } catch (e) {
        print('⚠️ Error loading feedback for ${order.id}: $e');
        _feedbackStatus[order.id] = false;
      }
    }
  }

  /// Opens the admin-uploaded GCash QR, lets the customer capture/upload
  /// the payment receipt, then records the payment.
  Future<void> _payWithGcash(LaundryOrder order, double amount) async {
    final receipt = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (context) => GcashQrPaymentScreen(
          title: 'Pay with GCash',
          orderLabel: order.displayNumber,
          amount: amount,
          customerName: order.customerName,
        ),
      ),
    );
    if (receipt == null || !mounted) return;

    // Fail fast with a clear message when offline instead of a cryptic
    // upload failure dialog.
    if (!await ConnectivityService.instance.checkNow()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No internet connection. Reconnect to submit your payment.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Uploading receipt...'),
          ],
        ),
      ),
    );

    try {
      await PaymentService().submitGcashPayment(
        orderId: order.id,
        amount: amount,
        receiptFile: receipt,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Receipt Uploaded',
                  style: GoogleFonts.lexend(fontSize: 18),
                ),
              ),
            ],
          ),
          content: Text(
            'Your GCash payment is marked as PAID. It is now pending verification by our admin team.',
            style: GoogleFonts.lexend(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Done', style: GoogleFonts.lexend()),
            ),
          ],
        ),
      );

      await _loadCustomerOrders();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      print('❌ GCash payment failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment could not be saved. ${mapErrorToMessage(e)}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _payWithGcash(order, amount),
          ),
        ),
      );
    }
  }

  /// Cancel an order
  Future<void> _cancelOrder(String orderId) async {
    try {
      await _serviceRequestService.cancelOrder(orderId);

      if (mounted) {
        showTopNotification(
          context,
          message: 'Request cancelled successfully',
          icon: Icons.check_circle,
          backgroundColor: Colors.green,
        );
      }
      await _loadCustomerOrders();
    } catch (e) {
      print('❌ Error cancelling order: $e');
      if (mounted) {
        showTopNotification(
          context,
          message: mapErrorToMessage(e),
          icon: Icons.error,
          backgroundColor: Colors.red,
        );
      }
    }
  }

  /// Get payment method display text
  String _getPaymentMethodDisplay(LaundryOrder order) {
    if (order.paymentStatus == PaymentStatus.paid &&
        order.paymentMethod != null) {
      return order.paymentMethod!;
    }
    if (order.paymentPreference != null &&
        order.paymentPreference!.isNotEmpty) {
      return order.paymentPreference!;
    }
    return 'GCash';
  }

  /// Get pay button text
  String _getPayButtonText(LaundryOrder order, double amount) {
    final preference = order.paymentPreference ?? 'GCash';
    final amountStr = '₱${amount.toStringAsFixed(2)}';
    if (preference == 'Cash on Delivery') {
      return 'Confirm Cash on Delivery ($amountStr)';
    } else if (preference == 'GCash') {
      return 'Pay $amountStr via GCash';
    } else {
      return 'Pay $amountStr via $preference';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────
  String _timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}/${date.year}';
  }

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_approval:
        return Colors.orange;
      case OrderStatus.pending_pickup:
        return Colors.orange;
      case OrderStatus.processing:
        return AppTheme.accentBlue;
      case OrderStatus.ready:
        return const Color(0xFF43A047);
      case OrderStatus.out_for_delivery:
        return const Color(0xFF7B1FA2);
      case OrderStatus.completed:
        return const Color(0xFF43A047);
      case OrderStatus.rejected:
        return AppTheme.errorRed;
      case OrderStatus.cancelled:
        return AppTheme.textLight;
    }
  }

  String _statusLabel(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_approval:
        return 'Pending';
      case OrderStatus.pending_pickup:
        return 'Pickup';
      case OrderStatus.processing:
        return 'Processing';
      case OrderStatus.ready:
        return 'Ready';
      case OrderStatus.out_for_delivery:
        return 'Delivering';
      case OrderStatus.completed:
        return 'Completed';
      case OrderStatus.rejected:
        return 'Rejected';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  IconData _statusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_approval:
        return Icons.schedule;
      case OrderStatus.pending_pickup:
        return Icons.local_shipping_outlined;
      case OrderStatus.processing:
        return Icons.local_laundry_service_outlined;
      case OrderStatus.ready:
        return Icons.check_circle_outline;
      case OrderStatus.out_for_delivery:
        return Icons.delivery_dining;
      case OrderStatus.completed:
        return Icons.task_alt;
      case OrderStatus.rejected:
        return Icons.cancel_outlined;
      case OrderStatus.cancelled:
        return Icons.block;
    }
  }

  Color _getLoadStatusColor(LoadStatus? status) {
    if (status == null) return AppTheme.textLight;
    switch (status) {
      case LoadStatus.queued:
        return AppTheme.textLight;
      case LoadStatus.washing:
        return Colors.blue;
      case LoadStatus.drying:
        return Colors.orange;
      case LoadStatus.folded:
        return Colors.green;
    }
  }

  String _getLoadStatusText(LoadStatus? status) {
    if (status == null) return 'Queued';
    switch (status) {
      case LoadStatus.queued:
        return 'Queued';
      case LoadStatus.washing:
        return 'Washing';
      case LoadStatus.drying:
        return 'Drying';
      case LoadStatus.folded:
        return 'Folded';
    }
  }

  int _progressStepIndex(OrderStatus status) {
    switch (status) {
      case OrderStatus.processing:
      case OrderStatus.ready:
      case OrderStatus.out_for_delivery:
        return 1;
      case OrderStatus.completed:
        return 2;
      default:
        return 0;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.softGray,
      appBar: AppBar(
        title: Text(
          'My Orders',
          style: GoogleFonts.lexend(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.textDark,
          ),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_allActiveOrders.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(
                  Icons.support_agent_rounded,
                  color: AppTheme.textDark,
                ),
                tooltip: 'Need help?',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CustomerChatDetailScreen(
                        recipientName: 'InfinityWash Support',
                        recipientRole: 'Customer Support Helpdesk',
                        recipientType: ChatRecipientType.support,
                        orderId: (_activeOrders.isNotEmpty ? _activeOrders : _allActiveOrders).first.displayNumber,
                        phoneNumber: '0912-345-6789',
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            margin: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppTheme.softGray,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TabBar(
              controller: _tabController,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              indicator: BoxDecoration(
                color: AppTheme.accentBlue,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentBlue.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.textLight,
              labelStyle: GoogleFonts.lexend(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              unselectedLabelStyle: GoogleFonts.lexend(fontSize: 13),
              dividerHeight: 0,
              tabs: [
                Tab(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Requests'),
                        if (_requestOrders.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.errorRed,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_requestOrders.length}',
                              style: GoogleFonts.lexend(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Tab(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Active'),
                        if (_activeOrders.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF43A047),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_activeOrders.length}',
                              style: GoogleFonts.lexend(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const Tab(text: 'History'),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                RefreshIndicator(
                  color: AppTheme.accentBlue,
                  onRefresh: _loadCustomerOrders,
                  child: _buildRequestsTab(),
                ),
                RefreshIndicator(
                  color: AppTheme.accentBlue,
                  onRefresh: _loadCustomerOrders,
                  child: _buildActiveTab(),
                ),
                RefreshIndicator(
                  color: AppTheme.accentBlue,
                  onRefresh: _loadCustomerOrders,
                  child: _buildHistoryTab(),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const RequestServiceFlow()),
          );
          if (result == true) {
            _tabController.animateTo(0); // Switch to Requests tab
            _loadCustomerOrders();
          }
        },
        backgroundColor: AppTheme.accentBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Request Service',
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REQUESTS TAB
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildRequestsTab() {
    if (_isLoading && _customerOrders.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          color: AppTheme.accentBlue,
          strokeWidth: 2.5,
        ),
      );
    }

    if (_errorMessage != null && _customerOrders.isEmpty) {
      return _buildErrorState();
    }

    if (_requestOrders.isEmpty) {
      if (_searchQuery.trim().isNotEmpty && _allRequestOrders.isNotEmpty) {
        return _buildEmptyState(
          icon: Icons.search_off_rounded,
          title: 'No matching requests',
          subtitle: 'No requests matched "$_searchQuery".',
          actionLabel: 'Clear Search',
          onAction: () {
            setState(() {
              _searchController.clear();
              _searchQuery = '';
            });
          },
        );
      }
      return _buildEmptyState(
        icon: Icons.mark_email_unread_outlined,
        title: 'No pending requests',
        subtitle:
            'Your laundry requests awaiting review will appear here.\nTap "Request Service" to get started.',
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      itemCount: _requestOrders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildRequestCard(_requestOrders[index]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVE TAB
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildActiveTab() {
    if (_isLoading && _customerOrders.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          color: AppTheme.accentBlue,
          strokeWidth: 2.5,
        ),
      );
    }

    if (_errorMessage != null && _customerOrders.isEmpty) {
      return _buildErrorState();
    }

    if (_activeOrders.isEmpty) {
      if (_searchQuery.trim().isNotEmpty && _allActiveOrders.isNotEmpty) {
        return _buildEmptyState(
          icon: Icons.search_off_rounded,
          title: 'No matching active orders',
          subtitle: 'No active orders matched "$_searchQuery".',
          actionLabel: 'Clear Search',
          onAction: () {
            setState(() {
              _searchController.clear();
              _searchQuery = '';
            });
          },
        );
      }
      return _buildEmptyState(
        icon: Icons.local_laundry_service_outlined,
        title: 'No active orders',
        subtitle: 'Orders in progress will appear here.',
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      itemCount: _activeOrders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildActiveCard(_activeOrders[index]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HISTORY TAB
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHistoryTab() {
    if (_isLoading && _customerOrders.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          color: AppTheme.accentBlue,
          strokeWidth: 2.5,
        ),
      );
    }

    if (_errorMessage != null && _customerOrders.isEmpty) {
      return _buildErrorState();
    }

    if (_historyOrders.isEmpty) {
      if (_searchQuery.trim().isNotEmpty && _allHistoryOrders.isNotEmpty) {
        return _buildEmptyState(
          icon: Icons.search_off_rounded,
          title: 'No matching order history',
          subtitle: 'No orders in history matched "$_searchQuery".',
          actionLabel: 'Clear Search',
          onAction: () {
            setState(() {
              _searchController.clear();
              _searchQuery = '';
            });
          },
        );
      }
      return _buildEmptyState(
        icon: Icons.history_rounded,
        title: 'No order history',
        subtitle: 'Your completed orders will show up here.',
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      itemCount: _historyOrders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) =>
          _buildHistoryCard(_historyOrders[index]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REQUEST CARD — pending_approval orders
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildRequestCard(LaundryOrder order) {
    final hasPhotos =
        order.laundryPhotoUrls != null && order.laundryPhotoUrls!.isNotEmpty;
    final photoCount = order.laundryPhotoUrls?.length ?? 0;
    final isRiderPickup =
        order.collectionMethod == CollectionMethod.riderPickup;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
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
                builder: (context) =>
                    CustomerOrderDetailsScreen(order: order),
              ),
            );
            if (result == true) _loadCustomerOrders();
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top accent bar ──
              Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.orange.withValues(alpha: 0.8),
                      Colors.amber.withValues(alpha: 0.6),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header row: order number + badges + time ──
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            order.displayNumber,
                            style: GoogleFonts.lexend(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryBlue,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildChip(
                          label: isRiderPickup
                              ? 'RIDER PICKUP'
                              : 'WALK-IN',
                          color: isRiderPickup
                              ? AppTheme.accentBlue
                              : const Color(0xFF26A69A),
                          icon: isRiderPickup
                              ? Icons.delivery_dining
                              : Icons.storefront_outlined,
                        ),
                        const SizedBox(width: 5),
                        _buildChip(
                          label: 'PENDING',
                          color: Colors.orange,
                          icon: Icons.schedule,
                        ),
                        const Spacer(),
                        Text(
                          _timeAgo(order.createdAt),
                          style: GoogleFonts.lexend(
                            fontSize: 11,
                            color: AppTheme.textLight,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // ── Info banner ──
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color:
                            AppTheme.teamMemberOrange.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.teamMemberIconOrange
                              .withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16,
                              color: AppTheme.teamMemberIconOrange),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your request is being reviewed by our staff',
                              style: GoogleFonts.lexend(
                                fontSize: 11,
                                color: AppTheme.textDark,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Address ──
                    if (order.deliveryAddress != null &&
                        order.deliveryAddress!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 15,
                            color: AppTheme.textLight.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              order.deliveryAddress!,
                              style: GoogleFonts.lexend(
                                fontSize: 12,
                                color: AppTheme.textLight,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],

                    // ── Photos indicator ──
                    if (hasPhotos) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  _CustomerRequestPhotoViewer(
                                photoUrls: order.laundryPhotoUrls!,
                                initialIndex: 0,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color:
                                AppTheme.accentBlue.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.photo_library_outlined,
                                size: 14,
                                color: AppTheme.accentBlue,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$photoCount photo${photoCount > 1 ? 's' : ''} attached',
                                style: GoogleFonts.lexend(
                                  fontSize: 11,
                                  color: AppTheme.accentBlue,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // ── Customer notes preview ──
                    if (order.customerDescription != null &&
                        order.customerDescription!.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.notes_outlined,
                            size: 15,
                            color: AppTheme.textLight.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              order.customerDescription!,
                              style: GoogleFonts.lexend(
                                fontSize: 12,
                                color: AppTheme.textLight,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 14),

                    // ── Cancel button ──
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                              title: Text('Cancel Request?',
                                  style: GoogleFonts.lexend(
                                      fontWeight: FontWeight.w600)),
                              content: Text(
                                'Are you sure you want to cancel this service request? This action cannot be undone.',
                                style: GoogleFonts.lexend(fontSize: 14),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text('Keep Request',
                                      style: GoogleFonts.lexend()),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  style: TextButton.styleFrom(
                                      foregroundColor: Colors.red),
                                  child: Text('Cancel Request',
                                      style: GoogleFonts.lexend(
                                          fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await _cancelOrder(order.id);
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.errorRed,
                          side: BorderSide(
                              color:
                                  AppTheme.errorRed.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Cancel Request',
                              style: GoogleFonts.lexend(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.close_rounded, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVE CARD — pending_pickup, processing, ready, out_for_delivery
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildActiveCard(LaundryOrder order) {
    final color = _statusColor(order.status);
    final needsPayment = order.paymentStatus == PaymentStatus.unpaid;
    final double displayPrice =
        order.totalAmount != null && order.totalAmount! > 0
            ? order.totalAmount!
            : order.totalWeight * 30.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
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
                builder: (context) =>
                    CustomerOrderDetailsScreen(order: order),
              ),
            );
            if (result == true) _loadCustomerOrders();
          },
          child: IntrinsicHeight(
            child: Row(
              children: [
                // ── Left status accent ──
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(16),
                    ),
                  ),
                ),
                // ── Card content ──
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Header: status icon + order# + badge + time ──
                        Row(
                          children: [
                            Icon(
                              _statusIcon(order.status),
                              size: 16,
                              color: color,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                order.displayNumber,
                                style: GoogleFonts.lexend(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primaryBlue,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildStatusBadge(order.status),
                            const Spacer(),
                            Text(
                              _timeAgo(order.createdAt),
                              style: GoogleFonts.lexend(
                                fontSize: 11,
                                color: AppTheme.textLight,
                              ),
                            ),
                          ],
                        ),

                        // ── Action banner (pending pickup / out for delivery) ──
                        if (order.status == OrderStatus.pending_pickup) ...[
                          const SizedBox(height: 10),
                          _buildActionBanner(
                            icon: Icons.local_shipping_outlined,
                            text: 'Waiting for rider to pick up your laundry',
                            color: Colors.orange,
                          ),
                        ],
                        if (order.status == OrderStatus.out_for_delivery) ...[
                          const SizedBox(height: 10),
                          _buildActionBanner(
                            icon: Icons.delivery_dining,
                            text: 'Your laundry is on the way!',
                            color: const Color(0xFF7B1FA2),
                          ),
                        ],

                        const SizedBox(height: 12),

                        // ── Service + weight row ──
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.local_laundry_service_outlined,
                                size: 16,
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Wash, Dry & Fold',
                                    style: GoogleFonts.lexend(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    order.totalWeight > 0
                                        ? '${order.loads.length} load${order.loads.length != 1 ? 's' : ''} • ${order.totalWeight.toStringAsFixed(1)} kg'
                                        : order.needsCheckIn
                                            ? 'Needs check-in'
                                            : '${order.loads.length} load${order.loads.length != 1 ? 's' : ''}',
                                    style: GoogleFonts.lexend(
                                      fontSize: 12,
                                      color: order.needsCheckIn
                                          ? Colors.orange
                                          : AppTheme.textLight,
                                      fontWeight: order.needsCheckIn
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color:
                                  AppTheme.textLight.withValues(alpha: 0.4),
                              size: 22,
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // ── Compact progress tracker ──
                        _buildCompactProgressTracker(order.status),

                        // ── Payment banner (GCash unpaid) ──
                        if (needsPayment &&
                            order.totalWeight > 0 &&
                            order.paymentPreference != 'Cash on Delivery') ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.lightBlue,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: AppTheme.accentBlue
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.receipt_outlined,
                                    color: AppTheme.accentBlue, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_getPaymentMethodDisplay(order)} Due',
                                        style: GoogleFonts.lexend(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.accentBlue,
                                        ),
                                      ),
                                      Text(
                                        '₱${displayPrice.toStringAsFixed(2)}',
                                        style: GoogleFonts.lexend(
                                          fontSize: 11,
                                          color: AppTheme.textDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  height: 32,
                                  child: ElevatedButton(
                                    onPressed: () =>
                                        _payWithGcash(order, displayPrice),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.accentBlue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Text(
                                      'Pay Now',
                                      style: GoogleFonts.lexend(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // ── COD banner ──
                        if (needsPayment &&
                            order.totalWeight > 0 &&
                            order.paymentPreference ==
                                'Cash on Delivery') ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color:
                                      Colors.green.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.payments,
                                    color: Colors.green, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Cash on Delivery',
                                        style: GoogleFonts.lexend(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.green,
                                        ),
                                      ),
                                      Text(
                                        'Prepare ₱${displayPrice.toStringAsFixed(2)}',
                                        style: GoogleFonts.lexend(
                                          fontSize: 11,
                                          color: AppTheme.textDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'COD',
                                    style: GoogleFonts.lexend(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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

  // ─────────────────────────────────────────────────────────────────────────
  // HISTORY CARD — completed, rejected, cancelled
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHistoryCard(LaundryOrder order) {
    final color = _statusColor(order.status);
    final hasFeedback = _feedbackStatus[order.id] ?? false;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
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
                builder: (context) =>
                    CustomerOrderDetailsScreen(order: order),
              ),
            );
            if (result == true) _loadCustomerOrders();
          },
          child: IntrinsicHeight(
            child: Row(
              children: [
                // ── Left status accent ──
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(16),
                    ),
                  ),
                ),
                // ── Card content ──
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Header: status icon + order# + badge + time ──
                        Row(
                          children: [
                            Icon(
                              _statusIcon(order.status),
                              size: 16,
                              color: color,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                order.displayNumber,
                                style: GoogleFonts.lexend(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primaryBlue,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildStatusBadge(order.status),
                            const Spacer(),
                            Text(
                              _timeAgo(order.createdAt),
                              style: GoogleFonts.lexend(
                                fontSize: 11,
                                color: AppTheme.textLight,
                              ),
                            ),
                          ],
                        ),

                        // ── Rejection reason ──
                        if (order.status == OrderStatus.rejected) ...[
                          const SizedBox(height: 10),
                          _buildActionBanner(
                            icon: Icons.cancel_outlined,
                            text: order.rejectionReason != null
                                ? _rejectionReasonText(
                                    order.rejectionReason!)
                                : 'Your request was rejected',
                            color: AppTheme.errorRed,
                          ),
                        ],

                        const SizedBox(height: 12),

                        // ── Service + weight row ──
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.local_laundry_service_outlined,
                                size: 16,
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Wash, Dry & Fold',
                                    style: GoogleFonts.lexend(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    order.totalWeight > 0
                                        ? '${order.totalWeight.toStringAsFixed(1)} kg • ₱${(order.totalAmount ?? order.totalWeight * 30.0).toStringAsFixed(2)}'
                                        : _statusLabel(order.status),
                                    style: GoogleFonts.lexend(
                                      fontSize: 12,
                                      color: AppTheme.textLight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // ── Feedback badge ──
                            if (order.status == OrderStatus.completed)
                              hasFeedback
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFD700)
                                            .withValues(alpha: 0.15),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.star,
                                              size: 12,
                                              color: Color(0xFFFFD700)),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Rated',
                                            style: GoogleFonts.lexend(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  const Color(0xFFB8860B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.accentBlue
                                            .withValues(alpha: 0.08),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.rate_review_outlined,
                                              size: 12,
                                              color: AppTheme.accentBlue),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Rate',
                                            style: GoogleFonts.lexend(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.accentBlue,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right_rounded,
                              color:
                                  AppTheme.textLight.withValues(alpha: 0.4),
                              size: 22,
                            ),
                          ],
                        ),
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

  String _rejectionReasonText(String reason) {
    switch (reason) {
      case 'out_of_service_area':
        return 'Out of service area';
      case 'capacity_full':
        return 'Capacity full';
      case 'invalid_items':
        return 'Invalid items';
      default:
        return reason;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHARED WIDGETS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.softGray,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (val) {
            setState(() {
              _searchQuery = val;
            });
          },
          style: GoogleFonts.lexend(
            fontSize: 14,
            color: AppTheme.textDark,
          ),
          decoration: InputDecoration(
            hintText: 'Search by order #, service, or notes...',
            hintStyle: GoogleFonts.lexend(
              fontSize: 13,
              color: AppTheme.textLight.withValues(alpha: 0.7),
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: AppTheme.textLight,
              size: 20,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.cancel_rounded,
                      color: AppTheme.textLight,
                      size: 18,
                    ),
                    splashRadius: 18,
                    onPressed: () {
                      setState(() {
                        _searchController.clear();
                        _searchQuery = '';
                      });
                    },
                  )
                : null,
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppTheme.accentBlue.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 48,
                      color: AppTheme.accentBlue.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    style: GoogleFonts.lexend(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lexend(
                      fontSize: 13,
                      color: AppTheme.textLight,
                    ),
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: onAction,
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      label: Text(
                        actionLabel,
                        style: GoogleFonts.lexend(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.accentBlue,
                        side: const BorderSide(color: AppTheme.accentBlue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppTheme.errorRed.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.error_outline,
                      size: 48,
                      color: AppTheme.errorRed.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Something went wrong',
                    style: GoogleFonts.lexend(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage ?? 'Please try again.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lexend(
                      fontSize: 13,
                      color: AppTheme.textLight,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _loadCustomerOrders,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text('Retry',
                        style: GoogleFonts.lexend(
                            fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(OrderStatus status) {
    final color = _statusColor(status);
    final label = _statusLabel(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.lexend(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required Color color,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: GoogleFonts.lexend(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBanner({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.lexend(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactProgressTracker(OrderStatus status) {
    final steps = [
      {'label': 'Booked', 'icon': Icons.check_circle},
      {'label': 'Processing', 'icon': Icons.sync},
      {'label': 'Done', 'icon': Icons.check_circle},
    ];

    final currentStepIndex = _progressStepIndex(status);

    return SizedBox(
      height: 50,
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            _buildCompactProgressStep(
              label: steps[i]['label'] as String,
              icon: steps[i]['icon'] as IconData,
              isActive: i <= currentStepIndex,
              isCurrent: i == currentStepIndex,
            ),
            if (i < steps.length - 1)
              Container(
                width: 40,
                height: 2,
                margin:
                    const EdgeInsets.only(bottom: 14, left: 8, right: 8),
                color: i < currentStepIndex
                    ? AppTheme.accentBlue
                    : AppTheme.borderGray,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactProgressStep({
    required String label,
    required IconData icon,
    required bool isActive,
    required bool isCurrent,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive ? AppTheme.accentBlue : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? AppTheme.accentBlue : AppTheme.borderGray,
              width: 2,
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isActive ? Colors.white : AppTheme.textLight,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.lexend(
            fontSize: 9,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            color: isActive ? AppTheme.accentBlue : AppTheme.textLight,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Image helpers (preserved)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildThumbnailImage(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.photo, color: AppTheme.textLight, size: 32),
      );
    } else if (path.startsWith('data:image') ||
        (path.length > 100 &&
            !path.startsWith('/') &&
            !path.contains('\\'))) {
      try {
        final base64String =
            path.contains(',') ? path.split(',').last : path;
        final bytes = base64Decode(base64String.trim());
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.photo, color: AppTheme.textLight, size: 32),
        );
      } catch (e) {
        return const Icon(Icons.photo, color: AppTheme.textLight, size: 32);
      }
    } else {
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.photo, color: AppTheme.textLight, size: 32),
        );
      } else {
        return const Icon(Icons.photo, color: AppTheme.textLight, size: 32);
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Photo Viewer (preserved from original)
// ─────────────────────────────────────────────────────────────────────────────
class _CustomerRequestPhotoViewer extends StatefulWidget {
  final List<String> photoUrls;
  final int initialIndex;

  const _CustomerRequestPhotoViewer({
    required this.photoUrls,
    required this.initialIndex,
  });

  @override
  State<_CustomerRequestPhotoViewer> createState() =>
      _CustomerRequestPhotoViewerState();
}

class _CustomerRequestPhotoViewerState
    extends State<_CustomerRequestPhotoViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.8),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: Text(
          'Photo ${_currentIndex + 1} of ${widget.photoUrls.length}',
          style: GoogleFonts.lexend(color: Colors.white, fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.photoUrls.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          final path = widget.photoUrls[index];
          return Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: _buildFullImage(path),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFullImage(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
              child: CircularProgressIndicator(color: Colors.white));
        },
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image, color: Colors.white54, size: 48),
              SizedBox(height: 8),
              Text('Unable to load photo',
                  style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      );
    } else if (path.startsWith('data:image') ||
        (path.length > 100 &&
            !path.startsWith('/') &&
            !path.contains('\\'))) {
      try {
        final base64String =
            path.contains(',') ? path.split(',').last : path;
        final bytes = base64Decode(base64String.trim());
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Center(
            child:
                Icon(Icons.broken_image, color: Colors.white54, size: 48),
          ),
        );
      } catch (e) {
        return const Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
        );
      }
    } else {
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Center(
            child:
                Icon(Icons.broken_image, color: Colors.white54, size: 48),
          ),
        );
      } else {
        return const Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
        );
      }
    }
  }
}
