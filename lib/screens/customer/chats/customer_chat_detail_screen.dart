import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/top_notification.dart';
import '../../../models/order.dart';
import '../../../models/chat_model.dart';
import '../../../services/firebase_chat_service.dart';
import '../../../services/profile_service.dart';

enum ChatRecipientType { rider, support }

class CustomerChatDetailScreen extends StatefulWidget {
  final ChatConversation? conversation;
  final String? chatId;
  final String recipientName;
  final String recipientRole;
  final ChatRecipientType recipientType;
  final String? orderId;
  final String? phoneNumber;
  final String? riderId;

  const CustomerChatDetailScreen({
    super.key,
    this.conversation,
    this.chatId,
    this.recipientName = 'InfinityWash Support',
    this.recipientRole = 'Official Store Helpdesk',
    this.recipientType = ChatRecipientType.support,
    this.orderId,
    this.phoneNumber,
    this.riderId,
  });

  @override
  State<CustomerChatDetailScreen> createState() =>
      _CustomerChatDetailScreenState();
}

class _CustomerChatDetailScreenState extends State<CustomerChatDetailScreen> {
  final FirebaseChatService _chatService = FirebaseChatService.instance;
  final ProfileService _profileService = ProfileService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  String? _resolvedChatId;
  List<String> _participants = [];
  String _currentCustomerId = '';
  String _currentCustomerName = 'Customer';
  bool _isLoading = true;
  bool _isUploadingImage = false;

