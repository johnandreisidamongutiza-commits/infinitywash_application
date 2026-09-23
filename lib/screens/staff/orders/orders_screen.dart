import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
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
      final rejected = await _orderService.fetchOrders(
        statuses: ['rejected'],
        limit: 200,
        offset: 0,
      );
      if (mounted) setState(() => _rejectedCount = rejected.length);
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
      _showError(e);
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
        content: Text('Error loading orders: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Orders'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Badge(
                isLabelVisible: _rejectedCount > 0,
                backgroundColor: Colors.red,
                label: Text(
                  '$_rejectedCount',
                  style: const TextStyle(
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
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: AppTheme.softGray,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppTheme.accentBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.textLight,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              dividerHeight: 0,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Requests'),
                      if (_requests.isNotEmpty || _requestsHasMore) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _requestsHasMore
                                ? '${_requests.length}+'
                                : '${_requests.length}',
                            style: const TextStyle(
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
                const Tab(text: 'Active'),
                const Tab(text: 'History'),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
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
      floatingActionButton: FloatingActionButton(
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
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REQUESTS TAB UI
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildRequestsTab() {
    if (_requestsLoading && _requests.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_requestsLoading && _requests.isEmpty) {
      return _buildEmptyState(
        icon: Icons.online_prediction,
        title: 'No pending online requests',
        subtitle: 'New requests from customers will appear here.',
      );
    }

    return ListView.separated(
      controller: _requestsScroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      itemCount: _requests.length + 1, // +1 for footer
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        if (index == _requests.length) {
          return _buildPaginationFooter(
              _requestsLoadingMore, _requestsHasMore);
        }
        return _buildRequestCard(_requests[index]);
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVE TAB UI
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildActiveTab() {
    if (_activeLoading && _active.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_activeLoading && _active.isEmpty) {
      return _buildEmptyState(
        icon: Icons.assignment_outlined,
        title: 'No active orders',
        subtitle: 'New orders will appear here when created.',
      );
    }

    return ListView.separated(
      controller: _activeScroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      itemCount: _active.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        if (index == _active.length) {
          return _buildPaginationFooter(_activeLoadingMore, _activeHasMore);
        }
        return _buildOrderCard(_active[index]);
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HISTORY TAB UI
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHistoryTab() {
    if (_historyLoading && _history.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_historyLoading && _history.isEmpty) {
      return _buildEmptyState(
        icon: Icons.history,
        title: 'No order history',
        subtitle: 'Completed orders will appear here.',
      );
    }

    return ListView.separated(
      controller: _historyScroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      itemCount: _history.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        if (index == _history.length) {
          return _buildPaginationFooter(_historyLoadingMore, _historyHasMore);
        }
        return _buildOrderCard(_history[index]);
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
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : hasMore
                ? const SizedBox.shrink()
                : Text(
                    '— No more orders —',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textLight.withValues(alpha: 0.5),
                    ),
                  ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: AppTheme.textLight.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: AppTheme.textLight)),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
                color: AppTheme.textLight.withValues(alpha: 0.5), fontSize: 12),
          ),
        ],
      ),
    );
  }

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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
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
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        request.orderNumber ?? request.id,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentBlue,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: (isRiderPickup
                                ? AppTheme.accentBlue
                                : Colors.teal)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        request.collectionText.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isRiderPickup
                              ? AppTheme.accentBlue
                              : Colors.teal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'PENDING',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  request.customerName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                if (request.customerPhone != null &&
                    request.customerPhone!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined,
                          size: 14, color: AppTheme.textLight),
                      const SizedBox(width: 4),
                      Text(
                        request.customerPhone!,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textLight),
                      ),
                    ],
                  ),
                ],
                if (request.deliveryAddress != null &&
                    request.deliveryAddress!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 14, color: AppTheme.textLight),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          request.deliveryAddress!,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textLight),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (hasPhotos) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.photo_library_outlined,
                          size: 14, color: AppTheme.accentBlue),
                      const SizedBox(width: 4),
                      Text(
                        '$photoCount photo${photoCount > 1 ? 's' : ''} attached',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.accentBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
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
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'REVIEW REQUEST',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward, size: 16),
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

  Widget _buildOrderCard(LaundryOrder order) {
    return GestureDetector(
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
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
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
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusBadge(order.status),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              order.customerName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              order.needsCheckIn
                  ? 'Needs check-in'
                  : '${order.loads.length} load(s) • ${order.weightDisplay}',
              style: TextStyle(
                fontSize: 12,
                color:
                    order.needsCheckIn ? Colors.orange : AppTheme.textLight,
                fontWeight: order.needsCheckIn
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
            if (order.rfidTag != null) ...[
              const SizedBox(height: 4),
              Text(
                'RFID: ${order.rfidTag}',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.accentBlue),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(OrderStatus status) {
    Color color;
    String label;

    switch (status) {
      case OrderStatus.pending_pickup:
        color = Colors.orange;
        label = 'Waiting for Pickup';
        break;
      case OrderStatus.processing:
        color = Colors.blue;
        label = 'Processing';
        break;
      case OrderStatus.ready:
        color = Colors.green;
        label = 'Ready';
        break;
      case OrderStatus.out_for_delivery:
        color = Colors.purple;
        label = 'Out for Delivery';
        break;
      case OrderStatus.completed:
        color = Colors.grey;
        label = 'Completed';
        break;
      default:
        color = AppTheme.textLight;
        label = status.toString().split('.').last;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
            color: color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }
}