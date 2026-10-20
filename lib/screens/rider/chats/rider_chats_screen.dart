import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../../models/chat_model.dart';
import '../../../services/firebase_chat_service.dart';
import '../../../services/profile_service.dart';
import 'rider_chat_detail_screen.dart';

class RiderChatsScreen extends StatefulWidget {
  const RiderChatsScreen({super.key});

  @override
  State<RiderChatsScreen> createState() => _RiderChatsScreenState();
}

class _RiderChatsScreenState extends State<RiderChatsScreen> {
  final FirebaseChatService _chatService = FirebaseChatService.instance;
  final ProfileService _profileService = ProfileService();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  bool _isSearching = false;
  String _currentRiderId = '';
  String _currentRiderName = 'Rider';
  bool _isProfileLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadProfileAndEnsureDispatchChat();
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

      // Ensure that InfinityWash Dispatch channel exists for this rider
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
        final filtered = _filterChats(conversations);

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
                      hintText: 'Search chats or order ID...',
                      border: InputBorder.none,
                      hintStyle:
                          TextStyle(color: AppTheme.textLight, fontSize: 14),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  )
                : const Text(
                    'Chats',
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
            child: Column(
              children: [
                Expanded(
                  child: filtered.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            return _buildChatCard(filtered[index]);
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<ChatConversation> _filterChats(List<ChatConversation> chats) {
    if (_searchQuery.trim().isEmpty) return chats;
    final q = _searchQuery.trim().toLowerCase();
    return chats.where((c) {
      final name =
          c.getOtherParticipantName(_currentRiderId, 'rider').toLowerCase();
      final role =
          c.getOtherParticipantRole(_currentRiderId, 'rider').toLowerCase();
      final order = (c.orderId ?? '').toLowerCase();
      final lastMsg = c.lastMessage.toLowerCase();
      return name.contains(q) ||
          role.contains(q) ||
          order.contains(q) ||
          lastMsg.contains(q);
    }).toList();
  }

  Widget _buildChatCard(ChatConversation conversation) {
    final bool isDispatch =
        conversation.chatType == ChatType.riderStaff;
    final otherName =
        conversation.getOtherParticipantName(_currentRiderId, 'rider');
    final otherRole =
        conversation.getOtherParticipantRole(_currentRiderId, 'rider');
    final otherPhone =
        conversation.getOtherParticipantPhone(_currentRiderId, 'rider');
    final int unread =
        conversation.getUnreadCount(_currentRiderId, 'rider');
    final bool hasUnread = unread > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _chatService.markAsRead(
            chatId: conversation.id,
            currentUserId: _currentRiderId,
            currentRole: 'rider',
          );
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RiderChatDetailScreen(
                conversation: conversation,
                customerName: otherName,
                customerId: '',
                orderId: conversation.orderId,
                phoneNumber: otherPhone,
                isDispatchChat: isDispatch,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: AppStyles.cardDecoration.copyWith(
            border: hasUnread
                ? Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isDispatch
                      ? AppTheme.accentBlue.withValues(alpha: 0.12)
                      : AppTheme.lightBlue,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDispatch ? Icons.support_agent : Icons.person,
                  color: AppTheme.accentBlue,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            otherName,
                            style: TextStyle(
                              fontWeight:
                                  hasUnread ? FontWeight.bold : FontWeight.w600,
                              fontSize: 15,
                              color: AppTheme.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          conversation.timeAgo,
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
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDispatch
                                ? AppTheme.accentBlue.withValues(alpha: 0.1)
                                : AppTheme.lightBlue,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            otherRole,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accentBlue,
                            ),
                          ),
                        ),
                        if (conversation.orderId != null &&
                            conversation.orderId!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.softGray,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '#${conversation.orderId}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.lastMessage.isEmpty
                                ? 'No messages yet'
                                : conversation.lastMessage,
                            style: TextStyle(
                              fontSize: 13,
                              color: hasUnread
                                  ? AppTheme.textDark
                                  : AppTheme.textLight,
                              fontWeight: hasUnread
                                  ? FontWeight.w600
                                  : FontWeight.normal,
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
                              '$unread',
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

  Widget _buildEmptyState() {
    return Center(
      child: EmptyStateWidget(
        icon: Icons.chat_bubble_outline,
        title: 'No Conversations Yet',
        subtitle:
            'Assigned customer orders and dispatch support will appear here.',
        actionLabel: 'Chat Dispatch',
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
                  customerName: 'InfinityWash Dispatch',
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
