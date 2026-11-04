import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../../models/chat_model.dart';
import '../../../models/dispatch_job.dart';
import '../../../services/firebase_chat_service.dart';
import '../../../services/profile_service.dart';
import '../../../services/rider_service.dart';
import '../../../services/supabase_service.dart';
import '../../../services/order_number_resolver.dart';
import 'rider_chat_detail_screen.dart';

/// Internal model representing an active rider chat entry.
/// Can be either the persistent Shop Staff line, an active assigned job (Pickup / Delivery),
/// or a job completed earlier today.
class _RiderChatItem {
  final bool isDispatch;
  final ChatConversation? conversation;
  final DispatchJob? job;
  final DateTime sortTime;
  final int unreadCount;

  _RiderChatItem.dispatch({
    required this.conversation,
    required String currentRiderId,
  })  : isDispatch = true,
        job = null,
        unreadCount =
            conversation?.getUnreadCount(currentRiderId, 'rider') ?? 0,
        sortTime = conversation?.lastTimestamp ?? DateTime.now();

  _RiderChatItem.job({
    required this.job,
    required this.conversation,
    required String currentRiderId,
  })  : isDispatch = false,
        unreadCount =
            conversation?.getUnreadCount(currentRiderId, 'rider') ?? 0,
        sortTime =
            conversation?.lastTimestamp ?? job?.createdAt ?? DateTime.now();

  _RiderChatItem.conversationOnly({
    required this.conversation,
    required String currentRiderId,
  })  : isDispatch = false,
        job = null,
        unreadCount =
            conversation?.getUnreadCount(currentRiderId, 'rider') ?? 0,
        sortTime = conversation?.lastTimestamp ?? DateTime.now();

  String get displayName {
    if (isDispatch) return 'InfinityWash Staff';
    return job?.customerName ??
        conversation?.getOtherParticipantName('', 'rider') ??
        'Customer';
  }

  String? get orderId => job?.orderId ?? conversation?.orderId;

  String? get displayPhone =>
      conversation?.getOtherParticipantPhone('', 'rider');

  String? get orderNumber {
    if (conversation?.displayOrderNumber != null &&
        conversation!.displayOrderNumber!.isNotEmpty) {
      return conversation!.displayOrderNumber;
    }
    if (job?.jobNumber != null && job!.jobNumber!.isNotEmpty) {
      return '#${job!.jobNumber}';
    }
    return null;
  }

  String? get taskType {
    if (job?.jobType == 'pickup') {
      if (job?.status == 'pickup_done') return 'PICKUP DONE';
      return 'PICKUP';
    }
    if (job?.jobType == 'delivery') {
      if (job?.status == 'delivery_done') return 'DELIVERY DONE';
      return 'DELIVERY';
    }
    return null;
  }

  Color get taskColor {
    final t = taskType;
    if (t == 'PICKUP') return AppTheme.errorRed;
    if (t == 'DELIVERY') return AppTheme.teamMemberIconOrange;
    if (t == 'PICKUP DONE' || t == 'DELIVERY DONE') return Colors.green;
    return AppTheme.accentBlue;
  }

  String? get address => job?.address;
  String? get landmark => job?.landmark;

  String get lastMessageText {
    if (conversation != null && conversation!.lastMessage.isNotEmpty) {
      return conversation!.lastMessage;
    }
    if (isDispatch) return 'Tap to contact shop staff';
    if (job?.status == 'pickup_done') return 'Pickup completed today';
    if (job?.status == 'delivery_done') return 'Delivery completed today';
    return 'Tap to send a message...';
  }

  String get timeAgoText => conversation?.timeAgo ?? '';
}

class RiderChatsScreen extends StatefulWidget {
  const RiderChatsScreen({super.key});

  @override
  State<RiderChatsScreen> createState() => _RiderChatsScreenState();
}

class _RiderChatsScreenState extends State<RiderChatsScreen> {
  final FirebaseChatService _chatService = FirebaseChatService.instance;
  final ProfileService _profileService = ProfileService();
  final RiderService _riderService = RiderService();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  bool _isSearching = false;
  String _currentRiderId = '';
  String _currentRiderName = 'Rider';
  bool _isProfileLoaded = false;

  // Filter tabs: 0: All (Active + Shop Staff), 1: Pickups, 2: Deliveries, 3: Shop Staff
  int _selectedFilterIndex = 0;

