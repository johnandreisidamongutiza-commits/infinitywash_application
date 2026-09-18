import '../models/staff_chat.dart';

class ChatService {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;

  // Mock participants
  final List<ChatParticipant> _participants = [
    ChatParticipant(
      id: 'customer_1',
      name: 'Maria Santos',
      type: ChatParticipantType.customer,
      phone: '+63 917 123 4567',
      isOnline: true,
    ),
    ChatParticipant(
      id: 'customer_2',
      name: 'Juan dela Cruz',
      type: ChatParticipantType.customer,
      phone: '+63 918 234 5678',
      isOnline: false,
    ),
    ChatParticipant(
      id: 'customer_3',
      name: 'Ana Reyes',
      type: ChatParticipantType.customer,
      phone: '+63 919 345 6789',
      isOnline: true,
    ),
    ChatParticipant(
      id: 'rider_1',
      name: 'Michael Rider',
      type: ChatParticipantType.rider,
      phone: '+63 912 345 6789',
      isOnline: true,
    ),
    ChatParticipant(
      id: 'rider_2',
      name: 'Carlos Driver',
      type: ChatParticipantType.rider,
      phone: '+63 913 456 7890',
      isOnline: true,
    ),
  ];

  // Mock conversations
  List<StaffConversation> _conversations = [];

  // Mock messages storage
  final Map<String, List<StaffChatMessage>> _messagesByConversation = {};

  ChatService._internal() {
    _initializeMockData();
  }

  void _initializeMockData() {
    final now = DateTime.now();

    _conversations = [
      StaffConversation(
        id: 'conv_1',
        participant: _participants[0], // Maria Santos
        orderId: 'IW-105',
        lastMessage: 'What time will my laundry be ready?',
        lastMessageTime: now.subtract(const Duration(minutes: 2)),
        unreadCount: 1,
        orderStatus: 'Processing',
      ),
      StaffConversation(
        id: 'conv_2',
        participant: _participants[3], // Michael Rider
        orderId: 'IW-104',
        lastMessage: 'On my way to pick up the order now',
        lastMessageTime: now.subtract(const Duration(minutes: 15)),
        unreadCount: 0,
        orderStatus: 'Processing',
      ),
      StaffConversation(
        id: 'conv_3',
        participant: _participants[1], // Juan dela Cruz
        orderId: 'IW-103',
        lastMessage: 'Thanks for the update!',
        lastMessageTime: now.subtract(const Duration(hours: 1)),
        unreadCount: 0,
        orderStatus: 'Completed',
      ),
      StaffConversation(
        id: 'conv_4',
        participant: _participants[2], // Ana Reyes
        orderId: 'IW-106',
        lastMessage: 'Can I change my delivery address?',
        lastMessageTime: now.subtract(const Duration(minutes: 30)),
        unreadCount: 2,
        orderStatus: 'Pending',
      ),
      StaffConversation(
        id: 'conv_5',
        participant: _participants[4], // Carlos Driver
        orderId: 'IW-102',
        lastMessage: 'Customer not answering the door',
        lastMessageTime: now.subtract(const Duration(hours: 2)),
        unreadCount: 1,
        orderStatus: 'Out for Delivery',
      ),
    ];

    // Initialize messages for each conversation
    _initializeMessages();
  }

