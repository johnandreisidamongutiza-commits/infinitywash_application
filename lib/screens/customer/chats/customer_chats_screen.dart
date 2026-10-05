import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/empty_state_widget.dart';
import 'customer_chat_detail_screen.dart';

class CustomerChatsScreen extends StatefulWidget {
  const CustomerChatsScreen({super.key});

  @override
  State<CustomerChatsScreen> createState() => _CustomerChatsScreenState();
}

class _CustomerChatsScreenState extends State<CustomerChatsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;

  final List<Map<String, dynamic>> _chatConversations = [
    {
      'id': 'rider_michael',
      'name': 'Michael Rider',
      'role': 'Assigned Delivery Rider',
      'type': ChatRecipientType.rider,
      'orderId': 'IW-105',
      'phone': '+63 912 345 6789',
      'lastMessage': 'Thanks! See you soon',
      'time': '2m ago',
      'unreadCount': 1,
      'isOnline': true,
      'tag': 'Active Delivery',
    },
    {
      'id': 'support_desk',
      'name': 'InfinityWash Support',
      'role': 'Official Store Helpdesk',
      'type': ChatRecipientType.support,
      'orderId': 'IW-105',
      'phone': '0912-345-6789',
      'lastMessage': 'Hello! Welcome to InfinityWash Support. 🫧 How can we assist you?',
      'time': '2h ago',
      'unreadCount': 0,
      'isOnline': true,
      'tag': 'Helpdesk',
    },
  ];

  List<Map<String, dynamic>> get _filteredChats {
    if (_searchQuery.isEmpty) return _chatConversations;
    final q = _searchQuery.toLowerCase();
    return _chatConversations.where((c) {
      final name = (c['name'] as String).toLowerCase();
      final role = (c['role'] as String).toLowerCase();
      final order = (c['orderId'] as String? ?? '').toLowerCase();
      return name.contains(q) || role.contains(q) || order.contains(q);
    }).toList();
  }

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
            : const Text('Chats'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: AppTheme.textDark),
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
            // Active Order Quick Card
            if (!_isSearching) _buildActiveOrderShortcut(),

            // Chat List
            Expanded(
              child: _filteredChats.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: _filteredChats.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return _buildChatCard(_filteredChats[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveOrderShortcut() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 16),
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
            child: const Icon(Icons.delivery_dining, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order #IW-105 In Progress',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.accentBlue),
                ),
                SizedBox(height: 2),
                Text(
                  'Michael Rider is delivering your clothes • Est. 4:00 PM',
                  style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CustomerChatDetailScreen(
                    recipientName: 'Michael Rider',
                    recipientRole: 'Assigned Delivery Rider',
                    recipientType: ChatRecipientType.rider,
                    orderId: 'IW-105',
                    phoneNumber: '+63 912 345 6789',
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Chat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildChatCard(Map<String, dynamic> chat) {
    final bool isRider = chat['type'] == ChatRecipientType.rider;
    final int unread = chat['unreadCount'] as int;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            chat['unreadCount'] = 0;
          });
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CustomerChatDetailScreen(
                recipientName: chat['name'],
                recipientRole: chat['role'],
                recipientType: chat['type'],
                orderId: chat['orderId'],
                phoneNumber: chat['phone'],
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: AppStyles.cardDecoration,
          child: Row(
            children: [
              // Avatar with online dot
              Stack(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: isRider ? AppTheme.lightBlue : AppTheme.accentBlue.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isRider ? Icons.delivery_dining : Icons.support_agent,
                      color: AppTheme.accentBlue,
                      size: 26,
                    ),
                  ),
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
                                  chat['name'],
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isRider
                                      ? Colors.blue.withValues(alpha: 0.1)
                                      : Colors.orange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  chat['tag'],
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: isRider ? AppTheme.accentBlue : Colors.orange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          chat['time'],
                          style: TextStyle(
                            fontSize: 11,
                            color: unread > 0 ? AppTheme.accentBlue : AppTheme.textLight,
                            fontWeight: unread > 0 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            chat['lastMessage'],
                            style: TextStyle(
                              fontSize: 13,
                              color: unread > 0 ? AppTheme.textDark : AppTheme.textLight,
                              fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (unread > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: const BoxDecoration(
                              color: AppTheme.accentBlue,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$unread',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
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
    // Searching with no matches → search-specific empty state naming the query.
    if (_isSearching && _searchQuery.isNotEmpty) {
      return EmptyStateWidget.search(query: _searchQuery, what: 'chats');
    }
    return const EmptyStateWidget(
      icon: Icons.chat_bubble_outline,
      title: 'No conversations found',
      subtitle: 'Your chats with riders and support will appear here.',
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
