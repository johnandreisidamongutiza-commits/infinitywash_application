import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import 'rider_chat_detail_screen.dart';

class RiderChatsScreen extends StatefulWidget {
  const RiderChatsScreen({super.key});

  @override
  State<RiderChatsScreen> createState() => _RiderChatsScreenState();
}

class _RiderChatsScreenState extends State<RiderChatsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Mock data - in production, this would come from a database/API
  final List<ChatPreview> _chats = [
    ChatPreview(
      customerId: '1',
      customerName: 'Maria Santos',
      lastMessage: 'Thanks! See you soon',
      timestamp: '2m',
      unreadCount: 1,
      orderId: 'IW-105',
    ),
    ChatPreview(
      customerId: '2',
      customerName: 'Juan Dela Cruz',
      lastMessage: 'I\'ll be ready at 2pm',
      timestamp: '1h',
      unreadCount: 0,
      orderId: 'IW-106',
    ),
    ChatPreview(
      customerId: '3',
      customerName: 'Ana Reyes',
      lastMessage: 'Can you come earlier?',
      timestamp: '3h',
      unreadCount: 0,
      orderId: 'IW-107',
    ),
    ChatPreview(
      customerId: '4',
      customerName: 'Pedro Garcia',
      lastMessage: 'Got it, thanks!',
      timestamp: 'Yesterday',
      unreadCount: 0,
      orderId: 'IW-104',
    ),
  ];

  List<ChatPreview> get _filteredChats {
    if (_searchQuery.isEmpty) return _chats;
    return _chats.where((chat) => 
      chat.customerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
      (chat.orderId?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Chats'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              setState(() {
                _searchQuery = '';
                _searchController.clear();
              });
              _showSearchDialog();
            },
          ),
        ],
      ),
      body: _filteredChats.isEmpty && _searchQuery.isNotEmpty
          ? _buildEmptySearch()
          : _chats.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: _filteredChats.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _buildChatCard(_filteredChats[index]),
                ),
    );
  }

  Widget _buildChatCard(ChatPreview chat) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RiderChatDetailScreen(
                customerName: chat.customerName,
                customerId: chat.customerId,
                orderId: chat.orderId,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: AppStyles.cardDecoration,
          child: Row(
            children: [
              // Avatar
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppTheme.lightBlue,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    chat.customerName[0].toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.accentBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Message Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          chat.customerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          chat.timestamp,
                          style: TextStyle(
                            color: chat.unreadCount > 0 ? AppTheme.accentBlue : AppTheme.textLight,
                            fontSize: 11,
                            fontWeight: chat.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.lastMessage,
                            style: TextStyle(
                              fontSize: 13,
                              color: chat.unreadCount > 0 ? AppTheme.textDark : AppTheme.textLight,
                              fontWeight: chat.unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (chat.unreadCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.errorRed,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${chat.unreadCount}',
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
                    if (chat.orderId != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Order ${chat.orderId}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.accentBlue,
                          fontWeight: FontWeight.w500,
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 100,
              color: AppTheme.textLight.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 24),
            Text(
              'No conversations yet',
              style: AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(
                color: AppTheme.textLight,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Your customer messages will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textLight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySearch() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: AppTheme.textLight.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 24),
            Text(
              'No results found',
              style: AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(
                color: AppTheme.textLight,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No chats match "$_searchQuery"',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textLight),
            ),
          ],
        ),
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search Chats'),
        content: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'Enter customer name or order ID',
            prefixIcon: Icon(Icons.search),
          ),
          autofocus: true,
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
            Navigator.pop(context);
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _searchQuery = '';
                _searchController.clear();
              });
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class ChatPreview {
  final String customerId;
  final String customerName;
  final String lastMessage;
  final String timestamp;
  final int unreadCount;
  final String? orderId;

  ChatPreview({
    required this.customerId,
    required this.customerName,
    required this.lastMessage,
    required this.timestamp,
    required this.unreadCount,
    this.orderId,
  });
}