  void _initializeMessages() {
    final now = DateTime.now();

    // Messages for Maria Santos (conv_1)
    _messagesByConversation['conv_1'] = [
      StaffChatMessage(
        id: 'msg_1_1',
        text: 'Hello! I placed an order this morning.',
        senderId: 'customer_1',
        recipientId: 'staff',
        timestamp: now.subtract(const Duration(hours: 2)),
        isFromStaff: false,
      ),
      StaffChatMessage(
        id: 'msg_1_2',
        text: 'Hi Maria! Yes, we received your order #IW-105. It\'s currently being processed.',
        senderId: 'staff',
        recipientId: 'customer_1',
        timestamp: now.subtract(const Duration(hours: 1, minutes: 55)),
        isFromStaff: true,
      ),
      StaffChatMessage(
        id: 'msg_1_3',
        text: 'What time will my laundry be ready?',
        senderId: 'customer_1',
        recipientId: 'staff',
        timestamp: now.subtract(const Duration(minutes: 2)),
        isRead: false,
        isFromStaff: false,
      ),
    ];

    // Messages for Michael Rider (conv_2)
    _messagesByConversation['conv_2'] = [
      StaffChatMessage(
        id: 'msg_2_1',
        text: 'Hi Michael, order #IW-104 is ready for pickup.',
        senderId: 'staff',
        recipientId: 'rider_1',
        timestamp: now.subtract(const Duration(minutes: 30)),
        isFromStaff: true,
      ),
      StaffChatMessage(
        id: 'msg_2_2',
        text: 'Got it! On my way to pick up the order now',
        senderId: 'rider_1',
        recipientId: 'staff',
        timestamp: now.subtract(const Duration(minutes: 15)),
        isFromStaff: false,
      ),
    ];

    // Messages for Juan dela Cruz (conv_3)
    _messagesByConversation['conv_3'] = [
      StaffChatMessage(
        id: 'msg_3_1',
        text: 'Hi Juan, your order #IW-103 has been completed and is ready for delivery!',
        senderId: 'staff',
        recipientId: 'customer_2',
        timestamp: now.subtract(const Duration(hours: 1, minutes: 30)),
        isFromStaff: true,
      ),
      StaffChatMessage(
        id: 'msg_3_2',
        text: 'Great! What\'s the estimated delivery time?',
        senderId: 'customer_2',
        recipientId: 'staff',
        timestamp: now.subtract(const Duration(hours: 1, minutes: 15)),
        isFromStaff: false,
      ),
      StaffChatMessage(
        id: 'msg_3_3',
        text: 'Our rider will deliver it around 4:00 PM today.',
        senderId: 'staff',
        recipientId: 'customer_2',
        timestamp: now.subtract(const Duration(hours: 1, minutes: 10)),
        isFromStaff: true,
      ),
      StaffChatMessage(
        id: 'msg_3_4',
        text: 'Thanks for the update!',
        senderId: 'customer_2',
        recipientId: 'staff',
        timestamp: now.subtract(const Duration(hours: 1)),
        isFromStaff: false,
      ),
    ];

    // Messages for Ana Reyes (conv_4)
    _messagesByConversation['conv_4'] = [
      StaffChatMessage(
        id: 'msg_4_1',
        text: 'Hello, I need to update my order details.',
        senderId: 'customer_3',
        recipientId: 'staff',
        timestamp: now.subtract(const Duration(minutes: 35)),
        isFromStaff: false,
      ),
      StaffChatMessage(
        id: 'msg_4_2',
        text: 'Can I change my delivery address?',
        senderId: 'customer_3',
        recipientId: 'staff',
        timestamp: now.subtract(const Duration(minutes: 30)),
        isRead: false,
        isFromStaff: false,
      ),
    ];

    // Messages for Carlos Driver (conv_5)
    _messagesByConversation['conv_5'] = [
      StaffChatMessage(
        id: 'msg_5_1',
        text: 'Please proceed to deliver order #IW-102 to the customer.',
        senderId: 'staff',
        recipientId: 'rider_2',
        timestamp: now.subtract(const Duration(hours: 3)),
        isFromStaff: true,
      ),
      StaffChatMessage(
        id: 'msg_5_2',
        text: 'Arrived at the location. Customer not answering the door',
        senderId: 'rider_2',
        recipientId: 'staff',
        timestamp: now.subtract(const Duration(hours: 2)),
        isRead: false,
        isFromStaff: false,
      ),
    ];
  }

  // Get all conversations
  List<StaffConversation> getConversations() {
    return List.from(_conversations);
  }

  // Get conversations by type
  List<StaffConversation> getConversationsByType(ChatParticipantType type) {
    return _conversations
        .where((conv) => conv.participant.type == type)
        .toList();
  }

  // Get total unread count
  int getTotalUnreadCount() {
    return _conversations.fold(0, (sum, conv) => sum + conv.unreadCount);
  }

  // Get messages for a conversation
  List<StaffChatMessage> getMessages(String conversationId) {
    return List.from(_messagesByConversation[conversationId] ?? []);
  }

  // Send a message
  void sendMessage({
    required String conversationId,
    required String text,
    bool isFromStaff = true,
  }) {
    final conversation = _conversations.firstWhere((c) => c.id == conversationId);
    
    final newMessage = StaffChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      text: text,
      senderId: isFromStaff ? 'staff' : conversation.participant.id,
      recipientId: isFromStaff ? conversation.participant.id : 'staff',
      timestamp: DateTime.now(),
      isFromStaff: isFromStaff,
    );

    _messagesByConversation[conversationId]?.add(newMessage);

    // Update conversation's last message
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      _conversations[index] = StaffConversation(
        id: conversation.id,
        participant: conversation.participant,
        orderId: conversation.orderId,
        lastMessage: text,
        lastMessageTime: DateTime.now(),
        unreadCount: conversation.unreadCount,
        orderStatus: conversation.orderStatus,
      );
    }
  }

  // Mark conversation as read
  void markAsRead(String conversationId) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      final conversation = _conversations[index];
      _conversations[index] = StaffConversation(
        id: conversation.id,
        participant: conversation.participant,
        orderId: conversation.orderId,
        lastMessage: conversation.lastMessage,
        lastMessageTime: conversation.lastMessageTime,
        unreadCount: 0,
        orderStatus: conversation.orderStatus,
      );

      // Mark all messages as read
      final messages = _messagesByConversation[conversationId];
      if (messages != null) {
        for (var i = 0; i < messages.length; i++) {
          if (!messages[i].isRead) {
            messages[i] = StaffChatMessage(
              id: messages[i].id,
              text: messages[i].text,
              senderId: messages[i].senderId,
              recipientId: messages[i].recipientId,
              timestamp: messages[i].timestamp,
              isRead: true,
              attachmentUrl: messages[i].attachmentUrl,
              isFromStaff: messages[i].isFromStaff,
            );
          }
        }
      }
    }
  }

  // Search conversations
  List<StaffConversation> searchConversations(String query) {
    if (query.isEmpty) return getConversations();
    
    final lowerQuery = query.toLowerCase();
    return _conversations.where((conv) {
      final name = conv.participant.name.toLowerCase();
      final orderId = conv.orderId?.toLowerCase() ?? '';
      final role = conv.participant.role.toLowerCase();
      
      return name.contains(lowerQuery) ||
          orderId.contains(lowerQuery) ||
          role.contains(lowerQuery);
    }).toList();
  }
}
