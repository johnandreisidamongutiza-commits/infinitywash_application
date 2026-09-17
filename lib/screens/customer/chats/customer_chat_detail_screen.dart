import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/top_notification.dart';
import '../../../models/order.dart';

enum ChatRecipientType { rider, support }

class CustomerChatMessage {
  final String id;
  final String text;
  final bool isFromCustomer;
  final DateTime timestamp;
  final bool isRead;

  CustomerChatMessage({
    required this.id,
    required this.text,
    required this.isFromCustomer,
    required this.timestamp,
    this.isRead = true,
  });
}

class CustomerChatDetailScreen extends StatefulWidget {
  final String recipientName;
  final String recipientRole;
  final ChatRecipientType recipientType;
  final String? orderId;
  final String? phoneNumber;

  const CustomerChatDetailScreen({
    super.key,
    required this.recipientName,
    required this.recipientRole,
    this.recipientType = ChatRecipientType.rider,
    this.orderId,
    this.phoneNumber,
  });

  @override
  State<CustomerChatDetailScreen> createState() => _CustomerChatDetailScreenState();
}

class _CustomerChatDetailScreenState extends State<CustomerChatDetailScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late List<CustomerChatMessage> _messages;
  bool _isTyping = false;

  String? get _orderDisplay {
    final id = widget.orderId;
    if (id == null || id.isEmpty) return null;
    return LaundryOrder.formatDisplayNumber(id: id);
  }

  @override
  void initState() {
    super.initState();
    _initMessages();
  }

  void _initMessages() {
    if (widget.recipientType == ChatRecipientType.rider) {
      _messages = [
        CustomerChatMessage(
          id: '1',
          text: 'Hi, what time will you arrive?',
          isFromCustomer: true,
          timestamp: DateTime.now().subtract(const Duration(hours: 1)),
        ),
        CustomerChatMessage(
          id: '2',
          text: 'I\'m on my way now. Should be there in about 15 minutes.',
          isFromCustomer: false,
          timestamp: DateTime.now().subtract(const Duration(minutes: 45)),
        ),
        CustomerChatMessage(
          id: '3',
          text: 'Thanks! See you soon',
          isFromCustomer: true,
          timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
        ),
      ];
    } else {
      _messages = [
        CustomerChatMessage(
          id: '1',
          text: 'Hello! Welcome to InfinityWash Support. 🫧 How can we assist you with your laundry today?',
          isFromCustomer: false,
          timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      ];
    }
  }

  void _sendMessage([String? quickText]) {
    final text = quickText ?? _textController.text.trim();
    if (text.isEmpty) return;

    if (quickText == null) {
      _textController.clear();
    }

    setState(() {
      _messages.add(
        CustomerChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: text,
          isFromCustomer: true,
          timestamp: DateTime.now(),
        ),
      );
    });

    _scrollToBottom();
    _simulateReply(text);
  }

  void _simulateReply(String userMessage) {
    setState(() => _isTyping = true);

    Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;

      String replyText;
      if (widget.recipientType == ChatRecipientType.rider) {
        if (userMessage.toLowerCase().contains('where') || userMessage.toLowerCase().contains('eta')) {
          replyText = 'Currently passing by Clean Ave! Approaching your street in about 5 minutes.';
        } else if (userMessage.toLowerCase().contains('gate') || userMessage.toLowerCase().contains('leave')) {
          replyText = 'Noted! I will leave it safely by the blue gate as requested.';
        } else if (userMessage.toLowerCase().contains('call')) {
          replyText = 'Will ring your phone as soon as I pull up!';
        } else {
          replyText = 'Got it! Thanks for letting me know.';
        }
      } else {
        if (userMessage.toLowerCase().contains('status') || userMessage.toLowerCase().contains('order')) {
          replyText = 'Your Order #IW-105 is currently being washed and dried. Estimated completion is 4:00 PM today!';
        } else if (userMessage.toLowerCase().contains('address') || userMessage.toLowerCase().contains('change')) {
          replyText = 'Address change request noted. I will update rider Michael with the landmark details.';
        } else {
          replyText = 'Thank you for reaching out! Our shop staff is attending to your request.';
        }
      }

      setState(() {
        _isTyping = false;
        _messages.add(
          CustomerChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: replyText,
            isFromCustomer: false,
            timestamp: DateTime.now(),
          ),
        );
      });

      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<String> get _quickChips {
    if (widget.recipientType == ChatRecipientType.rider) {
      return [
        'Where are you now?',
        'Please leave at the gate',
        'I\'m coming down now',
        'Please call when nearby',
      ];
    }
    return [
      'Check order status',
      'Change delivery landmark',
      'Speak with staff agent',
      'Store operating hours',
    ];
  }

  @override
  Widget build(BuildContext context) {
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
                    color: widget.recipientType == ChatRecipientType.rider
                        ? AppTheme.lightBlue
                        : AppTheme.accentBlue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.recipientType == ChatRecipientType.rider
                        ? Icons.delivery_dining
                        : Icons.support_agent,
                    color: AppTheme.accentBlue,
                    size: 22,
                  ),
                ),
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
                    widget.recipientName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.recipientRole,
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
              final phone = widget.phoneNumber ?? '0912-345-6789';
              showTopNotification(
                context,
                message: 'Calling ${widget.recipientName} ($phone)...',
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
              if (val == 'order' && widget.orderId != null) {
                Navigator.pop(context);
              } else if (val == 'report') {
                showTopNotification(
                  context,
                  message: 'Issue report sent to store manager.',
                  icon: Icons.flag,
                  backgroundColor: AppTheme.accentBlue,
                );
              }
            },
            itemBuilder: (ctx) => [
              if (widget.orderId != null)
                PopupMenuItem(
                  value: 'order',
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long, size: 18, color: AppTheme.accentBlue),
                      const SizedBox(width: 10),
                      Text('Order #${_orderDisplay!} Info'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.flag_outlined, size: 18, color: AppTheme.errorRed),
                    SizedBox(width: 10),
                    Text('Report an Issue'),
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
            if (widget.orderId != null) _buildOrderContextBanner(),

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

            // Quick Reply Chips
            _buildQuickChipsBar(),

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
            child: const Icon(Icons.local_laundry_service, color: AppTheme.accentBlue, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active Order #$_orderDisplay',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark),
                ),
                const Text(
                  'Wash, Dry & Fold • Est. Arrival 4:00 PM',
                  style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('In Progress', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(CustomerChatMessage message) {
    final isCustomer = message.isFromCustomer;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isCustomer ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isCustomer) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: widget.recipientType == ChatRecipientType.rider
                  ? AppTheme.lightBlue
                  : AppTheme.accentBlue.withValues(alpha: 0.1),
              child: Icon(
                widget.recipientType == ChatRecipientType.rider ? Icons.delivery_dining : Icons.support_agent,
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
                color: isCustomer ? AppTheme.accentBlue : AppTheme.softGray,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isCustomer ? 16 : 4),
                  bottomRight: Radius.circular(isCustomer ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: isCustomer ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: TextStyle(
                      fontSize: 14,
                      color: isCustomer ? Colors.white : AppTheme.textDark,
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
                          color: isCustomer ? Colors.white70 : AppTheme.textLight,
                        ),
                      ),
                      if (isCustomer) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.done_all, size: 12, color: Colors.white70),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppTheme.lightBlue,
            child: const Icon(Icons.more_horiz, size: 16, color: AppTheme.accentBlue),
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
                  '${widget.recipientName} is typing...',
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.textLight),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChipsBar() {
    return Container(
      height: 42,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _quickChips.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final chipText = _quickChips[index];
          return ActionChip(
            label: Text(chipText, style: const TextStyle(fontSize: 12, color: AppTheme.textDark)),
            backgroundColor: AppTheme.softGray,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: AppTheme.borderGray.withValues(alpha: 0.6)),
            ),
            onPressed: () => _sendMessage(chipText),
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
        border: Border(top: BorderSide(color: AppTheme.borderGray.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              showTopNotification(
                context,
                message: 'Attachment simulation: image preview attached.',
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
                  hintText: 'Message ${widget.recipientName}...',
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
