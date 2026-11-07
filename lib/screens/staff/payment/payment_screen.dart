import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_error.dart';
import '../../../models/order.dart';
import '../../../services/order_service.dart';
import '../../../services/data_change_monitor.dart';
import '../../../widgets/skeleton_loading.dart';
import 'payment_process_screen.dart';

class _PaymentFilterSnapshot {
  const _PaymentFilterSnapshot({
    required this.unpaidOrders,
    required this.unpaidOffset,
    required this.unpaidHasMore,
    required this.unpaidInitialized,
    required this.paidOrders,
    required this.paidOffset,
    required this.paidHasMore,
    required this.paidInitialized,
  });

  final List<LaundryOrder> unpaidOrders;
  final int unpaidOffset;
  final bool unpaidHasMore;
  final bool unpaidInitialized;
  final List<LaundryOrder> paidOrders;
  final int paidOffset;
  final bool paidHasMore;
  final bool paidInitialized;
}

class PaymentScreen extends StatefulWidget {
  final bool isActive;

  const PaymentScreen({super.key, this.isActive = true});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  /// Page size for both payment tabs. Matches the other list screens so the
  /// scroll feel is consistent across the app.
  static const int _kPageSize = 7;

  final OrderService _orderService = OrderService();
  bool _showPaid = false;
  String _searchQuery = '';
  String _subFilter = 'all'; // 'all', 'walkin', 'rider'

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

  // ── Tab counts (cover every row, not just the loaded page) ───────
  int _unpaidCount = 0;
  int _paidCount = 0;
  int _unpaidWalkinCount = 0;
  int _unpaidRiderCount = 0;
  int _paidWalkinCount = 0;
  int _paidRiderCount = 0;
  bool _dataDirty = false;
  String? _pendingSubFilter;
  final Map<String, _PaymentFilterSnapshot> _filterSnapshots = {};

  @override
  void initState() {
    super.initState();
    DataChangeMonitor.instance.start();
    DataChangeMonitor.instance.ordersVersion.addListener(_onOrdersChanged);
    // Attach scroll listeners for infinite pagination
    _unpaidScroll.addListener(() => _onScroll(_unpaidScroll, _loadMoreUnpaid));
    _paidScroll.addListener(() => _onScroll(_paidScroll, _loadMorePaid));

    if (widget.isActive) {
      _initUnpaid();
      _refreshTotals();
    }
  }

