import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../../models/chat_model.dart';
import '../../../services/firebase_chat_service.dart';
import 'staff_chat_detail_screen.dart';

class StaffChatsScreen extends StatefulWidget {
  const StaffChatsScreen({super.key});

  @override
  State<StaffChatsScreen> createState() => _StaffChatsScreenState();
}

class _StaffChatsScreenState extends State<StaffChatsScreen> {
  final FirebaseChatService _chatService = FirebaseChatService.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;
  int _selectedFilterIndex = 0; // 0: All, 1: Customers, 2: Riders

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChatConversation>>(
      stream: _chatService.streamConversations(
        currentUserId: '',
        currentRole: 'staff',
      ),
      builder: (context, snapshot) {
        final allConversations = snapshot.data ?? [];
        final totalUnread = allConversations.fold<int>(
          0,
          (sum, c) => sum + c.getUnreadCount('', 'staff'),
        );

        final filtered = _filterConversations(allConversations);

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
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Chats',
                        style: TextStyle(
                          color: AppTheme.textDark,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (totalUnread > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accentBlue,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$totalUnread',
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
                icon: Icon(
                  _isSearching ? Icons.close : Icons.search,
                  color: AppTheme.textDark,
                ),
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
                if (!_isSearching) _buildFilterTabs(allConversations),
                if (!_isSearching && totalUnread > 0)
                  _buildUrgentMessagesBanner(allConversations, totalUnread),
                Expanded(
                  child: snapshot.connectionState == ConnectionState.waiting &&
                          allConversations.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.accentBlue,
                          ),
                        )
                      : filtered.isEmpty
                          ? _buildEmptyState()
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showNewChatModal(context),
            backgroundColor: AppTheme.accentBlue,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.edit_outlined, size: 20),
            label: const Text(
              'New Chat',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
    );
  }

  void _showNewChatModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _NewChatModalSheet(),
    );
  }

  List<ChatConversation> _filterConversations(
      List<ChatConversation> conversations) {
    List<ChatConversation> filtered = conversations;

    if (_selectedFilterIndex == 1) {
      filtered = filtered
          .where((c) => c.chatType == ChatType.customerSupport)
          .toList();
    } else if (_selectedFilterIndex == 2) {
      filtered = filtered
          .where((c) =>
              c.chatType == ChatType.riderStaff ||
              c.chatType == ChatType.customerRider)
          .toList();
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      filtered = filtered.where((c) {
        final name = c.getOtherParticipantName('', 'staff').toLowerCase();
        final order = (c.orderId ?? '').toLowerCase();
        final lastMsg = c.lastMessage.toLowerCase();
        return name.contains(q) || order.contains(q) || lastMsg.contains(q);
      }).toList();
    }

    return filtered;
  }

  Widget _buildFilterTabs(List<ChatConversation> all) {
    final customerCount =
        all.where((c) => c.chatType == ChatType.customerSupport).length;
    final riderCount = all
        .where((c) =>
            c.chatType == ChatType.riderStaff ||
            c.chatType == ChatType.customerRider)
        .length;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          _buildFilterChip('All', 0, all.length),
          const SizedBox(width: 8),
          _buildFilterChip('Customers', 1, customerCount),
          const SizedBox(width: 8),
          _buildFilterChip('Riders', 2, riderCount),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, int index, int count) {
    final isSelected = _selectedFilterIndex == index;

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
          ),
        ),
      ),
    );
  }

  Widget _buildUrgentMessagesBanner(
      List<ChatConversation> all, int totalUnread) {
    final unreadConvs =
        all.where((c) => c.getUnreadCount('', 'staff') > 0).length;

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
            child: const Icon(Icons.notifications_active,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$totalUnread Unread Message${totalUnread > 1 ? 's' : ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppTheme.accentBlue,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$unreadConvs conversation${unreadConvs > 1 ? 's' : ''} need${unreadConvs == 1 ? 's' : ''} attention',
                  style:
                      const TextStyle(fontSize: 11, color: AppTheme.textLight),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios,
              size: 14, color: AppTheme.accentBlue),
        ],
      ),
    );
  }

  Widget _buildChatCard(ChatConversation conversation) {
    final otherName = conversation.getOtherParticipantName('', 'staff');
    final otherRole = conversation.getOtherParticipantRole('', 'staff');
    final isCustomer =
        conversation.chatType == ChatType.customerSupport;
    final unreadCount = conversation.getUnreadCount('', 'staff');
    final hasUnread = unreadCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StaffChatDetailScreen(
                conversation: conversation,
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
                            color: isCustomer
                                ? AppTheme.accentBlue.withValues(alpha: 0.08)
                                : AppTheme.teamMemberIconOrange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            otherRole,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isCustomer
                                  ? AppTheme.accentBlue
                                  : AppTheme.teamMemberIconOrange,
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
                              '$unreadCount',
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
    return const Center(
      child: EmptyStateWidget(
        icon: Icons.chat_bubble_outline,
        title: 'No Conversations Found',
        subtitle: 'Customer and rider messages will appear here in real-time.',
      ),
    );
  }
}

