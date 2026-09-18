import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/staff_chat.dart';
import '../../../services/chat_service.dart';
import 'staff_chat_detail_screen.dart';

class StaffChatsScreen extends StatefulWidget {
  const StaffChatsScreen({super.key});

  @override
  State<StaffChatsScreen> createState() => _StaffChatsScreenState();
}

class _StaffChatsScreenState extends State<StaffChatsScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;
  int _selectedFilterIndex = 0; // 0: All, 1: Customers, 2: Riders

  List<StaffConversation> get _filteredConversations {
    List<StaffConversation> conversations;

    // Apply type filter
    if (_selectedFilterIndex == 1) {
      conversations = _chatService.getConversationsByType(ChatParticipantType.customer);
    } else if (_selectedFilterIndex == 2) {
      conversations = _chatService.getConversationsByType(ChatParticipantType.rider);
    } else {
      conversations = _chatService.getConversations();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      conversations = _chatService.searchConversations(_searchQuery);
      
      // Re-apply type filter after search
      if (_selectedFilterIndex == 1) {
        conversations = conversations
            .where((c) => c.participant.type == ChatParticipantType.customer)
            .toList();
      } else if (_selectedFilterIndex == 2) {
        conversations = conversations
            .where((c) => c.participant.type == ChatParticipantType.rider)
            .toList();
      }
    }

    // Sort by last message time (most recent first)
    conversations.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

    return conversations;
  }

  int get _totalUnreadCount => _chatService.getTotalUnreadCount();

  @override
  Widget build(BuildContext context) {
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
                  hintStyle: TextStyle(color: AppTheme.textLight, fontSize: 14),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Chats'),
                  if (_totalUnreadCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.errorRed,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_totalUnreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: AppTheme.textDark),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Filter Tabs
            if (!_isSearching) _buildFilterTabs(),

            // Urgent Messages Banner
            if (!_isSearching && _totalUnreadCount > 0) _buildUrgentMessagesBanner(),

            // Chat List
            Expanded(
              child: _filteredConversations.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _refreshConversations,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        itemCount: _filteredConversations.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          return _buildChatCard(_filteredConversations[index]);
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          _buildFilterChip('All', 0),
          const SizedBox(width: 8),
          _buildFilterChip('Customers', 1),
          const SizedBox(width: 8),
          _buildFilterChip('Riders', 2),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _selectedFilterIndex == index;
    int count = 0;

    if (index == 0) {
      count = _chatService.getConversations().length;
    } else if (index == 1) {
      count = _chatService.getConversationsByType(ChatParticipantType.customer).length;
    } else {
      count = _chatService.getConversationsByType(ChatParticipantType.rider).length;
    }

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilterIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.accentBlue : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppTheme.accentBlue
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
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          ),
        ),
      ),
    );
  }

  Widget _buildUrgentMessagesBanner() {
    final unreadConversations = _chatService
        .getConversations()
        .where((c) => c.unreadCount > 0)
        .toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accentBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.accentBlue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.notifications_active, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_totalUnreadCount Unread Message${_totalUnreadCount > 1 ? 's' : ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppTheme.accentBlue,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${unreadConversations.length} conversation${unreadConversations.length > 1 ? 's' : ''} need${unreadConversations.length == 1 ? 's' : ''} your attention',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.accentBlue),
        ],
      ),
    );
  }

  Widget _buildChatCard(StaffConversation conversation) {
    final isCustomer = conversation.participant.type == ChatParticipantType.customer;
    final hasUnread = conversation.unreadCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StaffChatDetailScreen(
                conversation: conversation,
              ),
            ),
          );
          // Refresh the list when returning
          setState(() {});
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
              // Avatar with online indicator
              Stack(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: isCustomer
                          ? AppTheme.accentBlue.withValues(alpha: 0.1)
                          : AppTheme.lightBlue,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isCustomer ? Icons.person : Icons.delivery_dining,
                      color: AppTheme.accentBlue,
                      size: 26,
                    ),
                  ),
                  if (conversation.participant.isOnline)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // Message Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  conversation.participant.name,
                                  style: TextStyle(
                                    fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
                                    fontSize: 15,
                                    color: AppTheme.textDark,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (conversation.orderId != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isCustomer
                                        ? Colors.blue.withValues(alpha: 0.1)
                                        : Colors.orange.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    conversation.orderId!,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: isCustomer ? AppTheme.accentBlue : Colors.orange,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Text(
                          conversation.timeAgo,
                          style: TextStyle(
                            fontSize: 11,
                            color: hasUnread ? AppTheme.accentBlue : AppTheme.textLight,
                            fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      conversation.participant.role,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textLight.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            conversation.lastMessage,
                            style: TextStyle(
                              fontSize: 13,
                              color: hasUnread ? AppTheme.textDark : AppTheme.textLight,
                              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasUnread)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: const BoxDecoration(
                              color: AppTheme.accentBlue,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${conversation.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (conversation.orderStatus != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _getStatusColor(conversation.orderStatus!).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          conversation.orderStatus!,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _getStatusColor(conversation.orderStatus!),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'processing':
      case 'ready':
        return AppTheme.teamMemberIconOrange;
      case 'pending':
        return AppTheme.accentBlue;
      case 'out for delivery':
        return Colors.purple;
      default:
        return AppTheme.textLight;
    }
  }

  Widget _buildEmptyState() {
    String message;
    if (_searchQuery.isNotEmpty) {
      message = 'No conversations found for "$_searchQuery"';
    } else if (_selectedFilterIndex == 1) {
      message = 'No customer conversations yet';
    } else if (_selectedFilterIndex == 2) {
      message = 'No rider conversations yet';
    } else {
      message = 'No conversations yet';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 60,
            color: AppTheme.textLight.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Messages with customers and riders will appear here.',
            style: TextStyle(fontSize: 12, color: AppTheme.textLight),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _refreshConversations() async {
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
