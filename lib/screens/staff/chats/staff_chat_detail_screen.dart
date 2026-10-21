import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../theme/app_theme.dart';
import '../../../models/chat_model.dart';
import '../../../services/firebase_chat_service.dart';
import '../../../services/profile_service.dart';
import '../../../widgets/top_notification.dart';
import '../../../utils/chat_rate_limiter.dart';

class StaffChatDetailScreen extends StatefulWidget {
  final ChatConversation conversation;

  const StaffChatDetailScreen({
    super.key,
    required this.conversation,
  });

  @override
  State<StaffChatDetailScreen> createState() => _StaffChatDetailScreenState();
}

class _StaffChatDetailScreenState extends State<StaffChatDetailScreen> {
  final FirebaseChatService _chatService = FirebaseChatService.instance;
  final ProfileService _profileService = ProfileService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  String _currentStaffId = '';
  String _currentStaffName = 'Staff Member';
  bool _isUploadingImage = false;

  // Hybrid pagination state (Free tier optimization)
  final List<ChatMessage> _olderMessages = [];
  List<ChatMessage> _latestStreamMessages = [];
  bool _isLoadingOlder = false;
  bool _hasMoreOlder = true;
  bool _initialScrollDone = false;

  // Rate limiting for staff quick templates (Staff: 2s cooldown, 10s duplicate window)
  final ChatRateLimiter _rateLimiter = ChatRateLimiter(
    cooldownDuration: const Duration(seconds: 2),
    sameMessageCooldownDuration: const Duration(seconds: 10),
  );
  bool _isSendingTemplate = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _rateLimiter.setTickListener(() {
      if (mounted) setState(() {});
    });
    _loadCurrentProfile();
    _markAsRead();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels <= 60 &&
        !_isLoadingOlder &&
        _hasMoreOlder) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoadingOlder || !_hasMoreOlder) return;

    ChatMessage? oldest;
    if (_olderMessages.isNotEmpty) {
      oldest = _olderMessages.first;
    } else if (_latestStreamMessages.isNotEmpty) {
      oldest = _latestStreamMessages.first;
    }

    if (oldest == null) return;

    setState(() => _isLoadingOlder = true);

    try {
      final earlier = await _chatService.loadEarlierMessages(
        chatId: widget.conversation.id,
        beforeTimestamp: oldest.timestamp,
        limit: 20,
      );

      if (mounted) {
        setState(() {
          if (earlier.isEmpty) {
            _hasMoreOlder = false;
          } else {
            final existingIds = {
              ..._olderMessages.map((m) => m.id),
              ..._latestStreamMessages.map((m) => m.id),
            };
            final newUnique =
                earlier.where((m) => !existingIds.contains(m.id)).toList();
            if (newUnique.isEmpty || earlier.length < 20) {
              _hasMoreOlder = false;
            }
            _olderMessages.insertAll(0, newUnique);
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading older staff chat messages: $e');
    } finally {
      if (mounted) setState(() => _isLoadingOlder = false);
    }
  }

  Future<void> _loadCurrentProfile() async {
    try {
      final profile = await _profileService.getProfile();
      if (mounted) {
        setState(() {
          _currentStaffId = profile['id']?.toString() ?? '';
          final first = profile['first_name']?.toString() ?? '';
          final last = profile['last_name']?.toString() ?? '';
          final fullName = '$first $last'.trim();
          _currentStaffName = fullName.isNotEmpty ? fullName : 'Staff Member';
        });
      }
    } catch (_) {}
  }

  void _markAsRead() {
    _chatService.markAsRead(
      chatId: widget.conversation.id,
      currentUserId: _currentStaffId,
      currentRole: 'staff',
    );
  }

  Future<void> _sendMessage([String? quickText]) async {
    final text = quickText ?? _textController.text.trim();
    if (text.isEmpty) return;

    if (quickText == null) {
      _textController.clear();
    }

    try {
      await _chatService.sendMessage(
        chatId: widget.conversation.id,
        senderId: _currentStaffId.isNotEmpty ? _currentStaffId : 'staff',
        senderName: _currentStaffName,
        senderRole: 'staff',
        text: text,
        participants: widget.conversation.participants,
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
        widget.conversation.id,
      );

      await _chatService.sendMessage(
        chatId: widget.conversation.id,
        senderId: _currentStaffId.isNotEmpty ? _currentStaffId : 'staff',
        senderName: _currentStaffName,
        senderRole: 'staff',
        text: '',
        attachmentUrl: downloadUrl,
        attachmentType: 'image',
        participants: widget.conversation.participants,
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

  List<String> get _quickReplyTemplates {
    final isCustomer =
        widget.conversation.chatType == ChatType.customerSupport;

    if (isCustomer) {
      return [
        'Your order is ready for pickup',
        'Order will be completed soon',
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
    final otherName = widget.conversation.getOtherParticipantName('', 'staff');
    final otherRole = widget.conversation.getOtherParticipantRole('', 'staff');
    final otherPhone = widget.conversation.getOtherParticipantPhone('', 'staff');
    final isCustomer =
        widget.conversation.chatType == ChatType.customerSupport;

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
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    otherName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppTheme.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    otherRole,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textLight),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (otherPhone != null && otherPhone.isNotEmpty)
            IconButton(
              onPressed: () {
                showTopNotification(
                  context,
                  message: 'Calling $otherName ($otherPhone)...',
                  icon: Icons.phone,
                  backgroundColor: AppTheme.accentBlue,
                );
              },
              icon: const Icon(Icons.phone_outlined,
                  color: AppTheme.accentBlue),
              tooltip: 'Call',
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.conversation.orderId != null &&
                widget.conversation.orderId!.isNotEmpty)
              _buildOrderContextBanner(),
            Expanded(
              child: StreamBuilder<List<ChatMessage>>(
                stream: _chatService.streamMessages(widget.conversation.id),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData &&
                      _olderMessages.isEmpty) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.accentBlue,
                      ),
                    );
                  }

                  final streamMessages = snapshot.data ?? [];
                  _latestStreamMessages = streamMessages;

                  // Merge and deduplicate historical older messages with live stream
                  final Map<String, ChatMessage> messageMap = {};
                  for (final m in _olderMessages) {
                    messageMap[m.id] = m;
                  }
                  for (final m in streamMessages) {
                    messageMap[m.id] = m;
                  }
                  final allMessages = messageMap.values.toList()
                    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

                  if (!_initialScrollDone &&
                      streamMessages.length < 20 &&
                      _olderMessages.isEmpty) {
                    _hasMoreOlder = false;
                  }

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollController.hasClients) {
                      if (!_initialScrollDone) {
                        _scrollController.jumpTo(
                          _scrollController.position.maxScrollExtent,
                        );
                        _initialScrollDone = true;
                      } else if (_scrollController.position.pixels >=
                          _scrollController.position.maxScrollExtent - 120) {
                        _scrollToBottom();
                      }
                    }
                  });

                  final bool showHeader = _hasMoreOlder || _isLoadingOlder;
                  final int itemCount =
                      allMessages.length + (showHeader ? 1 : 0);

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: itemCount,
                    itemBuilder: (context, index) {
                      if (showHeader && index == 0) {
                        if (_isLoadingOlder) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.accentBlue,
                                ),
                              ),
                            ),
                          );
                        } else {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: TextButton.icon(
                                onPressed: _loadOlderMessages,
                                icon: const Icon(Icons.history,
                                    size: 14, color: AppTheme.accentBlue),
                                label: const Text(
                                  'Load earlier messages',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.accentBlue,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                      }

                      final msgIndex = showHeader ? index - 1 : index;
                      return _buildMessageBubble(allMessages[msgIndex]);
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
            _buildQuickTemplatesBar(),
            _buildInputBar(otherName),
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
                'Linked Order #${widget.conversation.orderId}',
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

  Widget _buildMessageBubble(ChatMessage message) {
    final isStaff = message.senderRole == 'staff';
    final isMe = message.senderId == _currentStaffId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isStaff ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isStaff) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: widget.conversation.chatType ==
                      ChatType.customerSupport
                  ? AppTheme.accentBlue.withValues(alpha: 0.1)
                  : AppTheme.lightBlue,
              child: Icon(
                widget.conversation.chatType == ChatType.customerSupport
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
                crossAxisAlignment:
                    isStaff ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (isStaff && !isMe) ...[
                    Text(
                      message.senderName,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
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
                        color: isStaff ? Colors.white : AppTheme.textDark,
                        height: 1.3,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: isStaff ? Colors.white70 : AppTheme.textLight,
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

  Future<void> _handlePremadeTemplate(String template) async {
    if (_isSendingTemplate) return;

    if (!_rateLimiter.canSend(template, onBlocked: (reason) {
      showTopNotification(
        context,
        message: reason,
        icon: Icons.timer_outlined,
        backgroundColor: AppTheme.accentBlue,
      );
    })) {
      return;
    }

    setState(() => _isSendingTemplate = true);
    _rateLimiter.recordSent(template);

    try {
      await _sendMessage(template);
    } finally {
      if (mounted) setState(() => _isSendingTemplate = false);
    }
  }

  Widget _buildQuickTemplatesBar() {
    final bool isCooling = _rateLimiter.isInCooldown || _isSendingTemplate;
    final int remaining = _rateLimiter.remainingSeconds;

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
            avatar: isCooling && remaining > 0 && index == 0
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.textLight,
                    ),
                  )
                : null,
            label: Text(
              isCooling && remaining > 0 && index == 0
                  ? 'Wait ${remaining}s'
                  : template,
              style: TextStyle(
                fontSize: 12,
                color: isCooling
                    ? AppTheme.textLight.withValues(alpha: 0.8)
                    : AppTheme.textDark,
              ),
            ),
            backgroundColor: isCooling
                ? AppTheme.softGray.withValues(alpha: 0.5)
                : AppTheme.softGray,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color:
                    AppTheme.borderGray.withValues(alpha: isCooling ? 0.3 : 0.6),
              ),
            ),
            onPressed: () => _handlePremadeTemplate(template),
          );
        },
      ),
    );
  }

  Widget _buildInputBar(String otherName) {
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
                  hintText: 'Message $otherName...',
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
    _rateLimiter.dispose();
    _scrollController.removeListener(_onScroll);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
