import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../theme/app_theme.dart';
import '../../../models/chat_model.dart';
import '../../../services/firebase_chat_service.dart';
import '../../../services/profile_service.dart';
import '../../../services/supabase_service.dart';
import '../../../services/order_number_resolver.dart';
import '../../../widgets/top_notification.dart';
import '../../../utils/chat_rate_limiter.dart';

class RiderChatDetailScreen extends StatefulWidget {
  final ChatConversation? conversation;
  final String? chatId;
  final String customerName;
  final String customerId;
  final String? orderId;
  final String? phoneNumber;
  final String? jobType; // 'pickup' | 'delivery'
  final String? address;
  final String? landmark;
  final bool isDispatchChat;

  const RiderChatDetailScreen({
    super.key,
    this.conversation,
    this.chatId,
    required this.customerName,
    required this.customerId,
    this.orderId,
    this.phoneNumber,
    this.jobType,
    this.address,
    this.landmark,
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

  // Hybrid pagination state (Free tier optimization)
  final List<ChatMessage> _olderMessages = [];
  List<ChatMessage> _latestStreamMessages = [];
  bool _isLoadingOlder = false;
  bool _hasMoreOlder = true;
  bool _initialScrollDone = false;

  // Rate limiting for rider quick replies (Rider: 4s cooldown, 20s duplicate window)
  final ChatRateLimiter _rateLimiter = ChatRateLimiter(
    cooldownDuration: const Duration(seconds: 4),
    sameMessageCooldownDuration: const Duration(seconds: 20),
  );
  bool _isSendingPremade = false;

  /// Resolved human-readable order number for the app bar subtitle.
  String get _resolvedOrderDisplay {
    if (widget.conversation != null) {
      return widget.conversation!.displayOrderNumber ?? '';
    }
    if (widget.orderId != null && widget.orderId!.isNotEmpty) {
      return OrderNumberResolver.resolveSync(orderId: widget.orderId!);
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _rateLimiter.setTickListener(() {
      if (mounted) setState(() {});
    });
    _initChat();
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
    if (_isLoadingOlder || !_hasMoreOlder || _resolvedChatId == null) return;

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
        chatId: _resolvedChatId!,
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
      debugPrint('Error loading older rider chat messages: $e');
    } finally {
      if (mounted) setState(() => _isLoadingOlder = false);
    }
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
        String custId = widget.customerId;
        String? custPhone = widget.phoneNumber;

        if (custId.isEmpty && orderId != 'general') {
          try {
            final orderRes = await SupabaseService.client
                .from('orders')
                .select('customer_id, customers(phone)')
                .eq('id', orderId)
                .maybeSingle();
            if (orderRes != null) {
              custId = orderRes['customer_id']?.toString() ?? '';
              final cust = orderRes['customers'] as Map<String, dynamic>?;
              custPhone ??= cust?['phone']?.toString();
            }
          } catch (_) {}
        }

        final conv = await _chatService.getOrCreateOrderChat(
          orderId: orderId,
          customerId: custId,
          customerName: widget.customerName,
          riderId: _currentRiderId,
          riderName: _currentRiderName,
          customerPhone: custPhone,
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

  bool get _isDispatch =>
      widget.isDispatchChat ||
      (widget.conversation?.chatType == ChatType.riderStaff);

  List<String> get _quickReplies {
    if (_isDispatch) {
      return [
        'Picked up order from shop',
        'Customer not answering door',
        'Stuck in heavy traffic',
        'Delivered successfully!',
      ];
    }
    return [
      'I am on my way with your laundry.',
      'Arriving in about 10 minutes.',
      'I have arrived at your door/lobby.',
      'Thank you! Have a great day.',
    ];
  }

  Widget _buildOrderContextBanner(bool isPickup, Color taskColor) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.softGray.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: taskColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPickup
                  ? Icons.shopping_bag_outlined
                  : Icons.local_shipping_outlined,
              size: 16,
              color: taskColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isPickup ? 'PICKUP TASK' : 'DELIVERY TASK',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: taskColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '#$_resolvedOrderDisplay',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (widget.address != null && widget.address!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.address!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textLight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (widget.orderId != null && widget.orderId!.isNotEmpty) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderGray),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map_outlined,
                        size: 12, color: AppTheme.accentBlue),
                    SizedBox(width: 4),
                    Text(
                      'Job',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.conversation != null
        ? widget.conversation!.getOtherParticipantName(_currentRiderId, 'rider')
        : widget.customerName;

    final bool isPickup = widget.jobType == 'pickup';
    final Color taskColor =
        isPickup ? AppTheme.errorRed : AppTheme.teamMemberIconOrange;

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _isDispatch ? 'InfinityWash Staff' : title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_isDispatch) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.verified,
                      size: 15, color: AppTheme.primaryBlue),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: _isDispatch
                        ? AppTheme.primaryBlue.withValues(alpha: 0.12)
                        : Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _isDispatch ? 'STORE STAFF • Helpdesk' : 'CUSTOMER',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.4,
                      color: _isDispatch
                          ? AppTheme.primaryBlue
                          : Colors.teal.shade800,
                    ),
                  ),
                ),
                if (!_isDispatch && _resolvedOrderDisplay.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Order #$_resolvedOrderDisplay',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textLight,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.phone_outlined,
              color: _isDispatch ? AppTheme.primaryBlue : AppTheme.accentBlue,
            ),
            tooltip: _isDispatch ? 'Call Shop Staff' : 'Call Customer',
            onPressed: () {
              final phoneToCall = _isDispatch
                  ? (widget.phoneNumber ?? '0912-345-6789')
                  : (widget.phoneNumber ?? 'Customer Phone');
              showTopNotification(
                context,
                message: _isDispatch
                    ? 'Calling Shop Staff ($phoneToCall)...'
                    : 'Calling $title ($phoneToCall)...',
                icon: Icons.phone,
                backgroundColor:
                    _isDispatch ? AppTheme.primaryBlue : AppTheme.accentBlue,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Order Context Banner (Only for customer chats when order context exists)
            if (!_isDispatch && _resolvedOrderDisplay.isNotEmpty)
              _buildOrderContextBanner(isPickup, taskColor),
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
                                _scrollController.position.maxScrollExtent -
                                    120) {
                              _scrollToBottom();
                            }
                          }
                        });

                        final bool showHeader =
                            _hasMoreOlder || _isLoadingOlder;
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
                                          size: 14,
                                          color: AppTheme.accentBlue),
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

  Future<void> _handlePremadeReply(String reply) async {
    if (_isSendingPremade) return;

    if (!_rateLimiter.canSend(reply, onBlocked: (reason) {
      showTopNotification(
        context,
        message: reason,
        icon: Icons.timer_outlined,
        backgroundColor: AppTheme.accentBlue,
      );
    })) {
      return;
    }

    setState(() => _isSendingPremade = true);
    _rateLimiter.recordSent(reply);

    try {
      await _sendMessage(reply);
    } finally {
      if (mounted) setState(() => _isSendingPremade = false);
    }
  }

  Widget _buildQuickRepliesBar() {
    final bool isCooling = _rateLimiter.isInCooldown || _isSendingPremade;
    final int remaining = _rateLimiter.remainingSeconds;

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
                  : reply,
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
            onPressed: () => _handlePremadeReply(reply),
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
    _rateLimiter.dispose();
    _scrollController.removeListener(_onScroll);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
