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

// ─────────────────────────────────────────────────────────────────────────────
// Page sizes per tab
// ─────────────────────────────────────────────────────────────────────────────
const int _kRequestsPageSize = 8;
const int _kActivePageSize = 8;
const int _kHistoryPageSize = 8;

class OrdersScreen extends StatefulWidget {
  final int initialTab;
  final VoidCallback? onBecameVisible;
  const OrdersScreen({super.key, this.initialTab = 1, this.onBecameVisible});

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

  // ── History tab ─────────────────────────────────────────────────────────
  final List<LaundryOrder> _history = [];
  bool _historyLoading = false;
  bool _historyLoadingMore = false;
  bool _historyHasMore = true;
  int _historyOffset = 0;
  bool _historyInitialized = false;
  final ScrollController _historyScroll = ScrollController();

  // ── Rejected count (badge only, not paginated) ──────────────────────────
  int _rejectedCount = 0;

  // ── Search state ────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool _matchesSearch(LaundryOrder order) {
    if (_searchQuery.trim().isEmpty) return true;
    final q = _searchQuery.trim().toLowerCase();

    // 1. Customer Name & Phone
    if (order.customerName.toLowerCase().contains(q)) return true;
    if (order.customerPhone != null &&
        order.customerPhone!.toLowerCase().contains(q)) {
      return true;
    }

    // 2. Order & Request IDs
    if (order.displayNumber.toLowerCase().contains(q)) return true;
    if (order.orderNumber != null &&
        order.orderNumber!.toLowerCase().contains(q)) {
      return true;
    }
    if (order.id.toLowerCase().contains(q)) return true;

    // 3. RFID Card Tag
    if (order.rfidTag != null && order.rfidTag!.toLowerCase().contains(q)) {
      return true;
    }

    // 4. Service / Category names & load descriptions
    for (final load in order.loads) {
      if (load.category.toLowerCase().contains(q)) return true;
      if (load.description.toLowerCase().contains(q)) return true;
      if (load.notes != null && load.notes!.toLowerCase().contains(q)) return true;
    }

    // 5. Status label
    if (_statusLabel(order.status).toLowerCase().contains(q)) return true;

    // 6. Customer description, notes, instructions, delivery info
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

