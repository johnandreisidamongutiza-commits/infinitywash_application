import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_error.dart';
import '../../../models/order.dart';
import '../../../services/order_service.dart';
import '../../../services/data_change_monitor.dart';
import '../../../services/supabase_service.dart';
import '../../../widgets/skeleton_loading.dart';

/// Rejected requests accumulate forever, so they are loaded a page at a time.
const int _kRejectedPageSize = 8;

class RejectedRequestsScreen extends StatefulWidget {
  const RejectedRequestsScreen({super.key});

  @override
  State<RejectedRequestsScreen> createState() => _RejectedRequestsScreenState();
}

class _RejectedRequestsScreenState extends State<RejectedRequestsScreen> {
  static List<LaundryOrder>? _cachedOrders;
  static String? _cachedQuery;
  static int? _cachedPage;
  static int? _cachedOrderVersion;
  static String? _cachedUserId;
  static int _cachedTotalCount = 0;
  static DateTime? _lastCleanupAt;

  final OrderService _orderService = OrderService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  final List<LaundryOrder> _rejectedOrders = [];
  bool _isLoading = true;
  bool _isFetching = false;
  bool _refreshQueued = false;
  int _currentPage = 1;
  int _totalCount = 0;
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    DataChangeMonitor.instance.start();
    DataChangeMonitor.instance.ordersVersion.addListener(_onOrdersChanged);
    if (_cachedOrders != null &&
        _cachedUserId == SupabaseService.client.auth.currentUser?.id &&
        _cachedQuery == '' &&
        _cachedPage == 1 &&
        _cachedOrderVersion == DataChangeMonitor.instance.ordersVersion.value) {
      _rejectedOrders.addAll(_cachedOrders!);
      _totalCount = _cachedTotalCount;
      _isLoading = false;
    } else {
      _fetchPage(1);
    }
  }

  @override
  void dispose() {
    DataChangeMonitor.instance.ordersVersion.removeListener(_onOrdersChanged);
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  int get _totalPages {
    if (_totalCount == 0) return 1;
    return (_totalCount / _kRejectedPageSize).ceil();
  }

  int get _startItem {
    if (_totalCount == 0 || _rejectedOrders.isEmpty) return 0;
    return ((_currentPage - 1) * _kRejectedPageSize) + 1;
  }

  int get _endItem {
    if (_totalCount == 0 || _rejectedOrders.isEmpty) return 0;
    return (_startItem + _rejectedOrders.length - 1);
  }

  Future<void> _fetchPage(int page) async {
    if (_isFetching) {
      _refreshQueued = true;
      return;
    }
    _isFetching = true;
    setState(() {
      _isLoading = true;
      _currentPage = page;
    });

    try {
      final now = DateTime.now();
      if (page == 1 &&
          (_lastCleanupAt == null ||
              now.difference(_lastCleanupAt!) > const Duration(minutes: 10))) {
        await _orderService.autoRejectExpiredRequests();
        await _orderService.purgeOldRejectedOrders(days: 30);
        _lastCleanupAt = now;
      }

      final query = _searchQuery.trim().isEmpty ? null : _searchQuery.trim();
      final count = await _orderService.fetchOrderCount(
        statuses: ['rejected'],
        isDismissed: false,
        search: query,
      );

      final offset = (page - 1) * _kRejectedPageSize;
      final pageOrders = await _orderService.fetchOrders(
        statuses: ['rejected'],
        isDismissed: false,
        limit: _kRejectedPageSize,
        offset: offset,
        search: query,
      );

      if (!mounted) return;
      setState(() {
        _totalCount = count;
        _rejectedOrders.clear();
        _rejectedOrders.addAll(pageOrders);
        _isLoading = false;
      });
      _cachedOrders = List.of(pageOrders);
      _cachedUserId = SupabaseService.client.auth.currentUser?.id;
      _cachedQuery = query ?? '';
      _cachedPage = page;
      _cachedTotalCount = count;
      _cachedOrderVersion = DataChangeMonitor.instance.ordersVersion.value;

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapErrorToMessage(e)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      _isFetching = false;
      if (_refreshQueued && mounted) {
        _refreshQueued = false;
        _fetchPage(_currentPage);
      }
    }
  }

  void _onOrdersChanged() {
    _cachedOrderVersion = null;
    if (_isFetching) {
      _refreshQueued = true;
    } else if (mounted) {
      _fetchPage(_currentPage);
    }
  }

  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    setState(() => _searchQuery = val);
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _fetchPage(1);
    });
  }

  Future<void> _dismissOrder(LaundryOrder order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dismiss Request?'),
        content: Text(
          'This will permanently dismiss ${order.customerName}\'s request and remove it from this list. It will also clear the notification badge.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: const Text('Dismiss', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _orderService.dismissRejectedOrder(order.id);
      if (!mounted) return;
      setState(() {
        _rejectedOrders.removeWhere((o) => o.id == order.id);
        _totalCount = (_totalCount - 1).clamp(0, 999999);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request dismissed and removed from list.'),
          duration: Duration(seconds: 2),
        ),
      );
      if (_rejectedOrders.isEmpty && _currentPage > 1) {
        _fetchPage(_currentPage - 1);
      } else {
        _fetchPage(_currentPage);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to dismiss request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _dismissAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dismiss All Requests?'),
        content: const Text(
          'This will permanently dismiss all rejected requests and remove them from this list. It will also clear your notification badge.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: const Text('Dismiss All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final count = await _orderService.dismissAllRejectedOrders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dismissed $count request(s) and cleared notification badge.'),
          duration: const Duration(seconds: 2),
        ),
      );
      _fetchPage(1);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to dismiss all requests: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _reopenOrder(LaundryOrder order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reopen Request?'),
        content: Text(
          'Reopening will move ${order.customerName}\'s request back to the Requests tab '
          'under "Pending Approval" for staff review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentBlue,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: const Text('Reopen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _orderService.reopenRejectedOrder(order.id);
      if (!mounted) return;
      setState(() {
        _rejectedOrders.removeWhere((o) => o.id == order.id);
        _totalCount = (_totalCount - 1).clamp(0, 999999);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request moved back to Pending Requests.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      if (_rejectedOrders.isEmpty && _currentPage > 1) {
        _fetchPage(_currentPage - 1);
      } else {
        _fetchPage(_currentPage);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to reopen request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: const Color(0xFFF7F8FA),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textDark,
          ),
          decoration: InputDecoration(
            hintText: 'Search by customer, phone, or order #...',
            hintStyle: TextStyle(
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

  Widget _buildEmptyState() {
    final isSearching = _searchQuery.trim().isNotEmpty;
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: (isSearching ? Colors.blue : Colors.green).withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSearching ? Icons.search_off_rounded : Icons.check_circle_outline,
                  size: 64,
                  color: isSearching ? AppTheme.accentBlue : Colors.green,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                isSearching ? 'No Matching Requests' : 'No Rejected Requests',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isSearching
                    ? 'No rejected requests match "$_searchQuery". Try searching with different keywords.'
                    : 'All rejected requests have been reviewed and dismissed. Notification badge is clear!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textLight.withValues(alpha: 0.8),
                  height: 1.4,
                ),
              ),
              if (isSearching) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Clear Search'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentBlue,
                    side: BorderSide(color: AppTheme.accentBlue.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaginationBar() {
    final canPrev = _currentPage > 1;
    final canNext = _currentPage < _totalPages;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Previous Button
          OutlinedButton.icon(
            onPressed: canPrev && !_isLoading ? () => _fetchPage(_currentPage - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded, size: 18),
            label: const Text('Previous'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textDark,
              disabledForegroundColor: AppTheme.textLight.withValues(alpha: 0.35),
              side: BorderSide(
                color: canPrev ? Colors.grey.shade300 : Colors.grey.shade200,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              visualDensity: VisualDensity.compact,
              minimumSize: Size.zero,
            ),
          ),

          // Page info
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Page $_currentPage of $_totalPages',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Showing $_startItem–$_endItem of $_totalCount',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textLight.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),

          // Next Button
          OutlinedButton.icon(
            onPressed: canNext && !_isLoading ? () => _fetchPage(_currentPage + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded, size: 18),
            label: const Text('Next'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accentBlue,
              disabledForegroundColor: AppTheme.textLight.withValues(alpha: 0.35),
              side: BorderSide(
                color: canNext ? AppTheme.accentBlue.withValues(alpha: 0.5) : Colors.grey.shade200,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              visualDensity: VisualDensity.compact,
              minimumSize: Size.zero,
            ),
          ),
        ],
      ),
    );
  }

  String _formatReason(String? reason) {
    if (reason == null || reason.isEmpty) return 'No reason provided';
    switch (reason) {
      case 'out_of_service_area':
        return 'Out of service area';
      case 'capacity_full':
        return 'Shop is at full capacity';
      case 'invalid_items':
        return 'Unsupported or invalid items';
      case 'unreachable':
        return 'Customer unreachable / invalid info';
      case 'other':
        return 'Other reason';
      default:
        return reason;
    }
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final local = dateTime.toLocal();
    final hour = local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
    final period = local.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour:${local.minute.toString().padLeft(2, '0')} $period';
    final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${monthNames[local.month - 1]} ${local.day}, ${local.year} • $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text(
          'Rejected Requests',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.textDark),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_totalCount > 0)
            TextButton.icon(
              onPressed: _dismissAll,
              icon: const Icon(Icons.done_all, size: 18, color: AppTheme.accentBlue),
              label: const Text(
                'Dismiss All',
                style: TextStyle(color: AppTheme.accentBlue, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          if (_totalCount > 0 && !_isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$_totalCount rejected request${_totalCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textLight.withValues(alpha: 0.9),
                    ),
                  ),
                  Text(
                    'Showing $_startItem–$_endItem',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textLight.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _fetchPage(_currentPage),
              child: _isLoading && _rejectedOrders.isEmpty
                  ? const SkeletonCardList(
                      itemCount: 4,
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                      spacing: 14,
                    )
                  : _rejectedOrders.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _rejectedOrders.length + (_totalPages > 1 ? 1 : 0),
                          separatorBuilder: (context, index) => const SizedBox(height: 14),
                          itemBuilder: (context, index) {
                            if (index == _rejectedOrders.length) {
                              return _buildPaginationBar();
                            }
                            return _buildRejectedCard(_rejectedOrders[index]);
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRejectedCard(LaundryOrder order) {
    final orderDisplay = order.displayNumber;
    final isRiderPickup = order.collectionMethod == CollectionMethod.riderPickup;
    final photos = order.laundryPhotoUrls ?? [];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.red.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: ID, Collection Method & Rejected / Dismissed badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    orderDisplay,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accentBlue,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isRiderPickup ? AppTheme.accentBlue : Colors.teal).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    order.collectionText.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: isRiderPickup ? AppTheme.accentBlue : Colors.teal,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cancel_outlined, size: 11, color: Colors.red),
                      SizedBox(width: 3),
                      Text(
                        'REJECTED',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Customer Name & Contact
            Row(
              children: [
                const Icon(Icons.person_outline, size: 16, color: AppTheme.textDark),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    order.customerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppTheme.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (order.customerPhone != null && order.customerPhone!.isNotEmpty) ...[
                  const Icon(Icons.phone_outlined, size: 14, color: AppTheme.textLight),
                  const SizedBox(width: 4),
                  Text(
                    order.customerPhone!,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                  ),
                ],
              ],
            ),

            if (order.deliveryAddress != null && order.deliveryAddress!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_outlined, size: 15, color: AppTheme.textLight),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      order.deliveryAddress!,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Rejection reason banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.info_outline, size: 15, color: Colors.red),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Reason for Rejection',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatReason(order.rejectionReason),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (order.staffMessage != null && order.staffMessage!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.comment_outlined, size: 13, color: AppTheme.textLight),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              order.staffMessage!,
                              style: const TextStyle(fontSize: 12, color: AppTheme.textDark, fontStyle: FontStyle.italic),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Customer notes/description if any
            if (order.customerDescription != null && order.customerDescription!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notes, size: 14, color: AppTheme.textLight),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Customer notes: ${order.customerDescription!}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            // Photos if any
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Attached Photos (${photos.length})',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textDark),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                  itemBuilder: (context, photoIndex) {
                    final photo = photos[photoIndex];
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => _RejectedFullScreenImageViewer(
                              photoUrls: photos,
                              initialIndex: photoIndex,
                            ),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 64,
                          height: 64,
                          color: AppTheme.softGray,
                          child: _buildThumbnailImage(photo),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],

            // Footer: Reviewed timestamp
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.schedule, size: 12, color: AppTheme.textLight),
                const SizedBox(width: 4),
                Text(
                  order.reviewedAt != null
                      ? 'Rejected ${_formatDateTime(order.reviewedAt)}'
                      : 'Requested ${_formatDateTime(order.createdAt)}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                ),
              ],
            ),

            // Actions: Dismiss & Reopen
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _dismissOrder(order),
                    icon: const Icon(Icons.archive_outlined, size: 16, color: Color(0xFFDC2626)),
                    label: const Text(
                      'Dismiss',
                      style: TextStyle(
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFFFEF2F2),
                      side: const BorderSide(color: Color(0xFFFECACA)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      minimumSize: Size.zero,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _reopenOrder(order),
                    icon: const Icon(Icons.replay_rounded, size: 16, color: Colors.white),
                    label: const Text(
                      'Reopen Request',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      minimumSize: Size.zero,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnailImage(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.photo, color: AppTheme.textLight, size: 20),
      );
    } else if (path.startsWith('data:image') ||
        (path.length > 100 && !path.startsWith('/') && !path.contains('\\'))) {
      try {
        final base64String = path.contains(',') ? path.split(',').last : path;
        final bytes = base64Decode(base64String.trim());
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.photo, color: AppTheme.textLight, size: 20),
        );
      } catch (e) {
        return const Icon(Icons.photo, color: AppTheme.textLight, size: 20);
      }
    } else {
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.photo, color: AppTheme.textLight, size: 20),
        );
      } else {
        return const Icon(Icons.photo, color: AppTheme.textLight, size: 20);
      }
    }
  }
}

/// Full screen viewer for photo inspection
class _RejectedFullScreenImageViewer extends StatefulWidget {
  final List<String> photoUrls;
  final int initialIndex;

  const _RejectedFullScreenImageViewer({
    required this.photoUrls,
    required this.initialIndex,
  });

  @override
  State<_RejectedFullScreenImageViewer> createState() => _RejectedFullScreenImageViewerState();
}

class _RejectedFullScreenImageViewerState extends State<_RejectedFullScreenImageViewer> {
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
          style: const TextStyle(color: Colors.white, fontSize: 16),
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
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        },
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image, color: Colors.white54, size: 48),
              SizedBox(height: 8),
              Text('Unable to load photo', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      );
    } else if (path.startsWith('data:image') ||
        (path.length > 100 && !path.startsWith('/') && !path.contains('\\'))) {
      try {
        final base64String = path.contains(',') ? path.split(',').last : path;
        final bytes = base64Decode(base64String.trim());
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
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
            child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
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
