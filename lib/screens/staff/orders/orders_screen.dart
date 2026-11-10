import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_error.dart';
import '../../../models/order.dart';
import 'create_order_flow.dart';
import 'order_status_screen.dart';
import 'review_request_screen.dart';
import 'rejected_requests_screen.dart';
import '../../../services/order_service.dart';
import '../../../services/data_change_monitor.dart';
import '../../../widgets/skeleton_loading.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Page sizes per tab
// ─────────────────────────────────────────────────────────────────────────────
const int _kRequestsPageSize = 8;
const int _kActivePageSize = 8;
const int _kHistoryPageSize = 10;

class OrdersScreen extends StatefulWidget {
  final int initialTab;
  final VoidCallback? onBecameVisible;
  final bool isActive;
  const OrdersScreen({
    super.key,
    this.initialTab = 1,
    this.onBecameVisible,
    this.isActive = true,
  });

  @override
  State<OrdersScreen> createState() => OrdersScreenState();
}

class OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final OrderService _orderService = OrderService();

  // ── Requests tab ────────────────────────────────────────────────────────
  final List<LaundryOrder> _requests = [];
  bool _requestsLoading = false;
  bool _requestsLoadingMore = false;
  bool _requestsHasMore = true;
  int _requestsOffset = 0;
  bool _requestsInitialized = false;
  final ScrollController _requestsScroll = ScrollController();

  // ── Active tab ──────────────────────────────────────────────────────────
  final List<LaundryOrder> _active = [];
  bool _activeLoading = false;
  bool _activeLoadingMore = false;
  bool _activeHasMore = true;
  int _activeOffset = 0;
  bool _activeInitialized = false;
  final ScrollController _activeScroll = ScrollController();
  OrderStatus? _selectedActiveStatus;
  Map<String, int> _activeStatusCounts = {};

  // ── History tab — explicit page pagination ──────────────────────────────
  final List<LaundryOrder> _history = [];
  bool _historyLoading = false;
  bool _historyInitialized = false;
  final ScrollController _historyScroll = ScrollController();
  int _historyPage = 1;          // 1-indexed current page
  int _historyTotalCount = 0;    // total rows from DB
  int get _historyTotalPages =>
      _historyTotalCount == 0 ? 1 : (_historyTotalCount / _kHistoryPageSize).ceil();
  OrderStatus? _selectedHistoryStatus;
  Map<String, int> _historyStatusCounts = {};

  // ── Rejected count (badge only, not paginated) ──────────────────────────
  int _rejectedCount = 0;
  final Set<int> _dirtyTabs = {};
  bool _metadataDirty = true;
  DateTime? _lastRejectedCleanupAt;
  bool _isRunningRejectedCleanup = false;

  // ── Search state — debounced, server-side ────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  // Server-side search: results are already filtered by the DB so no
  // additional in-memory filtering is needed.
  List<LaundryOrder> get _filteredRequests => _requests;

  List<LaundryOrder> get _filteredActive {
    // Status filter is handled server-side in _fetchActive; filter only needed
    // locally when the user has chosen a sub-status and we already fetched all.
    if (_selectedActiveStatus != null) {
      return _active.where((o) => o.status == _selectedActiveStatus).toList();
    }
    return _active;
  }

  // History is paginated server-side — no local filtering needed.
  List<LaundryOrder> get _filteredHistory => _history;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DataChangeMonitor.instance.start();
    DataChangeMonitor.instance.ordersVersion.addListener(_onOrdersChanged);
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab,
    );

    // Attach scroll listeners (Requests & Active only — History uses page buttons)
    _requestsScroll.addListener(() => _onScroll(_requestsScroll, _loadMoreRequests));
    _activeScroll.addListener(() => _onScroll(_activeScroll, _loadMoreActive));

    // Tab-change listener: lazy-load a tab on first visit
    _tabController.addListener(_onTabChanged);

    // Screens inside the role IndexedStack stay mounted. Defer their reads
    // until the Orders destination is actually selected.
    if (widget.isActive) {
      _loadTabForIndex(widget.initialTab);
      _refreshMetadata();
      if (widget.initialTab != 0) _initRequests();
    }
  }

  @override
  void didUpdateWidget(covariant OrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _loadTabForIndex(_tabController.index);
      if (_metadataDirty) _refreshMetadata();
      if (_tabController.index != 0 && !_requestsInitialized) _initRequests();
    }
  }

  void _onOrdersChanged() {
    _dirtyTabs.addAll(const [0, 1, 2]);
    _metadataDirty = true;
    if (widget.isActive) refreshCurrentTab();
  }

  void _afterTabLoad(int index) {
    if (!mounted || !widget.isActive || !_dirtyTabs.contains(index)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isActive) _loadTabForIndex(index);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _dirtyTabs.addAll(const [0, 1, 2]);
      _metadataDirty = true;
      if (widget.isActive) refreshCurrentTab();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    DataChangeMonitor.instance.ordersVersion.removeListener(_onOrdersChanged);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    _requestsScroll.dispose();
    _activeScroll.dispose();
    _historyScroll.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Scroll listener — triggers load-more when near bottom (200 px threshold)
  // ─────────────────────────────────────────────────────────────────────────
  void _onScroll(ScrollController ctrl, VoidCallback loadMore) {
    if (!ctrl.hasClients) return;
    final pos = ctrl.position;
    print('📜 Scroll position: ${pos.pixels}/${pos.maxScrollExtent}');
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      print('📜 Triggering load more...');
      loadMore();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tab change — lazy-init tabs that haven't been visited yet
  // ─────────────────────────────────────────────────────────────────────────
  void _onTabChanged() {
    if (_tabController.indexIsChanging || !widget.isActive) return;
    _loadTabForIndex(_tabController.index);
  }

  void _loadTabForIndex(int index) {
    if (!widget.isActive) return;
    switch (index) {
      case 0:
        if (!_requestsInitialized || _dirtyTabs.contains(0)) _initRequests();
        break;
      case 1:
        if (!_activeInitialized || _dirtyTabs.contains(1)) _initActive();
        break;
      case 2:
        if (!_historyInitialized || _dirtyTabs.contains(2)) _initHistory();
        break;
    }
  }

  Future<void> _refreshMetadata() async {
    _metadataDirty = false;
    await Future.wait([
      _loadRejectedCount(),
      _loadActiveStatusCounts(),
      _loadHistoryStatusCounts(),
    ]);
  }

  Future<int> _cleanupRejectedIfNeeded() async {
    final now = DateTime.now();
    if (_isRunningRejectedCleanup ||
        (_lastRejectedCleanupAt != null &&
            now.difference(_lastRejectedCleanupAt!) <=
                const Duration(minutes: 10))) {
      return 0;
    }
    _isRunningRejectedCleanup = true;
    try {
      final expiredCount = await _orderService.autoRejectExpiredRequests();
      await _orderService.purgeOldRejectedOrders(days: 30);
      _lastRejectedCleanupAt = DateTime.now();
      return expiredCount;
    } catch (error) {
      debugPrint('Could not run rejected-order cleanup: $error');
      _lastRejectedCleanupAt = DateTime.now();
      return 0;
    } finally {
      _isRunningRejectedCleanup = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Rejected & Active status counts
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _loadRejectedCount() async {
    try {
      await _cleanupRejectedIfNeeded();
      final count = await _orderService.fetchOrderCount(
        statuses: ['rejected'],
        isDismissed: false,
      );
      if (mounted) setState(() => _rejectedCount = count);
    } catch (_) {}
  }

  Future<void> _loadActiveStatusCounts() async {
    try {
      final results = await Future.wait([
        _orderService.fetchOrderCount(statuses: ['pending_pickup']),
        _orderService.fetchOrderCount(statuses: ['processing']),
        _orderService.fetchOrderCount(statuses: ['ready']),
        _orderService.fetchOrderCount(statuses: ['out_for_delivery']),
      ]);
      if (mounted) {
        setState(() {
          _activeStatusCounts = {
            'pending_pickup': results[0],
            'processing': results[1],
            'ready': results[2],
            'out_for_delivery': results[3],
            'all': results[0] + results[1] + results[2] + results[3],
          };
        });
      }
    } catch (_) {}
  }

  Future<void> _loadHistoryStatusCounts() async {
    try {
      final results = await Future.wait([
        _orderService.fetchOrderCount(statuses: ['completed']),
        _orderService.fetchOrderCount(statuses: ['cancelled']),
      ]);
      if (mounted) {
        setState(() {
          _historyStatusCounts = {
            'completed': results[0],
            'cancelled': results[1],
            'all': results[0] + results[1],
          };
        });
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REQUESTS TAB
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _initRequests() async {
    if (_requestsLoading) return;
    _dirtyTabs.remove(0);
    setState(() {
      _requestsLoading = true;
      _requestsInitialized = true;
      _requests.clear();
      _requestsOffset = 0;
      _requestsHasMore = true;
    });
    // Run expiration cleanup occasionally, not on every visit to Requests.
    final expiredCount = await _cleanupRejectedIfNeeded();
    if (expiredCount > 0) _loadRejectedCount();
    await _fetchRequests(reset: true);
  }

  Future<void> _loadMoreRequests() async {
    if (_requestsLoadingMore || !_requestsHasMore) return;
    setState(() => _requestsLoadingMore = true);
    await _fetchRequests(reset: false);
  }

  Future<void> _fetchRequests({required bool reset}) async {
    try {
      final page = await _orderService.fetchOrders(
        statuses: ['pending_approval'],
        limit: _kRequestsPageSize,
        offset: _requestsOffset,
        search: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
      );
      if (!mounted) return;
      setState(() {
        if (reset) _requests.clear();
        _requests.addAll(page);
        _requestsHasMore = page.length == _kRequestsPageSize;
        _requestsOffset += page.length;
        _requestsLoading = false;
        _requestsLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _requestsLoading = false;
        _requestsLoadingMore = false;
      });
      if (_tabController.index == 0) {
        _showError(e);
      }
    }
    _afterTabLoad(0);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVE TAB
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _initActive() async {
    if (_activeLoading) return;
    _dirtyTabs.remove(1);
    setState(() {
      _activeLoading = true;
      _activeInitialized = true;
      _active.clear();
      _activeOffset = 0;
      _activeHasMore = true;
    });
    await _fetchActive(reset: true);
  }

  Future<void> _loadMoreActive() async {
    if (_activeLoadingMore || !_activeHasMore) return;
    setState(() => _activeLoadingMore = true);
    await _fetchActive(reset: false);
  }

  Future<void> _fetchActive({required bool reset}) async {
    try {
      print('🔵 ACTIVE TAB: Fetching with offset=$_activeOffset, limit=$_kActivePageSize');
      final statusesToFetch = _selectedActiveStatus != null
          ? [_selectedActiveStatus!.name]
          : ['pending_pickup', 'processing', 'ready', 'out_for_delivery'];
      print('🔵 ACTIVE TAB: Statuses filter: $statusesToFetch');
      final page = await _orderService.fetchOrders(
        statuses: statusesToFetch,
        limit: _kActivePageSize,
        offset: _activeOffset,
        search: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
      );
      print('🔵 ACTIVE TAB: Received ${page.length} orders');
      if (page.isNotEmpty) {
        print('🔵 ACTIVE TAB: Order details:');
        for (var order in page) {
          print('   - ID: ${order.id}, Number: ${order.displayNumber}, Status: ${order.status}, Customer: ${order.customerName}');
        }
      } else {
        print('🔵 ACTIVE TAB: ⚠️  NO ORDERS RETURNED FROM QUERY');
      }
      if (!mounted) return;
      setState(() {
        if (reset) _active.clear();
        _active.addAll(page);
        _activeHasMore = page.length == _kActivePageSize;
        _activeOffset += page.length;
        print('🔵 ACTIVE TAB: Total orders now: ${_active.length}, hasMore=$_activeHasMore, newOffset=$_activeOffset');
        _activeLoading = false;
        _activeLoadingMore = false;
      });
    } catch (e) {
      print('❌ ACTIVE TAB: Error fetching: $e');
      if (!mounted) return;
      setState(() {
        _activeLoading = false;
        _activeLoadingMore = false;
      });
      _showError(e);
    }
    _afterTabLoad(1);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HISTORY TAB — explicit page-based pagination
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _initHistory() async {
    if (_historyLoading) return;
    _dirtyTabs.remove(2);
    setState(() {
      _historyLoading = true;
      _historyInitialized = true;
      _historyPage = 1;
      _historyTotalCount = 0;
    });
    await _fetchHistory();
  }

  /// Navigate to a specific page in History (1-indexed).
  Future<void> _goToHistoryPage(int page) async {
    if (page < 1 || page > _historyTotalPages) return;
    setState(() {
      _historyPage = page;
      _historyLoading = true;
    });
    // Scroll to top so the user sees the new page from the beginning.
    if (_historyScroll.hasClients) _historyScroll.jumpTo(0);
    await _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final searchTerm = _searchQuery.trim().isEmpty ? null : _searchQuery.trim();
      final offset = (_historyPage - 1) * _kHistoryPageSize;
      final statusesToFetch = _selectedHistoryStatus != null
          ? [_selectedHistoryStatus!.name]
          : ['completed', 'cancelled'];

      // Fetch the page rows + total count in parallel.
      final results = await Future.wait([
        _orderService.fetchOrders(
          statuses: statusesToFetch,
          limit: _kHistoryPageSize,
          offset: offset,
          search: searchTerm,
        ),
        _orderService.fetchOrderCount(
          statuses: statusesToFetch,
          search: searchTerm,
        ),
      ]);

      if (!mounted) return;
      final pageData = results[0] as List<LaundryOrder>;
      final total = results[1] as int;

      setState(() {
        _history
          ..clear()
          ..addAll(pageData);
        _historyTotalCount = total;
        _historyLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _historyLoading = false);
      _showError(e);
    }
    _afterTabLoad(2);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Pull-to-refresh — resets all initialized tabs + badge
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _refreshAll() async {
    await Future.wait([
      if (_requestsInitialized) _initRequests(),
      if (_activeInitialized) _initActive(),
      if (_historyInitialized) _initHistory(),
      _loadRejectedCount(),
      _loadActiveStatusCounts(),
      _loadHistoryStatusCounts(),
    ]);
  }

  /// Called after returning from sub-screens (FAB, review, order status).
  /// Forces refresh of Active tab since new orders always go there.
  Future<void> _refreshAllTabs() async {
    _dirtyTabs.addAll(const [0, 1, 2]);
    _metadataDirty = true;
    if (!widget.isActive) return;
    await refreshCurrentTab();
  }

  /// Refresh only the currently visible tab
  Future<void> refreshCurrentTab() async {
    if (!widget.isActive) {
      _dirtyTabs.addAll(const [0, 1, 2]);
      _metadataDirty = true;
      return;
    }
    final currentIndex = _tabController.index;
    switch (currentIndex) {
      case 0:
        await _initRequests();
        break;
      case 1:
        await _initActive();
        break;
      case 2:
        await _initHistory();
        break;
    }
    if (_metadataDirty) await _refreshMetadata();
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

  // ───────────────────────────────────────────────────────────────────────────
  // Debounced server-side search — fires 400 ms after the user stops typing.
  // Resets all tabs (and History back to page 1) with the new query.
  // ───────────────────────────────────────────────────────────────────────────
  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    setState(() => _searchQuery = val); // update UI immediately (clear icon, etc.)
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      // Reset pagination state then re-fetch whichever tabs are initialized.
      if (_requestsInitialized) _initRequests();
      if (_activeInitialized) _initActive();
      if (_historyInitialized) {
        // History resets to page 1 on every new search.
        setState(() => _historyPage = 1);
        _fetchHistory();
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
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

  String _statusLabel(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_approval:
        return 'New Request';
      case OrderStatus.pending_pickup:
        return 'Waiting for Pickup';
      case OrderStatus.processing:
        return 'Processing';
      case OrderStatus.ready:
        return 'Ready';
      case OrderStatus.out_for_delivery:
        return 'Out for Delivery';
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
        return Icons.mark_email_unread_outlined;
      case OrderStatus.pending_pickup:
        return Icons.local_shipping_outlined;
      case OrderStatus.processing:
        return Icons.local_laundry_service_outlined;
      case OrderStatus.ready:
        return Icons.check_circle_outline_rounded;
      case OrderStatus.out_for_delivery:
        return Icons.delivery_dining_rounded;
      case OrderStatus.completed:
        return Icons.task_alt_rounded;
      case OrderStatus.rejected:
        return Icons.cancel_outlined;
      case OrderStatus.cancelled:
        return Icons.cancel_outlined;
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
          'Orders',
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
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Badge(
                isLabelVisible: _rejectedCount > 0,
                backgroundColor: AppTheme.errorRed,
                label: Text(
                  '$_rejectedCount',
                  style: GoogleFonts.lexend(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
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
                _loadRejectedCount();
                if (_requestsInitialized) _initRequests();
              },
            ),
          ),
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
                color: AppTheme.primaryBlue,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.3),
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
                        if (_filteredRequests.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.errorRed,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _searchQuery.isNotEmpty
                                  ? '${_filteredRequests.length}'
                                  : (_requestsHasMore
                                      ? '${_requests.length}+'
                                      : '${_requests.length}'),
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
                const Tab(text: 'Active'),
                const Tab(text: 'History'),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              final tabIndex =
                  (_tabController.animation?.value.round() ?? _tabController.index);
              if (tabIndex == 1) return _buildActiveStatusFilter();
              if (tabIndex == 2) return _buildHistoryStatusFilter();
              return const SizedBox.shrink();
            },
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppTheme.accentBlue,
              onRefresh: _refreshAll,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildRequestsTab(),
                  _buildActiveTab(),
                  _buildHistoryTab(),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          final isHistoryTab =
              (_tabController.animation?.value.round() ?? _tabController.index) == 2;
          if (isHistoryTab) return const SizedBox.shrink();

          return FloatingActionButton.extended(
            heroTag: 'staff_orders_new_order',
            onPressed: () async {
              print('🔵 FAB: Opening create order flow...');
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CreateOrderFlow()),
              );
              print('🔵 FAB: Returned from create order flow. Result: $result');
              if (result == true) {
                print('🔵 FAB: Order created successfully! Switching to Active tab...');
                // Switch to Active tab to show the newly created order
                _tabController.animateTo(1);
                print('🔵 FAB: Tab switched to index 1 (Active). Now refreshing...');
                // Force refresh Active tab
                await _refreshAllTabs();
                print('🔵 FAB: Refresh complete!');
              } else {
                print('🔵 FAB: Order not created (result != true)');
              }
            },
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: Text(
              'New Order',
              style: GoogleFonts.lexend(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REQUESTS TAB UI
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildRequestsTab() {
    if (_requestsLoading && _requests.isEmpty) {
      return const SkeletonCardList();
    }

    if (_searchQuery.trim().isNotEmpty && _filteredRequests.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matching requests',
        subtitle: 'No requests matched "$_searchQuery".',
        actionLabel: 'Clear Search',
        onAction: () {
          _searchController.clear();
          _onSearchChanged('');
        },
      );
    }

    if (!_requestsLoading && _requests.isEmpty) {
      return _buildEmptyState(
        icon: Icons.mark_email_unread_outlined,
        title: 'No pending requests',
        subtitle: 'New online requests from customers will appear here.',
      );
    }

    final isSearching = _searchQuery.trim().isNotEmpty;
    final displayList = _filteredRequests;

    return ListView.separated(
      controller: _requestsScroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      itemCount: isSearching ? displayList.length : displayList.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (!isSearching && index == displayList.length) {
          return _buildPaginationFooter(
              _requestsLoadingMore, _requestsHasMore);
        }
        return _buildRequestCard(displayList[index]);
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVE TAB UI
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildActiveTab() {
    if (_activeLoading && _active.isEmpty) {
      return const SkeletonCardList();
    }

    if (_searchQuery.trim().isNotEmpty && _filteredActive.isEmpty) {
      final statusSuffix = _selectedActiveStatus != null
          ? ' in ${_statusLabel(_selectedActiveStatus!)}'
          : '';
      return _buildEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matching active orders',
        subtitle: 'No active orders$statusSuffix matched "$_searchQuery".',
        actionLabel: 'Clear Search',
        onAction: () {
          _searchController.clear();
          _onSearchChanged('');
        },
      );
    }

    if (!_activeLoading && _active.isEmpty) {
      if (_selectedActiveStatus != null) {
        final label = _statusLabel(_selectedActiveStatus!);
        return _buildEmptyState(
          icon: _statusIcon(_selectedActiveStatus!),
          title: 'No $label orders',
          subtitle: 'There are currently no active orders marked as $label.',
          actionLabel: 'Show All Active Orders',
          onAction: () {
            setState(() {
              _selectedActiveStatus = null;
            });
            _initActive();
          },
        );
      }
      return _buildEmptyState(
        icon: Icons.local_laundry_service_outlined,
        title: 'No active orders',
        subtitle: 'Create a new order to get started.',
      );
    }

    final isSearching = _searchQuery.trim().isNotEmpty;
    final displayList = _filteredActive;

    return ListView.separated(
      controller: _activeScroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      itemCount: isSearching ? displayList.length : displayList.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (!isSearching && index == displayList.length) {
          return _buildPaginationFooter(_activeLoadingMore, _activeHasMore);
        }
        return _buildOrderCard(displayList[index]);
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HISTORY TAB UI
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHistoryTab() {
    if (_historyLoading && _history.isEmpty) {
      return const SkeletonCardList();
    }

    if (_searchQuery.trim().isNotEmpty && _filteredHistory.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matching order history',
        subtitle: 'No orders in history matched "$_searchQuery".',
        actionLabel: 'Clear Search',
        onAction: () {
          _searchController.clear();
          _onSearchChanged('');
        },
      );
    }

    if (!_historyLoading && _history.isEmpty) {
      if (_selectedHistoryStatus != null) {
        final label = _statusLabel(_selectedHistoryStatus!);
        return _buildEmptyState(
          icon: _statusIcon(_selectedHistoryStatus!),
          title: 'No $label orders',
          subtitle: 'There are currently no orders in history marked as $label.',
          actionLabel: 'Show All History',
          onAction: () {
            setState(() {
              _selectedHistoryStatus = null;
              _historyPage = 1;
            });
            _fetchHistory();
          },
        );
      }
      return _buildEmptyState(
        icon: Icons.history_rounded,
        title: 'No order history',
        subtitle: 'Completed and cancelled orders will show up here.',
      );
    }

    return Column(
      children: [
        if (_historyLoading)
          LinearProgressIndicator(
            color: AppTheme.accentBlue,
            backgroundColor: AppTheme.accentBlue.withValues(alpha: 0.15),
            minHeight: 2,
          ),
        Expanded(
          child: ListView.separated(
            controller: _historyScroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            itemCount: _filteredHistory.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _buildOrderCard(_filteredHistory[index]);
            },
          ),
        ),
        _buildHistoryPaginationBar(),
      ],
    );
  }

  /// Bottom pagination control bar for the History tab.
  Widget _buildHistoryPaginationBar() {
    final totalPages = _historyTotalPages;
    final currentPage = _historyPage;
    final totalCount = _historyTotalCount;

    final startItem =
        totalCount == 0 ? 0 : (currentPage - 1) * _kHistoryPageSize + 1;
    final endItem = (currentPage * _kHistoryPageSize > totalCount)
        ? totalCount
        : currentPage * _kHistoryPageSize;

    final canGoPrev = currentPage > 1 && !_historyLoading;
    final canGoNext = currentPage < totalPages && !_historyLoading;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -2),
            blurRadius: 8,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Previous button
                OutlinedButton.icon(
                  onPressed:
                      canGoPrev ? () => _goToHistoryPage(currentPage - 1) : null,
                  icon: const Icon(Icons.arrow_back_ios_rounded, size: 13),
                  label: Text(
                    'Prev',
                    style: GoogleFonts.lexend(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentBlue,
                    disabledForegroundColor:
                        AppTheme.textLight.withValues(alpha: 0.35),
                    side: BorderSide(
                      color: canGoPrev
                          ? AppTheme.accentBlue.withValues(alpha: 0.4)
                          : AppTheme.textLight.withValues(alpha: 0.2),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: const Size(0, 36),
                  ),
                ),

                // Page indicator
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.softGray,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Page $currentPage of $totalPages',
                    style: GoogleFonts.lexend(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                    ),
                  ),
                ),

                // Next button
                OutlinedButton(
                  onPressed:
                      canGoNext ? () => _goToHistoryPage(currentPage + 1) : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentBlue,
                    disabledForegroundColor:
                        AppTheme.textLight.withValues(alpha: 0.35),
                    side: BorderSide(
                      color: canGoNext
                          ? AppTheme.accentBlue.withValues(alpha: 0.4)
                          : AppTheme.textLight.withValues(alpha: 0.2),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Next',
                        style: GoogleFonts.lexend(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 13),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              totalCount == 0
                  ? (_selectedHistoryStatus == OrderStatus.cancelled
                      ? 'No cancelled orders'
                      : _selectedHistoryStatus == OrderStatus.completed
                          ? 'No completed orders'
                          : 'No orders in history')
                  : (_selectedHistoryStatus == OrderStatus.cancelled
                      ? 'Showing $startItem–$endItem of $totalCount cancelled orders'
                      : _selectedHistoryStatus == OrderStatus.completed
                          ? 'Showing $startItem–$endItem of $totalCount completed orders'
                          : 'Showing $startItem–$endItem of $totalCount orders'),
              style: GoogleFonts.lexend(
                fontSize: 11,
                color: AppTheme.textLight,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHARED WIDGETS
  // ─────────────────────────────────────────────────────────────────────────

  /// Shows a spinner while loading more, or an end-of-list label when done.
  Widget _buildPaginationFooter(bool isLoadingMore, bool hasMore) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: isLoadingMore
            ? SizedBox(
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
                    'No more orders',
                    style: GoogleFonts.lexend(
                      fontSize: 12,
                      color: AppTheme.textLight.withValues(alpha: 0.5),
                    ),
                  ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
          onChanged: _onSearchChanged,
          style: GoogleFonts.lexend(
            fontSize: 14,
            color: AppTheme.textDark,
          ),
          decoration: InputDecoration(
            hintText: 'Search by customer, phone, order #, service...',
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
                      _searchController.clear();
                      _onSearchChanged('');
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

  Widget _buildActiveStatusFilter() {
    final statuses = [
      null, // All
      OrderStatus.pending_pickup,
      OrderStatus.processing,
      OrderStatus.ready,
      OrderStatus.out_for_delivery,
    ];

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: statuses.map((status) {
            final isSelected = _selectedActiveStatus == status;
            final label = status == null ? 'All' : _statusLabel(status);
            final icon = status == null ? Icons.all_inbox_rounded : _statusIcon(status);
            const color = AppTheme.primaryBlue;

            final countKey = status == null ? 'all' : status.name;
            final count = _activeStatusCounts[countKey];

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    if (_selectedActiveStatus == status) return;
                    setState(() {
                      _selectedActiveStatus = status;
                    });
                    _initActive();
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
                        if (count != null && count > 0) ...[
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
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildHistoryStatusFilter() {
    final statuses = [
      null, // All
      OrderStatus.completed,
      OrderStatus.cancelled,
    ];

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: statuses.map((status) {
            final isSelected = _selectedHistoryStatus == status;
            final label = status == null ? 'All' : _statusLabel(status);
            final icon = status == null ? Icons.history_rounded : _statusIcon(status);
            final Color color = status == OrderStatus.cancelled
                ? AppTheme.errorRed
                : (status == OrderStatus.completed
                    ? AppTheme.statusCompleted
                    : AppTheme.primaryBlue);

            final countKey = status == null ? 'all' : status.name;
            final count = _historyStatusCounts[countKey];

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    if (_selectedHistoryStatus == status) return;
                    setState(() {
                      _selectedHistoryStatus = status;
                      _historyPage = 1;
                    });
                    _fetchHistory();
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
                        if (count != null && count > 0) ...[
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
              ),
            );
          }).toList(),
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
    return Center(
      // SingleChildScrollView rather than Padding: on a short window (or with a
      // large system font) the content scrolls instead of overflowing.
      child: SingleChildScrollView(
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
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REQUEST CARD — for online requests awaiting approval
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildRequestCard(LaundryOrder request) {
    final hasPhotos =
        request.laundryPhotoUrls != null &&
        request.laundryPhotoUrls!.isNotEmpty;
    final photoCount = request.laundryPhotoUrls?.length ?? 0;
    final isRiderPickup =
        request.collectionMethod == CollectionMethod.riderPickup;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.statusRequestBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withValues(alpha: 0.035),
            blurRadius: 16,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ReviewRequestScreen(request: request),
              ),
            );
            if (result == true) await _initRequests();
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Request identity and metadata ──
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            request.displayNumber,
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
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 13,
                              color: AppTheme.textLight,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _timeAgo(request.createdAt),
                              style: GoogleFonts.lexend(
                                fontSize: 11,
                                color: AppTheme.textLight,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildChip(
                          label: request.collectionText.toUpperCase(),
                          color: AppTheme.statusActive,
                          backgroundColor: AppTheme.statusActiveBg,
                          borderColor: AppTheme.statusActiveBorder,
                          icon: isRiderPickup
                              ? Icons.delivery_dining
                              : Icons.storefront_outlined,
                        ),
                        _buildStatusBadge(OrderStatus.pending_approval),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Customer info ──
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              request.customerName.isNotEmpty
                                  ? request.customerName[0].toUpperCase()
                                  : '?',
                              style: GoogleFonts.lexend(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryBlue,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                request.customerName,
                                style: GoogleFonts.lexend(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppTheme.textDark,
                                ),
                              ),
                              if (request.customerPhone != null &&
                                  request.customerPhone!.isNotEmpty)
                                Text(
                                  request.customerPhone!,
                                  style: GoogleFonts.lexend(
                                    fontSize: 12,
                                    color: AppTheme.textLight,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // ── Address ──
                    if (request.deliveryAddress != null &&
                        request.deliveryAddress!.isNotEmpty) ...[
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
                              request.deliveryAddress!,
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.photo_library_outlined,
                              size: 14,
                              color: AppTheme.primaryBlue,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$photoCount photo${photoCount > 1 ? 's' : ''} attached',
                              style: GoogleFonts.lexend(
                                fontSize: 11,
                                color: AppTheme.primaryBlue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),

                    // ── Review button ──
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  ReviewRequestScreen(request: request),
                            ),
                          );
                          if (result == true) await _initRequests();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Review Request',
                              style: GoogleFonts.lexend(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.arrow_forward_rounded, size: 16),
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
  // ORDER CARD — for active & history orders
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildOrderCard(LaundryOrder order) {
    final style = AppTheme.statusStyleFor(order.status);
    final color = style.primary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.04),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
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
                  builder: (context) => OrderStatusScreen(order: order)),
            );
            if (result == true) {
              // Refresh both Active and History tabs since completing an order
              // moves it from Active → History
              final currentTab = _tabController.index;
              if (currentTab == 1) {
                // Currently on Active tab
                await _initActive();
                // Also refresh History in case order was completed
                if (_historyInitialized) await _initHistory();
              } else if (currentTab == 2) {
                // Currently on History tab
                await _initHistory();
              }
              _loadActiveStatusCounts();
              _loadHistoryStatusCounts();
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Header: order# + status badge + time ──
                        Row(
                          children: [
                            Icon(
                              _statusIcon(order.status),
                              size: 15,
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

                        const SizedBox(height: 12),

                        // ── Customer row ──
                        Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Center(
                                child: Text(
                                  order.customerName.isNotEmpty
                                      ? order.customerName[0].toUpperCase()
                                      : '?',
                                  style: GoogleFonts.lexend(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryBlue,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    order.customerName,
                                    style: GoogleFonts.lexend(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    order.status == OrderStatus.cancelled
                                        ? (order.rejectionReason != null && order.rejectionReason!.isNotEmpty
                                            ? 'Reason: ${order.rejectionReason}'
                                            : 'Order cancelled')
                                        : (order.needsCheckIn
                                            ? 'Needs check-in'
                                            : (order.status == OrderStatus.pending_pickup && order.loads.isEmpty)
                                                ? 'Waiting for pickup'
                                                : '${order.loads.length} load${order.loads.length != 1 ? 's' : ''} • ${order.weightDisplay}'),
                                    style: GoogleFonts.lexend(
                                      fontSize: 12,
                                      color: order.status == OrderStatus.cancelled
                                          ? AppTheme.errorRed
                                          : (order.needsCheckIn
                                              ? AppTheme.statusRequest
                                              : (order.status == OrderStatus.pending_pickup && order.loads.isEmpty)
                                                  ? AppTheme.statusPending
                                                  : AppTheme.textLight),
                                      fontWeight: (order.status == OrderStatus.cancelled ||
                                              order.needsCheckIn ||
                                              (order.status == OrderStatus.pending_pickup && order.loads.isEmpty))
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            // ── Arrow hint ──
                            Icon(
                              Icons.chevron_right_rounded,
                              color: AppTheme.textLight.withValues(alpha: 0.4),
                              size: 22,
                            ),
                          ],
                        ),

                        // ── RFID tag ──
                        if (order.rfidTag != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.nfc_rounded,
                                size: 14,
                                color: AppTheme.primaryBlue.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'RFID: ${order.rfidTag}',
                                style: GoogleFonts.lexend(
                                  fontSize: 11,
                                  color: AppTheme.primaryBlue.withValues(alpha: 0.7),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
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

  // ─────────────────────────────────────────────────────────────────────────
  // MICRO WIDGETS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStatusBadge(OrderStatus status) {
    final style = AppTheme.statusStyleFor(status);
    final label = _statusLabel(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: style.border,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: style.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.lexend(
              color: style.primary,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required Color color,
    Color? backgroundColor,
    Color? borderColor,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: backgroundColor ?? color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor ?? color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: GoogleFonts.lexend(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