    return false;
  }

  List<LaundryOrder> get _filteredRequests =>
      _searchQuery.trim().isEmpty ? _requests : _requests.where(_matchesSearch).toList();

  List<LaundryOrder> get _filteredActive =>
      _searchQuery.trim().isEmpty ? _active : _active.where(_matchesSearch).toList();

  List<LaundryOrder> get _filteredHistory =>
      _searchQuery.trim().isEmpty ? _history : _history.where(_matchesSearch).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab,
    );

    // Attach scroll listeners
    _requestsScroll.addListener(() => _onScroll(_requestsScroll, _loadMoreRequests));
    _activeScroll.addListener(() => _onScroll(_activeScroll, _loadMoreActive));
    _historyScroll.addListener(() => _onScroll(_historyScroll, _loadMoreHistory));

    // Tab-change listener: lazy-load a tab on first visit
    _tabController.addListener(_onTabChanged);

    // Load the initial tab eagerly + rejected badge
    _loadTabForIndex(widget.initialTab);
    _loadRejectedCount();
    // Also check for pending requests in background to keep badge accurate
    if (widget.initialTab != 0) {
      _initRequests();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      print('🔵 ORDERS SCREEN: App resumed, refreshing current tab...');
      refreshCurrentTab();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (_tabController.indexIsChanging) return;
    _loadTabForIndex(_tabController.index);
  }

  void _loadTabForIndex(int index) {
    switch (index) {
      case 0:
        if (!_requestsInitialized) _initRequests();
        break;
      case 1:
        if (!_activeInitialized) _initActive();
        break;
      case 2:
        if (!_historyInitialized) _initHistory();
        break;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Rejected count (for AppBar badge)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _loadRejectedCount() async {
    try {
      // Count in the database instead of downloading up to 200 full orders
      // (with their loads and customer details) only to read `.length`.
      final count = await _orderService.fetchOrderCount(statuses: ['rejected']);
      if (mounted) setState(() => _rejectedCount = count);
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REQUESTS TAB
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _initRequests() async {
    if (_requestsLoading) return;
    setState(() {
      _requestsLoading = true;
      _requestsInitialized = true;
      _requests.clear();
      _requestsOffset = 0;
      _requestsHasMore = true;
    });
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
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVE TAB
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _initActive() async {
    if (_activeLoading) return;
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
      print('🔵 ACTIVE TAB: Statuses filter: [pending_pickup, processing, ready, out_for_delivery]');
      final page = await _orderService.fetchOrders(
        statuses: ['pending_pickup', 'processing', 'ready', 'out_for_delivery'],
        limit: _kActivePageSize,
        offset: _activeOffset,
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
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HISTORY TAB
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _initHistory() async {
    if (_historyLoading) return;
    setState(() {
      _historyLoading = true;
      _historyInitialized = true;
      _history.clear();
      _historyOffset = 0;
      _historyHasMore = true;
    });
    await _fetchHistory(reset: true);
  }

  Future<void> _loadMoreHistory() async {
    if (_historyLoadingMore || !_historyHasMore) return;
    setState(() => _historyLoadingMore = true);
    await _fetchHistory(reset: false);
  }

  Future<void> _fetchHistory({required bool reset}) async {
    try {
      final page = await _orderService.fetchOrders(
        statuses: ['completed'],
        limit: _kHistoryPageSize,
        offset: _historyOffset,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _history.clear();
        _history.addAll(page);
        _historyHasMore = page.length == _kHistoryPageSize;
        _historyOffset += page.length;
        _historyLoading = false;
        _historyLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyLoading = false;
        _historyLoadingMore = false;
      });
      _showError(e);
    }
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
    ]);
  }

  /// Called after returning from sub-screens (FAB, review, order status).
  /// Forces refresh of Active tab since new orders always go there.
  Future<void> _refreshAllTabs() async {
    print('🔵 _refreshAllTabs: Starting refresh...');
    
    // Always force refresh Active tab (new orders go here)
    print('🔵 _refreshAllTabs: Calling _initActive()...');
    await _initActive();
    print('🔵 _refreshAllTabs: _initActive() complete');
    
    // Refresh other tabs only if they were already loaded
    if (_requestsInitialized) {
      print('🔵 _refreshAllTabs: Refreshing Requests tab...');
      await _initRequests();
    }
    if (_historyInitialized) {
      print('🔵 _refreshAllTabs: Refreshing History tab...');
      await _initHistory();
    }
    
    // Refresh rejected count badge
    print('🔵 _refreshAllTabs: Refreshing rejected count...');
    await _loadRejectedCount();
    print('🔵 _refreshAllTabs: All refreshes complete!');
  }

  /// Refresh only the currently visible tab
  Future<void> refreshCurrentTab() async {
    final currentIndex = _tabController.index;
    print('🔵 refreshCurrentTab: Refreshing tab $currentIndex');
    print('🔵 refreshCurrentTab: _requestsInitialized=$_requestsInitialized, _activeInitialized=$_activeInitialized, _historyInitialized=$_historyInitialized');
    
    switch (currentIndex) {
      case 0:
        if (_requestsInitialized) {
          print('🔵 refreshCurrentTab: Calling _initRequests()');
          await _initRequests();
        } else {
          print('🔵 refreshCurrentTab: Requests tab not initialized yet');
        }
        break;
      case 1:
        if (_activeInitialized) {
          print('🔵 refreshCurrentTab: Calling _initActive()');
          await _initActive();
        } else {
          print('🔵 refreshCurrentTab: Active tab not initialized yet, loading for first time');
          _loadTabForIndex(1);
        }
        break;
      case 2:
        if (_historyInitialized) {
          print('🔵 refreshCurrentTab: Calling _initHistory()');
          await _initHistory();
        } else {
          print('🔵 refreshCurrentTab: History tab not initialized yet');
        }
        break;
    }
    
    await _loadRejectedCount();
    print('🔵 refreshCurrentTab: Complete!');
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

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_approval:
        return Colors.orange;
      case OrderStatus.pending_pickup:
        return Colors.orange;
      case OrderStatus.processing:
        return AppTheme.accentBlue;
      case OrderStatus.ready:
        return const Color(0xFF43A047); // green
      case OrderStatus.out_for_delivery:
        return const Color(0xFF7B1FA2); // purple
      case OrderStatus.completed:
        return const Color(0xFF78909C); // blue-grey
      case OrderStatus.rejected:
        return AppTheme.errorRed;
      case OrderStatus.cancelled:
        return AppTheme.textLight;
    }
  }

  String _statusLabel(OrderStatus status) {
    switch (status) {
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
      default:
        return status.toString().split('.').last;
    }
  }

  IconData _statusIcon(OrderStatus status) {
    switch (status) {
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
      default:
        return Icons.circle_outlined;
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
      floatingActionButton: FloatingActionButton.extended(
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
        backgroundColor: AppTheme.accentBlue,
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
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REQUESTS TAB UI
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildRequestsTab() {
    if (_requestsLoading && _requests.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          color: AppTheme.accentBlue,
          strokeWidth: 2.5,
        ),
      );
    }

    if (!_requestsLoading && _requests.isEmpty) {
      return _buildEmptyState(
        icon: Icons.mark_email_unread_outlined,
        title: 'No pending requests',
        subtitle: 'New online requests from customers will appear here.',
      );
    }

    if (_searchQuery.trim().isNotEmpty && _filteredRequests.isEmpty) {
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
      return Center(
        child: CircularProgressIndicator(
          color: AppTheme.accentBlue,
          strokeWidth: 2.5,
        ),
      );
    }

    if (!_activeLoading && _active.isEmpty) {
      return _buildEmptyState(
        icon: Icons.local_laundry_service_outlined,
        title: 'No active orders',
        subtitle: 'Create a new order to get started.',
      );
    }

    if (_searchQuery.trim().isNotEmpty && _filteredActive.isEmpty) {
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
      return Center(
        child: CircularProgressIndicator(
          color: AppTheme.accentBlue,
          strokeWidth: 2.5,
        ),
      );
    }

    if (!_historyLoading && _history.isEmpty) {
      return _buildEmptyState(
        icon: Icons.history_rounded,
        title: 'No order history',
        subtitle: 'Completed orders will show up here.',
      );
    }

    if (_searchQuery.trim().isNotEmpty && _filteredHistory.isEmpty) {
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

    final isSearching = _searchQuery.trim().isNotEmpty;
    final displayList = _filteredHistory;

    return ListView.separated(
      controller: _historyScroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      itemCount: isSearching ? displayList.length : displayList.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (!isSearching && index == displayList.length) {
          return _buildPaginationFooter(_historyLoadingMore, _historyHasMore);
        }
        return _buildOrderCard(displayList[index]);
      },
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
    return Center(
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
                builder: (context) => ReviewRequestScreen(request: request),
              ),
            );
            if (result == true) await _initRequests();
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
                    // ── Header row: order number + badges ──
                    Row(
                      children: [
                        Flexible(
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
                        _buildChip(
                          label: request.collectionText.toUpperCase(),
                          color: isRiderPickup
                              ? AppTheme.accentBlue
                              : const Color(0xFF26A69A), // teal
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
                          _timeAgo(request.createdAt),
                          style: GoogleFonts.lexend(
                            fontSize: 11,
                            color: AppTheme.textLight,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // ── Customer info ──
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.accentBlue.withValues(alpha: 0.1),
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
                                color: AppTheme.accentBlue,
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
                          color: AppTheme.accentBlue.withValues(alpha: 0.06),
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
                          backgroundColor: AppTheme.accentBlue,
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
    final isPendingPickup = order.status == OrderStatus.pending_pickup;
    final isOutForDelivery = order.status == OrderStatus.out_for_delivery;
    final color = _statusColor(order.status);

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
            }
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
                        // ── Header: order# + status badge + time ──
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
                        if (isPendingPickup) ...[
                          const SizedBox(height: 10),
                          _buildActionBanner(
                            icon: Icons.local_shipping_outlined,
                            text: 'Tap to complete pickup manually',
                            color: Colors.orange,
                          ),
                        ],
                        if (isOutForDelivery) ...[
                          const SizedBox(height: 10),
                          _buildActionBanner(
                            icon: Icons.delivery_dining,
                            text: 'Tap to complete delivery manually',
                            color: const Color(0xFF7B1FA2),
                          ),
                        ],

                        const SizedBox(height: 12),

                        // ── Customer row ──
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  order.customerName.isNotEmpty
                                      ? order.customerName[0].toUpperCase()
                                      : '?',
                                  style: GoogleFonts.lexend(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: color,
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
                                    order.needsCheckIn
                                        ? 'Needs check-in'
                                        : '${order.loads.length} load${order.loads.length != 1 ? 's' : ''} • ${order.weightDisplay}',
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
                                color: AppTheme.accentBlue,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'RFID: ${order.rfidTag}',
                                style: GoogleFonts.lexend(
                                  fontSize: 11,
                                  color: AppTheme.accentBlue,
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
}