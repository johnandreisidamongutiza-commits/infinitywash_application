import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_error.dart';
import '../../../models/order.dart';
import '../../../services/rider_service.dart';
import 'rider_payment_process_screen.dart';

/// Dedicated Payment tab screen for Riders to view and collect payments
/// for pickup and delivery orders.
class RiderPaymentScreen extends StatefulWidget {
  final bool isActive;

  const RiderPaymentScreen({super.key, this.isActive = true});

  @override
  State<RiderPaymentScreen> createState() => RiderPaymentScreenState();
}

class RiderPaymentScreenState extends State<RiderPaymentScreen> {
  /// Page size for both payment tabs, matching the other list screens.
  static const int _kPageSize = 7;

  final RiderService _riderService = RiderService();
  bool _showPaid = false;
  String _searchQuery = '';

  // ── Unpaid tab (paginated) ──────────────────────────────────────────────
  final List<LaundryOrder> _unpaidOrders = [];
  int _unpaidOffset = 0;
  bool _unpaidHasMore = true;
  bool _unpaidLoading = false;
  bool _unpaidLoadingMore = false;
  bool _unpaidInitialized = false;
  final ScrollController _unpaidScroll = ScrollController();

  // ── Paid tab (paginated) ────────────────────────────────────────────────
  final List<LaundryOrder> _paidOrders = [];
  int _paidOffset = 0;
  bool _paidHasMore = true;
  bool _paidLoading = false;
  bool _paidLoadingMore = false;
  bool _paidInitialized = false;
  final ScrollController _paidScroll = ScrollController();

  // ── Tab badges (cover every row, not just the loaded page) ──────────────
  int _unpaidCount = 0;
  int _paidCount = 0;
  String _jobTypeFilter = 'all'; // 'all', 'pickup', 'delivery'
  int _unpaidPickupCount = 0;
  int _unpaidDeliveryCount = 0;
  int _paidPickupCount = 0;
  int _paidDeliveryCount = 0;

  @override
  void initState() {
    super.initState();
    // Attach scroll listeners for infinite pagination
    _unpaidScroll.addListener(() => _onScroll(_unpaidScroll, _loadMoreUnpaid));
    _paidScroll.addListener(() => _onScroll(_paidScroll, _loadMorePaid));

    // Only load immediately if this screen is already the active tab (e.g. the
    // app launched directly onto the Payment tab). If it starts offstage inside
    // IndexedStack, skip the load here — didUpdateWidget will trigger it the
    // moment isActive flips true, guaranteeing setState never runs mid-layout.
    if (widget.isActive) {
      _initUnpaid();
      _refreshCounts();
    }
  }

  @override
  void didUpdateWidget(covariant RiderPaymentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload every time the tab becomes active so fresh data is always shown.
    if (widget.isActive && !oldWidget.isActive) {
      _refreshAll();
    }
  }

  @override
  void dispose() {
    _unpaidScroll.dispose();
    _paidScroll.dispose();
    super.dispose();
  }

  void refreshOrders() {
    _refreshAll();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Scroll listener — triggers load-more when near bottom (200 px threshold)
  // ─────────────────────────────────────────────────────────────────────────
  void _onScroll(ScrollController ctrl, VoidCallback loadMore) {
    if (!ctrl.hasClients) return;
    final pos = ctrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      loadMore();
    }
  }

