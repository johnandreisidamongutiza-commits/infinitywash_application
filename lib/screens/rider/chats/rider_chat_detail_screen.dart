import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import '../../../models/chat_model.dart';
import '../../../services/firebase_chat_service.dart';
import '../../../services/profile_service.dart';
import '../../../widgets/top_notification.dart';

class RiderChatDetailScreen extends StatefulWidget {
  final ChatConversation? conversation;
  final String? chatId;
  final String customerName;
  final String customerId;
  final String? orderId;
  final String? phoneNumber;
  final bool isDispatchChat;

  const RiderChatDetailScreen({
    super.key,
    this.conversation,
    this.chatId,
    required this.customerName,
    required this.customerId,
    this.orderId,
    this.phoneNumber,
    this.isDispatchChat = false,
  });

  @override
  State<RiderChatDetailScreen> createState() => _RiderChatDetailScreenState();
}

class _RiderChatDetailScreenState extends State<RiderChatDetailScreen> {
  final FirebaseChatService _chatService = FirebaseChatService.instance;
  final ProfileService _profileService = ProfileService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  String? _resolvedChatId;
  List<String> _participants = [];
  String _currentRiderId = '';
  String _currentRiderName = 'Rider';
  bool _isLoading = true;
  bool _isUploadingImage = false;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    try {
      final profile = await _profileService.getProfile();
      _currentRiderId = profile['id']?.toString() ?? '';
      final first = profile['first_name']?.toString() ?? '';
      final last = profile['last_name']?.toString() ?? '';
      final fullName = '$first $last'.trim();
      _currentRiderName = fullName.isNotEmpty ? fullName : 'Delivery Rider';
      final phone = profile['phone']?.toString();
      final avatar = profile['avatar_url']?.toString();

      if (widget.conversation != null) {
        _resolvedChatId = widget.conversation!.id;
        _participants = widget.conversation!.participants;
      } else if (widget.chatId != null && widget.chatId!.isNotEmpty) {
        _resolvedChatId = widget.chatId;
        _participants = [_currentRiderId, 'role:staff'];
      } else if (widget.isDispatchChat) {
        final conv = await _chatService.getOrCreateRiderStaffChat(
          riderId: _currentRiderId,
          riderName: _currentRiderName,
          riderPhone: phone,
          riderAvatar: avatar,
        );
        _resolvedChatId = conv.id;
        _participants = conv.participants;
      } else {
        // Customer chat
        final orderId = widget.orderId ?? 'general';
        final conv = await _chatService.getOrCreateOrderChat(
          orderId: orderId,
          customerId: widget.customerId,
          customerName: widget.customerName,
          riderId: _currentRiderId,
          riderName: _currentRiderName,
          customerPhone: widget.phoneNumber,
          riderPhone: phone,
          riderAvatar: avatar,
        );
        _resolvedChatId = conv.id;
        _participants = conv.participants;
      }

      if (_resolvedChatId != null) {
        _chatService.markAsRead(
          chatId: _resolvedChatId!,
          currentUserId: _currentRiderId,
          currentRole: 'rider',
        );
      }
    } catch (e) {
      debugPrint('Error initializing rider chat: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage([String? quickText]) async {
    final text = quickText ?? _messageController.text.trim();
    if (text.isEmpty || _resolvedChatId == null) return;

    if (quickText == null) {
      _messageController.clear();
    }

    try {
      await _chatService.sendMessage(
        chatId: _resolvedChatId!,
        senderId: _currentRiderId,
        senderName: _currentRiderName,
        senderRole: 'rider',
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
        senderId: _currentRiderId,
        senderName: _currentRiderName,
        senderRole: 'rider',
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
          message: 'Failed to upload photo: $e',
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
    if (widget.isDispatchChat) {
      return [
        'Picked up order from shop',
        'Customer not answering door',
        'Stuck in heavy traffic',
        'Delivered successfully!',
      ];
    }
    return [
      'I am on my way now.',
      'Arriving in about 10 minutes.',
      'I have arrived at your door/lobby.',
      'Thank you! Have a great day.',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.conversation != null
        ? widget.conversation!.getOtherParticipantName(_currentRiderId, 'rider')
        : widget.customerName;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            if (widget.orderId != null && widget.orderId!.isNotEmpty)
              Text(
                'Order #${LaundryOrder.formatDisplayNumber(id: widget.orderId!)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textLight,
                ),
              ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 20, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (widget.phoneNumber != null && widget.phoneNumber!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.phone_outlined,
                  color: AppTheme.accentBlue),
              onPressed: () {
                showTopNotification(
                  context,
                  message: 'Calling $title (${widget.phoneNumber})...',
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
                            return _buildMessageBubble(messages[index]);
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
            _buildInputBar(title),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final bool isRider = message.senderRole == 'rider' ||
        message.senderId == _currentRiderId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isRider ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isRider) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: AppTheme.accentBlue.withValues(alpha: 0.1),
              child: const Icon(
                Icons.person,
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
                color: isRider ? AppTheme.accentBlue : AppTheme.softGray,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isRider ? 16 : 4),
                  bottomRight: Radius.circular(isRider ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment:
                    isRider ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isRider && message.senderName.isNotEmpty) ...[
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
                        color: isRider ? Colors.white : AppTheme.textDark,
                        height: 1.3,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: isRider ? Colors.white70 : AppTheme.textLight,
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

  Widget _buildInputBar(String title) {
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
                controller: _messageController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Message $title...',
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
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