  // Active jobs & completed jobs for today
  List<DispatchJob> _activeJobs = [];
  Map<String, DispatchJob> _activeJobsByOrderId = {};
  Map<String, DispatchJob> _completedJobsByOrderId = {};
  bool _isLoadingJobs = false;

  @override
  void initState() {
    super.initState();
    OrderNumberResolver.changeNotifier.addListener(_onOrderResolved);
    _loadProfileAndEnsureDispatchChat();
    _loadActiveJobs();
  }

  Future<void> _loadProfileAndEnsureDispatchChat() async {
    try {
      final profile = await _profileService.getProfile();
      final riderId = profile['id']?.toString() ?? '';
      final first = profile['first_name']?.toString() ?? '';
      final last = profile['last_name']?.toString() ?? '';
      final name = '$first $last'.trim();
      final phone = profile['phone']?.toString();
      final avatar = profile['avatar_url']?.toString();

      if (mounted) {
        setState(() {
          _currentRiderId = riderId;
          _currentRiderName = name.isNotEmpty ? name : 'Delivery Rider';
          _isProfileLoaded = true;
        });
      }

      // Ensure that InfinityWash Staff channel exists for this rider
      if (riderId.isNotEmpty) {
        await _chatService.getOrCreateRiderStaffChat(
          riderId: riderId,
          riderName: _currentRiderName,
          riderPhone: phone,
          riderAvatar: avatar,
        );
      }
    } catch (e) {
      debugPrint('Error loading rider profile for chats: $e');
      if (mounted) setState(() => _isProfileLoaded = true);
    }
  }