class _NewChatModalSheet extends StatefulWidget {
  const _NewChatModalSheet();

  @override
  State<_NewChatModalSheet> createState() => _NewChatModalSheetState();
}

class _NewChatModalSheetState extends State<_NewChatModalSheet> {
  final FirebaseChatService _chatService = FirebaseChatService.instance;
  final TextEditingController _searchController = TextEditingController();

  String _selectedRole = 'customer'; // 'customer' or 'rider'
  String _searchQuery = '';
  List<Map<String, dynamic>> _recipients = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchRecipients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchRecipients() async {
    setState(() => _isLoading = true);
    try {
      final results = await _chatService.searchChatRecipients(
        role: _selectedRole,
        query: _searchQuery,
      );
      if (mounted) {
        setState(() {
          _recipients = results;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startChatWith(Map<String, dynamic> recipient) async {
    final id = recipient['id']?.toString() ?? '';
    if (id.isEmpty) return;

    final first = recipient['first_name']?.toString() ?? '';
    final last = recipient['last_name']?.toString() ?? '';
    final fullName = '$first $last'.trim().isNotEmpty ? '$first $last'.trim() : 'User';
    final phone = recipient['phone']?.toString();
    final avatar = recipient['avatar_url']?.toString();

    Navigator.pop(context); // Close modal

    ChatConversation conv;
    if (_selectedRole == 'customer') {
      conv = await _chatService.getOrCreateSupportChat(
        customerId: id,
        customerName: fullName,
        customerPhone: phone,
        customerAvatar: avatar,
      );
    } else {
      conv = await _chatService.getOrCreateRiderStaffChat(
        riderId: id,
        riderName: fullName,
        riderPhone: phone,
        riderAvatar: avatar,
      );
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StaffChatDetailScreen(conversation: conv),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75 + keyboardPadding,
      ),
      margin: EdgeInsets.only(bottom: keyboardPadding),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.borderGray,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start a Conversation',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Choose a customer or delivery rider to message',
                      style: TextStyle(fontSize: 12, color: AppTheme.textLight),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textLight),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _buildRoleButton('Customers', 'customer'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildRoleButton('Riders', 'rider'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  icon: Icon(Icons.search, size: 20, color: AppTheme.textLight),
                  hintText: 'Search by name or phone...',
                  hintStyle: TextStyle(fontSize: 13, color: AppTheme.textLight),
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  _searchQuery = val;
                  _fetchRecipients();
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.accentBlue),
                  )
                : _recipients.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isEmpty
                              ? 'No ${_selectedRole}s found'
                              : 'No matches for "$_searchQuery"',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textLight,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        itemCount: _recipients.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final p = _recipients[index];
                          final first = p['first_name']?.toString() ?? '';
                          final last = p['last_name']?.toString() ?? '';
                          final name = '$first $last'.trim().isNotEmpty ? '$first $last'.trim() : 'User';
                          final phone = p['phone']?.toString() ?? '';
                          final isCust = _selectedRole == 'customer';

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 4),
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isCust
                                    ? AppTheme.accentBlue.withValues(alpha: 0.1)
                                    : AppTheme.lightBlue,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isCust ? Icons.person : Icons.delivery_dining,
                                color: AppTheme.accentBlue,
                                size: 22,
                              ),
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppTheme.textDark,
                              ),
                            ),
                            subtitle: Text(
                              phone.isNotEmpty ? phone : 'No phone number',
                              style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.accentBlue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Text(
                                'Message',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.accentBlue,
                                ),
                              ),
                            ),
                            onTap: () => _startChatWith(p),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleButton(String label, String role) {
    final isSelected = _selectedRole == role;

    return GestureDetector(
      onTap: () {
        if (_selectedRole != role) {
          setState(() {
            _selectedRole = role;
            _recipients = [];
          });
          _fetchRecipients();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentBlue : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppTheme.accentBlue
                : AppTheme.borderGray.withValues(alpha: 0.6),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppTheme.textDark,
          ),
        ),
      ),
    );
  }
}