  void _selectTab(bool showPaid) {
    if (_showPaid == showPaid) return;
    setState(() => _showPaid = showPaid);
    // Lazy-load the Paid tab the first time it is opened.
    if (showPaid && !_paidInitialized) _initPaid();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UNPAID TAB
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _initUnpaid() async {
    if (_unpaidLoading) return;
    setState(() {
      _unpaidLoading = true;
      _unpaidInitialized = true;
      _unpaidOrders.clear();
      _unpaidOffset = 0;
      _unpaidHasMore = true;
    });
    await _fetchUnpaid(reset: true);
  }

  Future<void> _loadMoreUnpaid() async {
    if (_unpaidLoadingMore || !_unpaidHasMore || !_unpaidInitialized) return;
    setState(() => _unpaidLoadingMore = true);
    await _fetchUnpaid(reset: false);
  }

  Future<void> _fetchUnpaid({required bool reset}) async {
    try {
      final page = await _riderService.fetchRiderPaymentOrders(
        paymentStatus: 'unpaid',
        jobType: _jobTypeFilter == 'all' ? null : _jobTypeFilter,
        limit: _kPageSize,
        offset: _unpaidOffset,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _unpaidOrders.clear();
        _unpaidOrders.addAll(page);
        _unpaidHasMore = page.length == _kPageSize;
        _unpaidOffset += page.length;
        _unpaidLoading = false;
        _unpaidLoadingMore = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading rider unpaid orders: $e');
      if (!mounted) return;
      setState(() {
        _unpaidLoading = false;
        _unpaidLoadingMore = false;
      });
      _showError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PAID TAB
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _initPaid() async {
    if (_paidLoading) return;
    setState(() {
      _paidLoading = true;
      _paidInitialized = true;
      _paidOrders.clear();
      _paidOffset = 0;
      _paidHasMore = true;
    });
    await _fetchPaid(reset: true);
  }

  Future<void> _loadMorePaid() async {
    if (_paidLoadingMore || !_paidHasMore || !_paidInitialized) return;
    setState(() => _paidLoadingMore = true);
    await _fetchPaid(reset: false);
  }

  Future<void> _fetchPaid({required bool reset}) async {
    try {
      final page = await _riderService.fetchRiderPaymentOrders(
        paymentStatus: 'paid',
        jobType: _jobTypeFilter == 'all' ? null : _jobTypeFilter,
        limit: _kPageSize,
        offset: _paidOffset,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _paidOrders.clear();
        _paidOrders.addAll(page);
        _paidHasMore = page.length == _kPageSize;
        _paidOffset += page.length;
        _paidLoading = false;
        _paidLoadingMore = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading rider paid orders: $e');
      if (!mounted) return;
      setState(() {
        _paidLoading = false;
        _paidLoadingMore = false;
      });
      _showError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Counts & refresh
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _refreshCounts() async {
    try {
      final counts = await Future.wait([
        _riderService.fetchRiderPaymentOrderCount(paymentStatus: 'unpaid'),
        _riderService.fetchRiderPaymentOrderCount(paymentStatus: 'paid'),
        _riderService.fetchRiderPaymentOrderCount(
            paymentStatus: 'unpaid', jobType: 'pickup'),
        _riderService.fetchRiderPaymentOrderCount(
            paymentStatus: 'unpaid', jobType: 'delivery'),
        _riderService.fetchRiderPaymentOrderCount(
            paymentStatus: 'paid', jobType: 'pickup'),
        _riderService.fetchRiderPaymentOrderCount(
            paymentStatus: 'paid', jobType: 'delivery'),
      ]);
      if (!mounted) return;
      setState(() {
        _unpaidCount = counts[0];
        _paidCount = counts[1];
        _unpaidPickupCount = counts[2];
        _unpaidDeliveryCount = counts[3];
        _paidPickupCount = counts[4];
        _paidDeliveryCount = counts[5];
      });
    } catch (e) {
      // Badges are cosmetic — keep the last known values if the query fails.
      debugPrint('❌ Error loading rider payment counts: $e');
    }
  }

  /// Pull-to-refresh / refresh button / tab re-activation: reloads both tabs
  /// and the badges.
  Future<void> _refreshAll() async {
    await Future.wait([
      _initUnpaid(),
      if (_paidInitialized) _initPaid(),
      _refreshCounts(),
    ]);
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mapErrorToMessage(e)),
        backgroundColor: Colors.red,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Active tab accessors
  // ─────────────────────────────────────────────────────────────────────────
  List<LaundryOrder> get _activeOrders =>
      _showPaid ? _paidOrders : _unpaidOrders;

  bool get _activeLoading => _showPaid ? _paidLoading : _unpaidLoading;

  bool get _activeLoadingMore =>
      _showPaid ? _paidLoadingMore : _unpaidLoadingMore;

  bool get _activeHasMore => _showPaid ? _paidHasMore : _unpaidHasMore;

  ScrollController get _activeScroll => _showPaid ? _paidScroll : _unpaidScroll;

  bool _isDelivery(LaundryOrder order) {
    if (order.status == OrderStatus.pending_pickup) return false;
    return order.returnMethod == ReturnMethod.delivery;
  }

  /// Only free-text search is applied here; it covers the pages loaded so far
  /// (same convention as the other list screens).
  List<LaundryOrder> _getFilteredOrders() {
    var list = _activeOrders;

    if (_jobTypeFilter != 'all') {
      if (_jobTypeFilter == 'delivery') {
        list = list.where((o) => _isDelivery(o)).toList();
      } else if (_jobTypeFilter == 'pickup') {
        list = list.where((o) => !_isDelivery(o)).toList();
      }
    }

    if (_searchQuery.trim().isEmpty) return list;

    final q = _searchQuery.trim().toLowerCase();
    return list.where((order) {
      final name = order.customerName.toLowerCase();
      final number = order.displayNumber.toLowerCase();
      final phone = (order.customerPhone ?? '').toLowerCase();
      return name.contains(q) || number.contains(q) || phone.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final displayedOrders = _getFilteredOrders();
    final isSearching = _searchQuery.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Payments',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.accentBlue),
            tooltip: 'Refresh',
            onPressed: _refreshAll,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips & Search
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                // Filter Tabs (Unpaid vs Paid)
                Row(
                  children: [
                    Expanded(
                      child: _buildFilterTab(
                        title: 'Unpaid ($_unpaidCount)',
                        isSelected: !_showPaid,
                        isUnpaid: true,
                        onTap: () => _selectTab(false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildFilterTab(
                        title: 'Paid ($_paidCount)',
                        isSelected: _showPaid,
                        isUnpaid: false,
                        onTap: () => _selectTab(true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Search Input
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search by customer name or order #',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                    prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.textLight),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setState(() => _searchQuery = ''),
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey[100],
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                // Sub-filter chips below search bar
                const SizedBox(height: 12),
                _buildSubFilterBar(),
              ],
            ),
          ),

          // Orders List
          Expanded(
            child: _activeLoading && _activeOrders.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.accentBlue),
                  )
                : displayedOrders.isEmpty
                    ? RefreshIndicator(
                        onRefresh: _refreshAll,
                        child: ListView(
                          primary: false,
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            // ConstrainedBox, not SizedBox: a fixed height clips
                            // the empty state once the system font grows.
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight:
                                    MediaQuery.of(context).size.height * 0.45,
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _showPaid
                                          ? Icons.receipt_long_outlined
                                          : Icons.check_circle_outline,
                                      size: 64,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      isSearching
                                          ? 'No matching orders'
                                          : (_showPaid
                                              ? (_jobTypeFilter == 'pickup'
                                                  ? 'No paid pickup orders found'
                                                  : (_jobTypeFilter == 'delivery'
                                                      ? 'No paid delivery orders found'
                                                      : 'No paid orders found'))
                                              : (_jobTypeFilter == 'pickup'
                                                  ? 'No unpaid pickup orders found'
                                                  : (_jobTypeFilter == 'delivery'
                                                      ? 'No unpaid delivery orders found'
                                                      : 'No unpaid orders. All caught up!'))),
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (_jobTypeFilter != 'all' &&
                                        !isSearching) ...[
                                      const SizedBox(height: 12),
                                      TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _jobTypeFilter = 'all';
                                          });
                                          if (_showPaid) {
                                            _initPaid();
                                          } else {
                                            _initUnpaid();
                                          }
                                        },
                                        child: Text('Show All ${_showPaid ? 'Paid' : 'Unpaid'} Orders'),
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Text(
                                      'Pull down to refresh',
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _refreshAll,
                        child: ListView.separated(
                          controller: _activeScroll,
                          primary: false,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: isSearching
                              ? displayedOrders.length
                              : displayedOrders.length + 1,
                          separatorBuilder: (context, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            if (!isSearching &&
                                index == displayedOrders.length) {
                              return _buildPaginationFooter(
                                _activeLoadingMore,
                                _activeHasMore,
                              );
                            }
                            final order = displayedOrders[index];
                            return _buildOrderCard(order);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ─── Pagination Footer ──────────────────────────────────────────
  /// Shows a spinner while the next page is loading, or an end-of-list label
  /// once every page has been fetched.
  Widget _buildPaginationFooter(bool isLoadingMore, bool hasMore) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: isLoadingMore
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.accentBlue,
                ),
              )
            : hasMore
                ? const SizedBox.shrink()
                : Text(
                    'No more payments',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                  ),
      ),
    );
  }

  Widget _buildSubFilterBar() {
    final allCount = _showPaid ? _paidCount : _unpaidCount;
    final pickupCount = _showPaid ? _paidPickupCount : _unpaidPickupCount;
    final deliveryCount = _showPaid ? _paidDeliveryCount : _unpaidDeliveryCount;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildSubFilterChip(
            label: 'All',
            icon: Icons.all_inbox_rounded,
            value: 'all',
            count: allCount,
            color: AppTheme.accentBlue,
          ),
          const SizedBox(width: 8),
          _buildSubFilterChip(
            label: 'Pickups',
            icon: Icons.inventory_2_outlined,
            value: 'pickup',
            count: pickupCount,
            color: AppTheme.accentBlue,
          ),
          const SizedBox(width: 8),
          _buildSubFilterChip(
            label: 'Deliveries',
            icon: Icons.local_shipping_outlined,
            value: 'delivery',
            count: deliveryCount,
            color: Colors.purple.shade700,
          ),
        ],
      ),
    );
  }

  Widget _buildSubFilterChip({
    required String label,
    required IconData icon,
    required String value,
    required int count,
    required Color color,
  }) {
    final isSelected = _jobTypeFilter == value;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          if (_jobTypeFilter == value) return;
          setState(() {
            _jobTypeFilter = value;
          });
          if (_showPaid) {
            _initPaid();
          } else {
            _initUnpaid();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? color : AppTheme.softGray,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? color : Colors.black.withValues(alpha: 0.06),
              width: 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.28),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? Colors.white : color,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.lexend(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : AppTheme.textDark,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.25)
                        : color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.lexend(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : color,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterTab({
    required String title,
    required bool isSelected,
    required bool isUnpaid,
    required VoidCallback onTap,
  }) {
    final activeColor = isUnpaid ? AppTheme.accentBlue : Colors.green[700]!;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? activeColor : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  String _getJobStatusLabel(LaundryOrder order) {
    switch (order.status) {
      case OrderStatus.completed:
        return 'Job Completed';
      case OrderStatus.out_for_delivery:
        return 'Out for Delivery';
      case OrderStatus.ready:
        return 'Ready';
      case OrderStatus.pending_pickup:
        return 'Pending Pickup';
      case OrderStatus.processing:
        return 'Processing';
      default:
        return '';
    }
  }

  String _formatDateTime(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} $hour:$minute $period';
  }

  Future<void> _openPaymentProcess(LaundryOrder order, bool isDelivery) async {
    final paid = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => RiderPaymentProcessScreen(
          order: order,
          jobType: isDelivery ? 'delivery' : 'pickup',
        ),
      ),
    );

    if (paid == true) {
      // The order moved from Unpaid to Paid, so both tabs and the badges need
      // to be rebuilt.
      _refreshAll();
    }
  }

  void _showReceiptSheet(LaundryOrder order, double total) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: Colors.green, size: 48),
            ),
            const SizedBox(height: 12),
            const Text(
              'Payment Confirmed',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
            ),
            const SizedBox(height: 4),
            Text(
              'Order ${order.displayNumber}',
              style: const TextStyle(color: AppTheme.textLight, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  _receiptSheetRow('Customer', order.customerName),
                  _receiptSheetRow('Amount Paid', '₱${total.toStringAsFixed(2)}', isBold: true),
                  _receiptSheetRow('Payment Method', order.paymentMethod ?? 'Cash / GCash'),
                  if (order.paidAt != null)
                    _receiptSheetRow('Paid Date', _formatDateTime(order.paidAt!)),
                  if (order.deliveryAddress != null && order.deliveryAddress!.isNotEmpty)
                    _receiptSheetRow('Address', order.deliveryAddress!),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptSheetRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textLight)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: isBold ? AppTheme.accentBlue : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(LaundryOrder order) {
    final isDelivery = _isDelivery(order);
    final isPaid = order.paymentStatus == PaymentStatus.paid;
    final total = order.totalAmount ?? (order.basePrice > 0 ? order.basePrice : 170.0);
    final jobStatusLabel = _getJobStatusLabel(order);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (!isPaid) {
            _openPaymentProcess(order, isDelivery);
          } else {
            _showReceiptSheet(order, total);
          }
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPaid ? Colors.grey.shade200 : AppTheme.accentBlue.withValues(alpha: 0.25),
              width: isPaid ? 1 : 1.5,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Badges (Delivery/Pickup, Job status) & Price with chevron
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDelivery ? Colors.purple.shade50 : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isDelivery ? Icons.local_shipping_outlined : Icons.inventory_2_outlined,
                                size: 13,
                                color: isDelivery ? Colors.purple.shade700 : AppTheme.accentBlue,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isDelivery ? 'Delivery' : 'Pickup',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isDelivery ? Colors.purple.shade700 : AppTheme.accentBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (jobStatusLabel.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: order.status == OrderStatus.completed
                                  ? Colors.green.shade50
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              jobStatusLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: order.status == OrderStatus.completed
                                    ? Colors.green.shade800
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '₱${total.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: isPaid ? Colors.green[700] : AppTheme.accentBlue,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: isPaid ? Colors.grey.shade400 : AppTheme.accentBlue,
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Customer name & Order number row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      order.customerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    order.displayNumber,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: AppTheme.textLight,
                    ),
                  ),
                ],
              ),
              if (order.customerPhone != null && order.customerPhone!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.phone_outlined, size: 13, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      order.customerPhone!,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
              if (order.deliveryAddress != null && order.deliveryAddress!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 13, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        order.deliveryAddress!,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Bottom Bar: Status Badge / Action Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isPaid ? Colors.green.shade50 : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isPaid ? Icons.check_circle : Icons.schedule,
                          size: 13,
                          color: isPaid ? Colors.green.shade700 : Colors.amber.shade800,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isPaid ? 'Paid' : 'Payment Due',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isPaid ? Colors.green.shade700 : Colors.amber.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isPaid)
                    // Flexible + minimumSize/tapTargetSize overrides cancel the global
                    // theme's Size(double.infinity, 56) which forces w=Infinity when
                    // the button is a direct Row child (unconstrained width pass).
                    Flexible(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.payments_outlined, size: 16),
                        label: const Text(
                          'Collect Payment',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: () => _openPaymentProcess(order, isDelivery),
                      ),
                    )
                  else
                    Row(
                      children: [
                        if (order.paymentMethod != null)
                          Text(
                            'Via ${order.paymentMethod}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                          ),
                        const SizedBox(width: 4),
                        const Icon(Icons.verified, size: 16, color: Colors.green),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