  String? get _orderDisplay {
    final id = widget.orderId ?? widget.conversation?.orderId;
    if (id == null || id.isEmpty) return null;
    return LaundryOrder.formatDisplayNumber(id: id);
  }

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    try {
      final profile = await _profileService.getProfile();
      _currentCustomerId = profile['id']?.toString() ?? '';
      final first = profile['first_name']?.toString() ?? '';
      final last = profile['last_name']?.toString() ?? '';
      final name = '$first $last'.trim();
      _currentCustomerName = name.isNotEmpty ? name : 'Customer';
      final phone = profile['phone']?.toString();
      final avatar = profile['avatar_url']?.toString();

      if (widget.conversation != null) {
        _resolvedChatId = widget.conversation!.id;
        _participants = widget.conversation!.participants;
      } else if (widget.chatId != null && widget.chatId!.isNotEmpty) {
        _resolvedChatId = widget.chatId;
        _participants = [_currentCustomerId, 'role:staff'];
      } else if (widget.recipientType == ChatRecipientType.support) {
        final conv = await _chatService.getOrCreateSupportChat(
          customerId: _currentCustomerId,
          customerName: _currentCustomerName,
          customerPhone: phone,
          customerAvatar: avatar,
          orderId: widget.orderId,
        );
        _resolvedChatId = conv.id;
        _participants = conv.participants;
      } else {
        // Rider chat
        final riderId = widget.riderId ?? 'rider_assigned';
        final orderId = widget.orderId ?? 'general';
        final conv = await _chatService.getOrCreateOrderChat(
          orderId: orderId,
          customerId: _currentCustomerId,
          customerName: _currentCustomerName,
          riderId: riderId,
          riderName: widget.recipientName,
          customerPhone: phone,
          customerAvatar: avatar,
        );
        _resolvedChatId = conv.id;
        _participants = conv.participants;
      }

      if (_resolvedChatId != null) {
        _chatService.markAsRead(
          chatId: _resolvedChatId!,
          currentUserId: _currentCustomerId,
          currentRole: 'customer',
        );
      }
    } catch (e) {
      debugPrint('Error init customer chat: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage([String? quickText]) async {
    final text = quickText ?? _textController.text.trim();
    if (text.isEmpty || _resolvedChatId == null) return;

    if (quickText == null) {
      _textController.clear();
    }

    try {
      await _chatService.sendMessage(
        chatId: _resolvedChatId!,
        senderId: _currentCustomerId,
        senderName: _currentCustomerName,
        senderRole: 'customer',
        text: text,
        participants: _participants,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        showTopNotification(
          context,
          message: 'Failed to send message: $e',
          icon: Icons.error_outline,
          backgroundColor: AppTheme.errorRed,
        );
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_resolvedChatId == null) return;
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null) return;

      setState(() => _isUploadingImage = true);

      final file = File(picked.path);
      final downloadUrl = await _chatService.uploadChatImage(
        file,
        _resolvedChatId!,
      );

      await _chatService.sendMessage(
        chatId: _resolvedChatId!,
        senderId: _currentCustomerId,
        senderName: _currentCustomerName,
        senderRole: 'customer',
        text: '',
        attachmentUrl: downloadUrl,
        attachmentType: 'image',
        participants: _participants,
      );

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        showTopNotification(
          context,
          message: 'Failed to send photo: $e',
          icon: Icons.error_outline,
          backgroundColor: AppTheme.errorRed,
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
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

  List<String> get _quickReplies {
    if (widget.recipientType == ChatRecipientType.rider) {
      return [
        'Where are you now?',
        'Please leave at the door',
        'I\'ll be there in 5 mins',
        'Thank you!',
      ];
    } else {
      return [
        'What time will my laundry be ready?',
        'Can I change my delivery address?',
        'How much is my total bill?',
        'Thank you!',
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isRider = widget.recipientType == ChatRecipientType.rider;
    final displayName = widget.conversation != null
        ? widget.conversation!.getOtherParticipantName(_currentCustomerId, 'customer')
        : widget.recipientName;
    final displayRole = widget.conversation != null
        ? widget.conversation!.getOtherParticipantRole(_currentCustomerId, 'customer')
        : widget.recipientRole;
    final displayPhone = widget.conversation != null
        ? widget.conversation!.getOtherParticipantPhone(_currentCustomerId, 'customer')
        : widget.phoneNumber;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 20, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isRider
                    ? AppTheme.lightBlue
                    : AppTheme.accentBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isRider ? Icons.delivery_dining : Icons.support_agent,
                color: AppTheme.accentBlue,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppTheme.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    displayRole,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textLight),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (displayPhone != null && displayPhone.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.phone_outlined,
                  color: AppTheme.accentBlue),
              onPressed: () {
                showTopNotification(
                  context,
                  message: 'Calling $displayName ($displayPhone)...',
                  icon: Icons.phone,
                  backgroundColor: AppTheme.accentBlue,
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_orderDisplay != null) _buildOrderContextBanner(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.accentBlue,
                      ),
                    )
                  : StreamBuilder<List<ChatMessage>>(
                      stream: _chatService.streamMessages(_resolvedChatId!),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: AppTheme.accentBlue,
                            ),
                          );
                        }

                        final messages = snapshot.data ?? [];
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_scrollController.hasClients) {
                            _scrollController.jumpTo(
                              _scrollController.position.maxScrollExtent,
                            );
                          }
                        });

                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            return _buildMessageBubble(
                                messages[index], isRider);
                          },
                        );
                      },
                    ),
            ),
            if (_isUploadingImage)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: AppTheme.softGray,
                child: const Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.accentBlue,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Uploading photo...',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textLight),
                    ),
                  ],
                ),
              ),
            _buildQuickRepliesBar(),
            _buildInputBar(displayName),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderContextBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.softGray,
        border: Border(
          bottom: BorderSide(
              color: AppTheme.borderGray.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long,
                  size: 16, color: AppTheme.accentBlue),
              const SizedBox(width: 6),
              Text(
                'Order #$_orderDisplay',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isRider) {
    final bool isFromCustomer = message.senderId == _currentCustomerId ||
        message.senderRole == 'customer';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isFromCustomer ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isFromCustomer) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: isRider
                  ? AppTheme.lightBlue
                  : AppTheme.accentBlue.withValues(alpha: 0.12),
              child: Icon(
                isRider ? Icons.delivery_dining : Icons.support_agent,
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
                color: isFromCustomer
                    ? AppTheme.accentBlue
                    : AppTheme.softGray,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isFromCustomer ? 16 : 4),
                  bottomRight: Radius.circular(isFromCustomer ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: isFromCustomer
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!isFromCustomer && message.senderName.isNotEmpty) ...[
                    Text(
                      message.senderName,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentBlue,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  if (message.attachmentUrl != null) ...[
                    GestureDetector(
                      onTap: () => _viewFullImage(message.attachmentUrl!),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          message.attachmentUrl!,
                          width: 200,
                          height: 180,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              width: 200,
                              height: 180,
                              color: Colors.black12,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.accentBlue,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    if (message.text.isNotEmpty) const SizedBox(height: 6),
                  ],
                  if (message.text.isNotEmpty)
                    Text(
                      message.text,
                      style: TextStyle(
                        fontSize: 14,
                        color: isFromCustomer ? Colors.white : AppTheme.textDark,
                        height: 1.3,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: isFromCustomer
                          ? Colors.white70
                          : AppTheme.textLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _viewFullImage(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(url, fit: BoxFit.contain),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickRepliesBar() {
    return Container(
      height: 42,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _quickReplies.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final reply = _quickReplies[index];
          return ActionChip(
            label: Text(
              reply,
              style: const TextStyle(fontSize: 12, color: AppTheme.textDark),
            ),
            backgroundColor: AppTheme.softGray,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: AppTheme.borderGray.withValues(alpha: 0.6),
              ),
            ),
            onPressed: () => _sendMessage(reply),
          );
        },
      ),
    );
  }

  Widget _buildInputBar(String displayName) {
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
            onPressed: _isUploadingImage ? null : _pickAndSendImage,
            icon: const Icon(Icons.camera_alt_outlined,
                color: AppTheme.textLight),
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
                  hintText: 'Message $displayName...',
                  hintStyle: const TextStyle(
                      fontSize: 13, color: AppTheme.textLight),
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
              icon: const Icon(Icons.send_rounded,
                  color: Colors.white, size: 18),
              tooltip: 'Send',
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour =
        time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
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
