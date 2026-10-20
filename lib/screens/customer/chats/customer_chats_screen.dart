import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../../models/chat_model.dart';
import '../../../services/firebase_chat_service.dart';
import '../../../services/profile_service.dart';
import 'customer_chat_detail_screen.dart';

class CustomerChatsScreen extends StatefulWidget {
  const CustomerChatsScreen({super.key});

  @override
  State<CustomerChatsScreen> createState() => _CustomerChatsScreenState();
}

class _CustomerChatsScreenState extends State<CustomerChatsScreen> {
  final FirebaseChatService _chatService = FirebaseChatService.instance;
  final ProfileService _profileService = ProfileService();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  bool _isSearching = false;
  String _currentCustomerId = '';
  String _currentCustomerName = 'Customer';
  bool _isProfileLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadProfileAndEnsureSupportChat();
  }

  Future<void> _loadProfileAndEnsureSupportChat() async {
    try {
      final profile = await _profileService.getProfile();
      final customerId = profile['id']?.toString() ?? '';
      final first = profile['first_name']?.toString() ?? '';
      final last = profile['last_name']?.toString() ?? '';
      final name = '$first $last'.trim();
      final phone = profile['phone']?.toString();
      final avatar = profile['avatar_url']?.toString();

      if (mounted) {
        setState(() {
          _currentCustomerId = customerId;
          _currentCustomerName = name.isNotEmpty ? name : 'Customer';
          _isProfileLoaded = true;
        });
      }

      // Ensure that InfinityWash Support channel exists for this customer
      if (customerId.isNotEmpty) {
        await _chatService.getOrCreateSupportChat(
          customerId: customerId,
          customerName: _currentCustomerName,
          customerPhone: phone,
          customerAvatar: avatar,
        );
      }
    } catch (e) {
      debugPrint('Error loading customer profile for chats: $e');
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
        currentUserId: _currentCustomerId,
        currentRole: 'customer',
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
          c.getOtherParticipantName(_currentCustomerId, 'customer').toLowerCase();
      final role =
          c.getOtherParticipantRole(_currentCustomerId, 'customer').toLowerCase();
      final order = (c.orderId ?? '').toLowerCase();
      final lastMsg = c.lastMessage.toLowerCase();
      return name.contains(q) ||
          role.contains(q) ||
          order.contains(q) ||
          lastMsg.contains(q);
    }).toList();
  }

  Widget _buildChatCard(ChatConversation conversation) {
    final bool isRider = conversation.chatType == ChatType.customerRider;
    final otherName =
        conversation.getOtherParticipantName(_currentCustomerId, 'customer');
    final otherRole =
        conversation.getOtherParticipantRole(_currentCustomerId, 'customer');
    final otherPhone =
        conversation.getOtherParticipantPhone(_currentCustomerId, 'customer');
    final int unread =
        conversation.getUnreadCount(_currentCustomerId, 'customer');
    final bool hasUnread = unread > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _chatService.markAsRead(
            chatId: conversation.id,
            currentUserId: _currentCustomerId,
            currentRole: 'customer',
          );
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CustomerChatDetailScreen(
                conversation: conversation,
                recipientName: otherName,
                recipientRole: otherRole,
                recipientType: isRider
                    ? ChatRecipientType.rider
                    : ChatRecipientType.support,
                orderId: conversation.orderId,
                phoneNumber: otherPhone,
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
                  color: isRider
                      ? AppTheme.lightBlue
                      : AppTheme.accentBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isRider ? Icons.delivery_dining : Icons.support_agent,
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
                            color: isRider
                                ? AppTheme.accentBlue.withValues(alpha: 0.08)
                                : AppTheme.accentBlue.withValues(alpha: 0.12),
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
            'Start a conversation with InfinityWash Support or your assigned rider.',
        actionLabel: 'Chat Support',
        onAction: () async {
          final profile = await _profileService.getProfile();
          final conv = await _chatService.getOrCreateSupportChat(
            customerId: _currentCustomerId,
            customerName: _currentCustomerName,
            customerPhone: profile['phone']?.toString(),
            customerAvatar: profile['avatar_url']?.toString(),
          );
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CustomerChatDetailScreen(
                  conversation: conv,
                ),
              ),
            );
          }
        },
      ),
    );
  }
}