  @override
  void didUpdateWidget(covariant PaymentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      if (!_unpaidInitialized) {
        _dataDirty = false;
        _initUnpaid();
        _refreshTotals();
      } else {
        _refreshIfDirty();
      }
    }
  }

  void _onOrdersChanged() {
    _dataDirty = true;
    _refreshIfDirty();
  }

  void _refreshIfDirty() {
    if (!widget.isActive || !_dataDirty) return;
    if (_unpaidLoading || _paidLoading || _unpaidLoadingMore || _paidLoadingMore) {
      return;
    }
    _dataDirty = false;
    _filterSnapshots.clear();
    _refreshAll();
  }

  @override
  void dispose() {
    DataChangeMonitor.instance.ordersVersion.removeListener(_onOrdersChanged);
    _unpaidScroll.dispose();
    _paidScroll.dispose();
    super.dispose();
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

  // ─────────────────────────────────────────────────────────────────────────
  // Tab / filter switching
  // ─────────────────────────────────────────────────────────────────────────
  void _selectTab(bool showPaid) {
    if (_showPaid == showPaid) return;
    setState(() => _showPaid = showPaid);
    // Lazy-load the Paid tab the first time it is opened.
    if (showPaid && !_paidInitialized) _initPaid();
  }

  void _setSubFilter(String filter) {
    if (_subFilter == filter) {
      _pendingSubFilter = null;
      return;
    }
    if (_unpaidLoading || _paidLoading || _unpaidLoadingMore || _paidLoadingMore) {
      _pendingSubFilter = filter;
      return;
    }
    _pendingSubFilter = null;
    _saveCurrentFilterSnapshot();
    final snapshot = _filterSnapshots[filter];
    setState(() {
      _subFilter = filter;
      if (snapshot == null) {
        _resetUnpaidState();
        _resetPaidState();
      } else {
        _restoreFilterSnapshot(snapshot);
      }
    });
    if (_showPaid && !_paidInitialized) _initPaid();
    if (!_showPaid && !_unpaidInitialized) _initUnpaid();
  }

  void _saveCurrentFilterSnapshot() {
    _filterSnapshots[_subFilter] = _PaymentFilterSnapshot(
      unpaidOrders: List.of(_unpaidOrders),
      unpaidOffset: _unpaidOffset,
      unpaidHasMore: _unpaidHasMore,
      unpaidInitialized: _unpaidInitialized,
      paidOrders: List.of(_paidOrders),
      paidOffset: _paidOffset,
      paidHasMore: _paidHasMore,
      paidInitialized: _paidInitialized,
    );
  }

  void _restoreFilterSnapshot(_PaymentFilterSnapshot snapshot) {
    _unpaidOrders
      ..clear()
      ..addAll(snapshot.unpaidOrders);
    _unpaidOffset = snapshot.unpaidOffset;
    _unpaidHasMore = snapshot.unpaidHasMore;
    _unpaidInitialized = snapshot.unpaidInitialized;
    _unpaidLoading = false;
    _unpaidLoadingMore = false;
    _paidOrders
      ..clear()
      ..addAll(snapshot.paidOrders);
    _paidOffset = snapshot.paidOffset;
    _paidHasMore = snapshot.paidHasMore;
    _paidInitialized = snapshot.paidInitialized;
    _paidLoading = false;
    _paidLoadingMore = false;
  }

  void _resetUnpaidState() {
    _unpaidOrders.clear();
    _unpaidOffset = 0;
    _unpaidHasMore = true;
    _unpaidInitialized = false;
  }

  void _resetPaidState() {
    _paidOrders.clear();
    _paidOffset = 0;
    _paidHasMore = true;
    _paidInitialized = false;
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
      final page = await _orderService.fetchOrders(
        paymentStatus: 'unpaid',
        subFilter: _subFilter,
        requireLoads: true,
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
      _saveCurrentFilterSnapshot();
    } catch (e) {
      debugPrint('❌ Error loading unpaid payments: $e');
      if (!mounted) return;
      setState(() {
        _unpaidLoading = false;
        _unpaidLoadingMore = false;
      });
      _showError(e);
    }
    _refreshIfDirty();
    _applyPendingSubFilter();
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
      final page = await _orderService.fetchOrders(
        paymentStatus: 'paid',
        subFilter: _subFilter,
        requireLoads: true,
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
      _saveCurrentFilterSnapshot();
    } catch (e) {
      debugPrint('❌ Error loading paid payments: $e');
      if (!mounted) return;
      setState(() {
        _paidLoading = false;
        _paidLoadingMore = false;
      });
      _showError(e);
    }
    _refreshIfDirty();
    _applyPendingSubFilter();
  }

  void _applyPendingSubFilter() {
    final filter = _pendingSubFilter;
    if (filter == null ||
        _unpaidLoading ||
        _paidLoading ||
        _unpaidLoadingMore ||
        _paidLoadingMore) {
      return;
    }
    _setSubFilter(filter);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Aggregates & refresh
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _refreshTotals() async {
    try {
      final results = await Future.wait([
        _orderService.fetchPaymentBucketTotals(
          paymentStatus: 'unpaid',
          subFilter: 'all',
          requireLoads: true,
        ),
        _orderService.fetchPaymentBucketTotals(
          paymentStatus: 'paid',
          subFilter: 'all',
          requireLoads: true,
        ),
        _orderService.fetchPaymentBucketTotals(
          paymentStatus: 'unpaid',
          subFilter: 'walkin',
          requireLoads: true,
        ),
        _orderService.fetchPaymentBucketTotals(
          paymentStatus: 'unpaid',
          subFilter: 'rider',
          requireLoads: true,
        ),
        _orderService.fetchPaymentBucketTotals(
          paymentStatus: 'paid',
          subFilter: 'walkin',
          requireLoads: true,
        ),
        _orderService.fetchPaymentBucketTotals(
          paymentStatus: 'paid',
          subFilter: 'rider',
          requireLoads: true,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _unpaidCount = results[0].count;
        _paidCount = results[1].count;
        _unpaidWalkinCount = results[2].count;
        _unpaidRiderCount = results[3].count;
        _paidWalkinCount = results[4].count;
        _paidRiderCount = results[5].count;
      });
    } catch (e) {
      // Totals are cosmetic — keep the last known values if the query fails.
      debugPrint('❌ Error loading payment totals: $e');
    }
  }

  /// Pull-to-refresh / refresh button: reloads both tabs and the header.
  Future<void> _refreshAll() async {
    _filterSnapshots.clear();
    await Future.wait([
      _initUnpaid(),
      if (_paidInitialized) _initPaid(),
      _refreshTotals(),
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

  bool _isRiderOrder(LaundryOrder order) {
    return order.collectionMethod == CollectionMethod.riderPickup ||
        order.returnMethod == ReturnMethod.delivery;
  }

  /// Walk-in / Rider filtering happens in the database (see
  /// [OrderService.fetchOrders]); only free-text search is applied here, and it
  /// covers the pages loaded so far.
  List<LaundryOrder> _getFilteredOrders() {
    final list = _activeOrders;
    if (_searchQuery.trim().isEmpty) return list;
    final q = _searchQuery.trim().toLowerCase();
    return list.where((order) {
      final name = order.customerName.toLowerCase();
      final number = order.displayNumber.toLowerCase();
      return name.contains(q) || number.contains(q);
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
          // Filter & Search Section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                // Main filter tabs (Unpaid / Paid)
                Row(
                  children: [
                    Expanded(
                      child: _buildFilterTab(
                        title: 'Unpaid ($_unpaidCount)',
                        isSelected: !_showPaid,
                        color: AppTheme.primaryBlue,
                        onTap: () => _selectTab(false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildFilterTab(
                        title: 'Paid ($_paidCount)',
                        isSelected: _showPaid,
                        color: Colors.green[700]!,
                        onTap: () => _selectTab(true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Sub-filter chips (All / Walk-in / Rider)
                _buildSubFilterBar(),
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
              ],
            ),
          ),

          // Orders List
          Expanded(
            child: _activeLoading && _activeOrders.isEmpty
                ? const SkeletonCardList(
                    itemCount: 4,
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
                    spacing: 12,
                  )
                : displayedOrders.isEmpty
                    ? RefreshIndicator(
                        onRefresh: _refreshAll,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            // ConstrainedBox, not SizedBox: a fixed height clips
                            // the empty state once the system font grows.
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight:
                                    MediaQuery.of(context).size.height * 0.35,
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
                                              ? 'No paid orders found'
                                              : 'No unpaid orders. All caught up!'),
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
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
                            return _buildPaymentCard(displayedOrders[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ─── Filter Tab ─────────────────────────────────────────────────
  Widget _buildFilterTab({
    required String title,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? color : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Sub-filter Bar & Chips ──────────────────────────────────────
  Widget _buildSubFilterBar() {
    final allCount = _showPaid ? _paidCount : _unpaidCount;
    final walkinCount = _showPaid ? _paidWalkinCount : _unpaidWalkinCount;
    final riderCount = _showPaid ? _paidRiderCount : _unpaidRiderCount;

    return Row(
      children: [
        _buildSubFilterChip('All', 'all', allCount),
        const SizedBox(width: 8),
        _buildSubFilterChip('Walk-in', 'walkin', walkinCount),
        const SizedBox(width: 8),
        _buildSubFilterChip('Rider', 'rider', riderCount),
      ],
    );
  }

  Widget _buildSubFilterChip(String label, String filter, int count) {
    final isSelected = _subFilter == filter;

    return Expanded(
      child: GestureDetector(
        onTap: () => _setSubFilter(filter),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryBlue : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryBlue
                  : AppTheme.borderGray.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : AppTheme.textDark,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.25)
                        : AppTheme.softGray,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : AppTheme.textDark,
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

  // ─── Payment Card ───────────────────────────────────────────────
  Widget _buildPaymentCard(LaundryOrder order) {
    final double total = order.totalAmount ?? (order.basePrice > 0 ? order.basePrice : 170.0);
    final isPaid = order.paymentStatus == PaymentStatus.paid;
    final isRider = _isRiderOrder(order);
    final isDelivery = order.returnMethod == ReturnMethod.delivery;
    final isPickup = order.collectionMethod == CollectionMethod.riderPickup;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (isPaid) {
            _showReceiptSheet(order, total);
          } else {
            _openPaymentProcess(order);
          }
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPaid
                  ? Colors.grey.shade200
                  : (isRider
                      ? Colors.grey.shade200
                      : AppTheme.accentBlue.withValues(alpha: 0.25)),
              width: isPaid ? 1 : 1.5,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Badges & Price
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildOrderTypeBadge(
                          isDelivery: isDelivery,
                          isPickup: isPickup,
                        ),
                        if (_getOrderStatusLabel(order).isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: order.status == OrderStatus.completed
                                  ? Colors.green.shade50
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _getOrderStatusLabel(order),
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
                  Text(
                    '₱${total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: isPaid ? Colors.green[700] : AppTheme.accentBlue,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Customer name & order number
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

              // Weight & loads info
              if (order.loads.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.scale_outlined, size: 13, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      '${order.loads.length} load(s) • ${order.weightDisplay}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],

              // Address for delivery orders
              if (isDelivery &&
                  order.deliveryAddress != null &&
                  order.deliveryAddress!.isNotEmpty) ...[
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

              // Bottom Bar: Status + Action
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Payment status badge
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

                  // Action area
                  if (!isPaid) ...[
                    if (isRider)
                      // Rider order: show "Rider Will Collect" muted indicator + override
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.two_wheeler, size: 13, color: Colors.purple.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  'Rider Collects',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _openPaymentProcess(order),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Override',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      // Walk-in order: prominent "Pay Now" button
                      Flexible(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            minimumSize: const Size(0, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.payments_outlined, size: 16),
                          label: const Text(
                            'Pay Now',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          onPressed: () => _openPaymentProcess(order),
                        ),
                      ),
                  ] else ...[
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Order Type Badge ───────────────────────────────────────────
  Widget _buildOrderTypeBadge({required bool isDelivery, required bool isPickup}) {
    final String label;
    final IconData icon;
    final Color color;
    final Color bgColor;

    if (isDelivery) {
      label = 'Delivery';
      icon = Icons.local_shipping_outlined;
      color = Colors.indigo.shade700;
      bgColor = Colors.indigo.shade50;
    } else if (isPickup) {
      label = 'Rider Pickup';
      icon = Icons.two_wheeler;
      color = Colors.purple.shade700;
      bgColor = Colors.purple.shade50;
    } else {
      label = 'Walk-in';
      icon = Icons.storefront_outlined;
      color = AppTheme.accentBlue;
      bgColor = Colors.blue.shade50;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Order Status Label ─────────────────────────────────────────
  String _getOrderStatusLabel(LaundryOrder order) {
    switch (order.status) {
      case OrderStatus.completed:
        return 'Completed';
      case OrderStatus.out_for_delivery:
        return 'Out for Delivery';
      case OrderStatus.ready:
        return 'Ready';
      case OrderStatus.processing:
        return 'Processing';
      default:
        return '';
    }
  }

  // ─── Format DateTime ────────────────────────────────────────────
  String _formatDateTime(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} $hour:$minute $period';
  }

  // ─── Open Payment Process ───────────────────────────────────────
  Future<void> _openPaymentProcess(LaundryOrder order) async {
    final paidSuccess = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => PaymentProcessScreen(order: order)),
    );
    if (paidSuccess == true) {
      // The order moved from Unpaid to Paid, so both tabs and the header
      // totals need to be rebuilt.
      await _refreshAll();
    }
  }

  // ─── Receipt Bottom Sheet ───────────────────────────────────────
  void _showReceiptSheet(LaundryOrder order, double total) {
    final isDelivery = order.returnMethod == ReturnMethod.delivery;
    final isPickup = order.collectionMethod == CollectionMethod.riderPickup;

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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Order ${order.displayNumber}',
                  style: const TextStyle(color: AppTheme.textLight, fontSize: 13),
                ),
                const SizedBox(width: 8),
                _buildOrderTypeBadge(
                  isDelivery: isDelivery,
                  isPickup: isPickup,
                ),
              ],
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
                  _receiptSheetRow(
                    'Amount Paid',
                    '₱${total.toStringAsFixed(2)}',
                    isBold: true,
                  ),
                  _receiptSheetRow(
                    'Payment Method',
                    order.paymentMethod ?? 'Cash / GCash',
                  ),
                  if (order.paidAt != null)
                    _receiptSheetRow('Paid Date', _formatDateTime(order.paidAt!)),
                  if (order.loads.isNotEmpty)
                    _receiptSheetRow(
                      'Details',
                      '${order.loads.length} load(s) • ${order.weightDisplay}',
                    ),
                  if (isDelivery &&
                      order.deliveryAddress != null &&
                      order.deliveryAddress!.isNotEmpty)
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
                  backgroundColor: AppTheme.primaryBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Close',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppTheme.textLight),
          ),
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
}
