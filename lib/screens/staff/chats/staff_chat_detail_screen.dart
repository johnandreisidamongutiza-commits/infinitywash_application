import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/staff_chat.dart';
import '../../../services/chat_service.dart';
import '../../../widgets/top_notification.dart';

class StaffChatDetailScreen extends StatefulWidget {
  final StaffConversation conversation;

  const StaffChatDetailScreen({
    super.key,
    required this.conversation,
  });

  @override
  State<StaffChatDetailScreen> createState() => _StaffChatDetailScreenState();
}

class _StaffChatDetailScreenState extends State<StaffChatDetailScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late List<StaffChatMessage> _messages;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _markAsRead();
  }

  void _loadMessages() {
    _messages = _chatService.getMessages(widget.conversation.id);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _markAsRead() {
    _chatService.markAsRead(widget.conversation.id);
  }

  void _sendMessage([String? quickText]) {
    final text = quickText ?? _textController.text.trim();
    if (text.isEmpty) return;

    if (quickText == null) {
      _textController.clear();
    }

    setState(() {
      _chatService.sendMessage(
        conversationId: widget.conversation.id,
        text: text,
        isFromStaff: true,
      );
      _messages = _chatService.getMessages(widget.conversation.id);
    });

    _scrollToBottom();
    _simulateReply(text);
  }

  void _simulateReply(String staffMessage) {
    setState(() => _isTyping = true);

    Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;

      String replyText = _generateReply(staffMessage);

      setState(() {
        _isTyping = false;
        _chatService.sendMessage(
          conversationId: widget.conversation.id,
          text: replyText,
          isFromStaff: false,
        );
        _messages = _chatService.getMessages(widget.conversation.id);
      });

      _scrollToBottom();
    });
  }

  String _generateReply(String staffMessage) {
    final isCustomer = widget.conversation.participant.type == ChatParticipantType.customer;
    final lower = staffMessage.toLowerCase();

    if (isCustomer) {
      if (lower.contains('ready') || lower.contains('4:00') || lower.contains('completed')) {
        return 'Thank you for the update! I\'ll be waiting.';
      } else if (lower.contains('address') || lower.contains('noted')) {
        return 'Great, thank you for confirming!';
      } else if (lower.contains('delay') || lower.contains('sorry')) {
        return 'No problem, I understand. Thanks for letting me know.';
      } else if (lower.contains('pickup') || lower.contains('collect')) {
        return 'What time can I come to pick it up?';
      } else {
        return 'Okay, got it. Thanks!';
      }
    } else {
      // Rider responses
      if (lower.contains('pick') || lower.contains('deliver')) {
        return 'Copy that! On my way now.';
      } else if (lower.contains('customer') || lower.contains('contact')) {
        return 'I\'ll try calling the customer again.';
      } else if (lower.contains('address') || lower.contains('location')) {
        return 'Understood. I have the updated location.';
      } else if (lower.contains('complete') || lower.contains('done')) {
        return 'Order delivered successfully!';
      } else {
        return 'Acknowledged. Will do!';
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<String> get _quickReplyTemplates {
    final isCustomer = widget.conversation.participant.type == ChatParticipantType.customer;

    if (isCustomer) {
      return [
        'Your order is ready for pickup',
        'Order will be completed by 4:00 PM',
        'Address change noted',
        'Please confirm your delivery address',
      ];
    } else {
      return [
        'Please pick up order from the shop',
        'Deliver to customer immediately',
        'Contact customer for exact location',
        'Mark as completed when delivered',
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCustomer = widget.conversation.participant.type == ChatParticipantType.customer;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Stack(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isCustomer
                        ? AppTheme.accentBlue.withValues(alpha: 0.1)
                        : AppTheme.lightBlue,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isCustomer ? Icons.person : Icons.delivery_dining,
                    color: AppTheme.accentBlue,
                    size: 22,
                  ),
                ),
                if (widget.conversation.participant.isOnline)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.conversation.participant.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppTheme.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.conversation.participant.role,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              final phone = widget.conversation.participant.phone ?? '0912-345-6789';
              showTopNotification(
                context,
                message: 'Calling ${widget.conversation.participant.name} ($phone)...',
                icon: Icons.phone,
                backgroundColor: AppTheme.accentBlue,
              );
            },
            icon: const Icon(Icons.phone_outlined, color: AppTheme.accentBlue),
            tooltip: 'Call',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppTheme.textDark),
            onSelected: (val) {
              if (val == 'order' && widget.conversation.orderId != null) {
                showTopNotification(
                  context,
                  message: 'Opening order ${widget.conversation.orderId}...',
                  icon: Icons.receipt_long,
                  backgroundColor: AppTheme.accentBlue,
                );
              } else if (val == 'block') {
                showTopNotification(
                  context,
                  message: '${widget.conversation.participant.name} has been blocked.',
                  icon: Icons.block,
                  backgroundColor: AppTheme.errorRed,
                );
              }
            },
            itemBuilder: (ctx) => [
              if (widget.conversation.orderId != null)
                PopupMenuItem(
                  value: 'order',
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long, size: 18, color: AppTheme.accentBlue),
                      const SizedBox(width: 10),
                      Text('View Order ${widget.conversation.orderId}'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'block',
                child: Row(
                  children: [
                    Icon(Icons.block, size: 18, color: AppTheme.errorRed),
                    SizedBox(width: 10),
                    Text('Block Contact'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Order Context Banner (if associated with order)
            if (widget.conversation.orderId != null) _buildOrderContextBanner(),

            // Message Stream
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length && _isTyping) {
                    return _buildTypingIndicator();
                  }
                  return _buildMessageBubble(_messages[index]);
                },
              ),
            ),

            // Quick Reply Templates
            _buildQuickTemplatesBar(),

            // Bottom Input Bar
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderContextBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.softGray.withValues(alpha: 0.8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.accentBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.local_laundry_service,
              color: AppTheme.accentBlue,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order ${widget.conversation.orderId}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: AppTheme.textDark,
                  ),
                ),
                if (widget.conversation.orderStatus != null)
                  Text(
                    'Status: ${widget.conversation.orderStatus}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                  ),
              ],
            ),
          ),
          if (widget.conversation.orderStatus != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _getStatusColor(widget.conversation.orderStatus!).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.conversation.orderStatus!,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _getStatusColor(widget.conversation.orderStatus!),
                ),
              ),
            ),
        ],
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

  Widget _buildMessageBubble(StaffChatMessage message) {
    final isStaff = message.isFromStaff;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isStaff ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isStaff) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: widget.conversation.participant.type == ChatParticipantType.customer
                  ? AppTheme.accentBlue.withValues(alpha: 0.1)
                  : AppTheme.lightBlue,
              child: Icon(
                widget.conversation.participant.type == ChatParticipantType.customer
                    ? Icons.person
                    : Icons.delivery_dining,
                size: 16,
                color: AppTheme.accentBlue,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isStaff ? AppTheme.accentBlue : AppTheme.softGray,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isStaff ? 16 : 4),
                  bottomRight: Radius.circular(isStaff ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: isStaff ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: TextStyle(
                      fontSize: 14,
                      color: isStaff ? Colors.white : AppTheme.textDark,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.timestamp),
                        style: TextStyle(
                          fontSize: 10,
                          color: isStaff ? Colors.white70 : AppTheme.textLight,
                        ),
                      ),
                      if (isStaff) ...[
                        const SizedBox(width: 4),
                        Icon(
                          message.isRead ? Icons.done_all : Icons.done,
                          size: 12,
                          color: Colors.white70,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    final isCustomer = widget.conversation.participant.type == ChatParticipantType.customer;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: isCustomer
                ? AppTheme.accentBlue.withValues(alpha: 0.1)
                : AppTheme.lightBlue,
            child: const Icon(Icons.more_horiz, size: 16, color: AppTheme.textLight),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.softGray,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.conversation.participant.name} is typing...',
                  style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.textLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTemplatesBar() {
    return Container(
      height: 42,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _quickReplyTemplates.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final template = _quickReplyTemplates[index];
          return ActionChip(
            label: Text(
              template,
              style: const TextStyle(fontSize: 12, color: AppTheme.textDark),
            ),
            backgroundColor: AppTheme.softGray,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: AppTheme.borderGray.withValues(alpha: 0.6),
              ),
            ),
            onPressed: () => _sendMessage(template),
          );
        },
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppTheme.borderGray.withValues(alpha: 0.6)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              showTopNotification(
                context,
                message: 'Image attachment feature coming soon!',
                icon: Icons.camera_alt_outlined,
                backgroundColor: AppTheme.accentBlue,
              );
            },
            icon: const Icon(Icons.camera_alt_outlined, color: AppTheme.textLight),
            tooltip: 'Attach photo',
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _textController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Message ${widget.conversation.participant.name}...',
                  hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textLight),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: const BoxDecoration(
              color: AppTheme.accentBlue,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: () => _sendMessage(),
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
              tooltip: 'Send',
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
