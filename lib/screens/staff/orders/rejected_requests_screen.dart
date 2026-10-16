import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_error.dart';
import '../../../models/order.dart';
import '../../../services/order_service.dart';

/// Rejected requests accumulate forever, so they are loaded a page at a time.
/// Matches the page size used by the Orders screen next door.
const int _kRejectedPageSize = 8;

class RejectedRequestsScreen extends StatefulWidget {
  const RejectedRequestsScreen({super.key});

  @override
  State<RejectedRequestsScreen> createState() => _RejectedRequestsScreenState();
}

class _RejectedRequestsScreenState extends State<RejectedRequestsScreen> {
  final OrderService _orderService = OrderService();
  final ScrollController _scrollController = ScrollController();
  // Only ever mutated (cleared / appended to) while paging; never reassigned.
  final List<LaundryOrder> _rejectedOrders = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadRejectedOrders();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMoreRejected();
    }
  }

  Future<void> _loadMoreRejected() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    await _fetchRejected(reset: false);
  }

  /// Loads the first page. Also used by pull-to-refresh, which is why it
  /// returns a Future that completes only once the request has finished.
  Future<void> _loadRejectedOrders() async {
    setState(() {
      _isLoading = true;
      _hasMore = true;
    });
    await _fetchRejected(reset: true);
  }

  Future<void> _fetchRejected({required bool reset}) async {
    try {
      if (reset) {
        await _orderService.autoRejectExpiredRequests();
      }
      final page = await _orderService.fetchOrders(
        statuses: ['rejected'],
        limit: _kRejectedPageSize,
        offset: reset ? 0 : _offset,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _rejectedOrders.clear();
        }
        _rejectedOrders.addAll(page);
        _offset = _rejectedOrders.length;
        // A short page means we reached the end of the list.
        _hasMore = page.length == _kRejectedPageSize;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        // Let the user retry the page that failed rather than losing the list.
        if (!reset) _hasMore = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapErrorToMessage(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildPaginationFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: _isLoadingMore
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.accentBlue,
                ),
              )
            : _hasMore
                ? const SizedBox.shrink()
                : Text(
                    'No more rejected requests',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textLight.withValues(alpha: 0.5),
                    ),
                  ),
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
      ),
      body: RefreshIndicator(
        onRefresh: _loadRejectedOrders,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _rejectedOrders.isEmpty
                ? Center(
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
                                color: Colors.red.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.do_disturb_alt_outlined,
                                size: 64,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'No Rejected Requests',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textDark,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Requests you decline or reject will show up here for your records.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textLight.withValues(alpha: 0.8),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    // +1 for the pagination footer.
                    itemCount: _rejectedOrders.length + 1,
                    separatorBuilder: (context, index) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      if (index == _rejectedOrders.length) {
                        return _buildPaginationFooter();
                      }
                      return _buildRejectedCard(_rejectedOrders[index]);
                    },
                  ),
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
        border: Border.all(color: Colors.red.withValues(alpha: 0.15)),
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
            // Top Row: ID, Collection Method & Rejected badge
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