  Future<void> _loadActiveJobs() async {
    if (_isLoadingJobs) return;
    setState(() => _isLoadingJobs = true);
    try {
      final pickups = await _riderService.fetchActivePickupJobs();
      final deliveries = await _riderService.fetchActiveDeliveryJobs();
      final completedPickups = await _riderService.fetchCompletedPickupJobs();
      final completedDeliveries = await _riderService.fetchCompletedDeliveryJobs();
      final allActive = [...pickups, ...deliveries];
      final allCompletedToday = [...completedPickups, ...completedDeliveries];

      if (mounted) {
        setState(() {
          _activeJobs = allActive;
          _activeJobsByOrderId = {for (final j in allActive) j.orderId: j};
          _completedJobsByOrderId = {for (final j in allCompletedToday) j.orderId: j};
          _isLoadingJobs = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading active jobs in rider chats: $e');
      if (mounted) setState(() => _isLoadingJobs = false);
    }
  }

  void _onOrderResolved() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    OrderNumberResolver.changeNotifier.removeListener(_onOrderResolved);
    _searchController.dispose();
    super.dispose();
  }

  void _openActiveJobChat(
    DispatchJob job, {
    ChatConversation? existingConversation,
  }) async {
    // Resolve customer phone / ID if missing
    String? phone = existingConversation?.getOtherParticipantPhone(_currentRiderId, 'rider');
    String? custId;
    String? address = job.address;
    String? landmark = job.landmark;

    if (phone == null || phone.isEmpty) {
      try {
        final orderRes = await SupabaseService.client
            .from('orders')
            .select('customer_id, customers(phone, address, landmark)')
            .eq('id', job.orderId)
            .maybeSingle();
        if (orderRes != null) {
          custId = orderRes['customer_id']?.toString();
          final cust = orderRes['customers'] as Map<String, dynamic>?;
          phone = cust?['phone']?.toString();
          address = address ?? cust?['address']?.toString();
          landmark = landmark ?? cust?['landmark']?.toString();
        }
      } catch (_) {}
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RiderChatDetailScreen(
          conversation: existingConversation,
          customerName: job.customerName ?? 'Customer',
          customerId: custId ?? '',
          orderId: job.orderId,
          phoneNumber: phone,
          jobType: job.jobType,
          address: address,
          landmark: landmark,
          isDispatchChat: false,
        ),
      ),
    ).then((_) => _loadActiveJobs());
  }

  void _onItemTap(_RiderChatItem item) {
    if (item.conversation != null) {
      _chatService.markAsRead(
        chatId: item.conversation!.id,
        currentUserId: _currentRiderId,
        currentRole: 'rider',
      );
    }

    if (item.isDispatch) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RiderChatDetailScreen(
            conversation: item.conversation,
            customerName: 'InfinityWash Staff',
            customerId: '',
            isDispatchChat: true,
          ),
        ),
      ).then((_) => _loadActiveJobs());
    } else if (item.job != null) {
      _openActiveJobChat(item.job!, existingConversation: item.conversation);
    } else if (item.conversation != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RiderChatDetailScreen(
            conversation: item.conversation,
            customerName: item.displayName,
            customerId: '',
            orderId: item.orderId ?? '',
            phoneNumber: item.displayPhone,
            jobType: 'delivery',
            isDispatchChat: false,
          ),
        ),
      ).then((_) => _loadActiveJobs());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isProfileLoaded) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.accentBlue),
        ),
      );
    }

    return StreamBuilder<List<ChatConversation>>(
      stream: _chatService.streamConversations(
        currentUserId: _currentRiderId,
        currentRole: 'rider',
      ),
      builder: (context, snapshot) {
        final conversations = snapshot.data ?? [];

        // 1. Shop Staff channel (Pinned)
        final dispatchConv = conversations
            .where((c) => c.chatType == ChatType.riderStaff)
            .firstOrNull;
        final dispatchItem = dispatchConv != null
            ? _RiderChatItem.dispatch(
                conversation: dispatchConv,
                currentRiderId: _currentRiderId,
              )
            : null;

        // 2. Active Customer Conversations:
        // Match conversations whose order is either an active job OR a completed job from today
        final activeConvByOrderId = <String, ChatConversation>{};
        for (final c in conversations) {
          if (c.chatType == ChatType.customerRider && c.orderId != null) {
            final hasActiveJob = _activeJobsByOrderId.containsKey(c.orderId);
            final hasCompletedJob = _completedJobsByOrderId.containsKey(c.orderId);
            if (hasActiveJob || hasCompletedJob) {
              activeConvByOrderId[c.orderId!] = c;
            }
          }
        }

        // 3. Create items for active jobs and today's completed jobs with conversations
        final List<_RiderChatItem> activeJobItems = [];
        final Set<String> processedOrderIds = {};

        // 3a. Active pending / in_progress dispatch jobs (always shown on route)
        for (final job in _activeJobs) {
          final conv = activeConvByOrderId[job.orderId];
          activeJobItems.add(_RiderChatItem.job(
            job: job,
            conversation: conv,
            currentRiderId: _currentRiderId,
          ));
          processedOrderIds.add(job.orderId);
        }

        // 3b. Today's completed jobs (shown if there is a conversation from today)
        for (final entry in _completedJobsByOrderId.entries) {
          final orderId = entry.key;
          if (processedOrderIds.contains(orderId)) continue;
          final conv = activeConvByOrderId[orderId];
          if (conv != null) {
            activeJobItems.add(_RiderChatItem.job(
              job: entry.value,
              conversation: conv,
              currentRiderId: _currentRiderId,
            ));
            processedOrderIds.add(orderId);
          }
        }

        // 3c. Any conversation whose order is still in activeConvByOrderId
        for (final conv in activeConvByOrderId.values) {
          if (conv.orderId != null && !processedOrderIds.contains(conv.orderId)) {
            activeJobItems.add(_RiderChatItem.conversationOnly(
              conversation: conv,
              currentRiderId: _currentRiderId,
            ));
            processedOrderIds.add(conv.orderId!);
          }
        }

        // Sort active jobs: unread messages first, then most recent activity
        activeJobItems.sort((a, b) {
          if (a.unreadCount > 0 && b.unreadCount == 0) return -1;
          if (a.unreadCount == 0 && b.unreadCount > 0) return 1;
          return b.sortTime.compareTo(a.sortTime);
        });

        bool isPickupItem(_RiderChatItem item) => item.job?.jobType == 'pickup';
        bool isDeliveryItem(_RiderChatItem item) => item.job?.jobType == 'delivery';

        final pickupCount = activeJobItems.where(isPickupItem).length;
        final deliveryCount = activeJobItems.where(isDeliveryItem).length;

        // 4. Apply Tab Filter
        List<_RiderChatItem> displayItems;
        if (_selectedFilterIndex == 1) {
          // Pickups
          displayItems = activeJobItems.where(isPickupItem).toList();
        } else if (_selectedFilterIndex == 2) {
          // Deliveries
          displayItems = activeJobItems.where(isDeliveryItem).toList();
        } else if (_selectedFilterIndex == 3) {
          // Shop Staff only
          displayItems = dispatchItem != null ? [dispatchItem] : [];
        } else {
          // All: Pinned Shop Staff first, followed by active route jobs & completed jobs from today
          displayItems = [
            ?dispatchItem,
            ...activeJobItems,
          ];
        }

        // 5. Apply Search Query
        if (_searchQuery.trim().isNotEmpty) {
          final q = _searchQuery.trim().toLowerCase();
          displayItems = displayItems.where((item) {
            final name = item.displayName.toLowerCase();
            final orderNum = (item.orderNumber ?? '').toLowerCase();
            final addr = (item.address ?? '').toLowerCase();
            final last = item.lastMessageText.toLowerCase();
            final task = (item.taskType ?? '').toLowerCase();
            return name.contains(q) ||
                orderNum.contains(q) ||
                addr.contains(q) ||
                last.contains(q) ||
                task.contains(q);
          }).toList();
        }

        final int totalActiveCount =
            activeJobItems.length + (dispatchItem != null ? 1 : 0);

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            title: _isSearching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search active customer, order, or staff...',
                      border: InputBorder.none,
                      hintStyle:
                          TextStyle(color: AppTheme.textLight, fontSize: 14),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  )
                : const Text(
                    'Active Chats',
                    style: TextStyle(
                      color: AppTheme.textDark,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
            actions: [
              IconButton(
                icon: Icon(
                  _isSearching ? Icons.close : Icons.search,
                  color: AppTheme.textDark,
                ),
                onPressed: () {
                  setState(() {
                    _isSearching = !_isSearching;
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
              ),
            ],
          ),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                await _loadActiveJobs();
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Filter Chips (All | Pickups | Deliveries | Shop Staff)
                  _buildFilterChips(
                    totalCount: totalActiveCount,
                    pickupCount: pickupCount,
                    deliveryCount: deliveryCount,
                    dispatchUnread: dispatchItem?.unreadCount ?? 0,
                  ),

                  // Active Route List
                  Expanded(
                    child: displayItems.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            itemCount: displayItems.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final item = displayItems[index];
                              return _buildChatItemCard(item);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChips({
    required int totalCount,
    required int pickupCount,
    required int deliveryCount,
    required int dispatchUnread,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('All', 0, count: totalCount),
            const SizedBox(width: 8),
            _buildFilterChip('Pickups', 1, count: pickupCount),
            const SizedBox(width: 8),
            _buildFilterChip('Deliveries', 2, count: deliveryCount),
            const SizedBox(width: 8),
            _buildFilterChip('Shop Staff', 3,
                count: dispatchUnread > 0 ? dispatchUnread : null,
                isUnreadBadge: dispatchUnread > 0),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    int index, {
    int? count,
    bool isUnreadBadge = false,
  }) {
    final isSelected = _selectedFilterIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _selectedFilterIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentBlue : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppTheme.accentBlue
                : AppTheme.borderGray.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.textDark,
              ),
            ),
            if (count != null && count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isUnreadBadge
                      ? AppTheme.errorRed
                      : isSelected
                          ? Colors.white.withValues(alpha: 0.25)
                          : AppTheme.softGray,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isUnreadBadge
                        ? Colors.white
                        : isSelected
                            ? Colors.white
                            : AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChatItemCard(_RiderChatItem item) {
    final bool isDispatch = item.isDispatch;
    final bool hasUnread = item.unreadCount > 0;
    final initials = _getInitials(item.displayName);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onItemTap(item),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: AppStyles.cardDecoration.copyWith(
            border: Border.all(
              color: isDispatch
                  ? AppTheme.primaryBlue.withValues(alpha: 0.35)
                  : hasUnread
                      ? AppTheme.accentBlue.withValues(alpha: 0.45)
                      : AppTheme.borderGray.withValues(alpha: 0.5),
              width: isDispatch || hasUnread ? 1.5 : 1,
            ),
            color: isDispatch
                ? AppTheme.primaryBlue.withValues(alpha: 0.03)
                : Colors.white,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar with distinctive role badge
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDispatch
                          ? AppTheme.primaryBlue
                          : item.taskColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: isDispatch
                          ? const Icon(
                              Icons.storefront,
                              color: Colors.white,
                              size: 24,
                            )
                          : Text(
                              initials,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: item.taskColor,
                              ),
                            ),
                    ),
                  ),
                  if (isDispatch)
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.headset_mic,
                          size: 13,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top line: Name + Verified/Pin Icon + Time
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  item.displayName,
                                  style: TextStyle(
                                    fontWeight: hasUnread || isDispatch
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    fontSize: 15,
                                    color: AppTheme.textDark,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isDispatch) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.verified,
                                    size: 15, color: AppTheme.primaryBlue),
                              ],
                            ],
                          ),
                        ),
                        if (item.timeAgoText.isNotEmpty)
                          Text(
                            item.timeAgoText,
                            style: TextStyle(
                              fontSize: 11,
                              color: hasUnread
                                  ? AppTheme.accentBlue
                                  : AppTheme.textLight,
                              fontWeight: hasUnread
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Badges row: Role (CUSTOMER vs SHOP STAFF) + Order # + Task
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Distinct Role Chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDispatch
                                ? AppTheme.primaryBlue.withValues(alpha: 0.12)
                                : Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isDispatch ? 'SHOP STAFF' : 'CUSTOMER',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: isDispatch
                                  ? AppTheme.primaryBlue
                                  : Colors.teal.shade800,
                            ),
                          ),
                        ),

                        // Order Number Pill (Customer chats)
                        if (item.orderNumber != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.softGray,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.orderNumber!.startsWith('#')
                                  ? item.orderNumber!
                                  : '#${item.orderNumber}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ),

                        // Task Type (Pickup vs Delivery)
                        if (item.taskType != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: item.taskColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.taskType == 'PICKUP'
                                  ? 'PICKUP'
                                  : 'DELIVERY',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: item.taskColor,
                              ),
                            ),
                          ),
                      ],
                    ),

                    // Address snippet (if available)
                    if (item.address != null && item.address!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 12, color: AppTheme.textLight),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              item.address!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textLight,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 6),

                    // Last message & unread badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.lastMessageText,
                            style: TextStyle(
                              fontSize: 13,
                              color: hasUnread
                                  ? AppTheme.textDark
                                  : item.conversation == null
                                      ? AppTheme.accentBlue
                                      : AppTheme.textLight,
                              fontWeight: hasUnread
                                  ? FontWeight.w600
                                  : item.conversation == null
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                              fontStyle: item.conversation == null
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.accentBlue,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${item.unreadCount}',
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts.last[0]).toUpperCase();
  }

  Widget _buildEmptyState() {
    final String label = _selectedFilterIndex == 1
        ? 'No Active Pickups'
        : _selectedFilterIndex == 2
            ? 'No Active Deliveries'
            : _selectedFilterIndex == 3
                ? 'No Dispatch Messages'
                : 'No Active Orders on Route';

    final String subtitle = _selectedFilterIndex == 1
        ? 'Active pickup jobs assigned to you for today will appear here.'
        : _selectedFilterIndex == 2
            ? 'Active delivery jobs assigned to you for today will appear here.'
            : _selectedFilterIndex == 3
                ? 'Use Shop Staff to communicate with the laundry shop attendants.'
                : 'When you accept a pickup or delivery job, customer chats will automatically appear here.';

    return Center(
      child: EmptyStateWidget(
        icon: _selectedFilterIndex == 1
            ? Icons.inventory_2_outlined
            : _selectedFilterIndex == 2
                ? Icons.local_shipping_outlined
                : Icons.chat_bubble_outline,
        title: label,
        subtitle: subtitle,
        actionLabel: 'Message Shop Staff',
        onAction: () async {
          final profile = await _profileService.getProfile();
          final conv = await _chatService.getOrCreateRiderStaffChat(
            riderId: _currentRiderId,
            riderName: _currentRiderName,
            riderPhone: profile['phone']?.toString(),
            riderAvatar: profile['avatar_url']?.toString(),
          );
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RiderChatDetailScreen(
                  conversation: conv,
                  customerName: 'InfinityWash Staff',
                  customerId: '',
                  isDispatchChat: true,
                ),
              ),
            );
          }
        },
      ),
    );
  }
}
