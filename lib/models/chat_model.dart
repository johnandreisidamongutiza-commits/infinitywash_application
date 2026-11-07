import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/order_number_resolver.dart';

enum ChatType {
  customerSupport,
  riderStaff,
  customerRider;

  String toDb() {
    switch (this) {
      case ChatType.customerSupport:
        return 'customer_support';
      case ChatType.riderStaff:
        return 'rider_staff';
      case ChatType.customerRider:
        return 'customer_rider';
    }
  }

  static ChatType fromDb(String? value) {
    switch (value) {
      case 'rider_staff':
        return ChatType.riderStaff;
      case 'customer_rider':
        return ChatType.customerRider;
      case 'customer_support':
      default:
        return ChatType.customerSupport;
    }
  }
}

class ChatMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String senderRole; // 'customer' | 'staff' | 'rider'
  final String text;
  final DateTime timestamp;
  final String? attachmentUrl;
  final String? attachmentType;
  final bool isRead;

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.text,
    required this.timestamp,
    this.attachmentUrl,
    this.attachmentType,
    this.isRead = true,
  });

  bool isFromMe(String currentUserId) => senderId == currentUserId;

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    
    DateTime parsedTime = DateTime.now();
    final rawTs = data['timestamp'];
    if (rawTs is Timestamp) {
      parsedTime = rawTs.toDate();
    } else if (rawTs is String) {
      parsedTime = DateTime.tryParse(rawTs) ?? DateTime.now();
    }

    return ChatMessage(
      id: doc.id,
      chatId: data['chat_id'] as String? ?? '',
      senderId: data['sender_id'] as String? ?? '',
      senderName: data['sender_name'] as String? ?? 'User',
      senderRole: data['sender_role'] as String? ?? 'customer',
      text: data['text'] as String? ?? '',
      timestamp: parsedTime,
      attachmentUrl: data['attachment_url'] as String?,
      attachmentType: data['attachment_type'] as String?,
      isRead: data['is_read'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'chat_id': chatId,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_role': senderRole,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'attachment_url': attachmentUrl,
      'attachment_type': attachmentType,
      'is_read': isRead,
    };
  }
}

class ChatConversation {
  final String id;
  final ChatType chatType;
  final String? orderId;
  final String? orderNumber;
  final List<String> participants;
  final Map<String, String> participantRoles;
  final Map<String, String> participantNames;
  final Map<String, String?> participantAvatars;
  final Map<String, String?> participantPhones;
  final String lastMessage;
  final String lastSenderId;
  final String? lastSenderName;
  final DateTime lastTimestamp;
  final Map<String, int> unreadCounts;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ChatConversation({
    required this.id,
    required this.chatType,
    this.orderId,
    this.orderNumber,
    required this.participants,
    required this.participantRoles,
    required this.participantNames,
    required this.participantAvatars,
    required this.participantPhones,
    required this.lastMessage,
    required this.lastSenderId,
    this.lastSenderName,
    required this.lastTimestamp,
    required this.unreadCounts,
    this.createdAt,
    this.updatedAt,
  });

  /// Returns the human-readable order number (e.g. REQ-261003-002)
  String? get displayOrderNumber {
    if (orderNumber != null &&
        orderNumber!.trim().isNotEmpty &&
        !OrderNumberResolver.isUuid(orderNumber)) {
      return orderNumber!.trim();
    }
    if (orderId != null && orderId!.trim().isNotEmpty) {
      final trimmed = orderId!.trim();
      if (!OrderNumberResolver.isUuid(trimmed)) return trimmed;
      return OrderNumberResolver.resolveSync(
        orderId: trimmed,
        orderNumber: orderNumber,
      );
    }
    return null;
  }

  /// Formats the last message preview, converting any raw order UUIDs into readable order numbers.
  String get displayLastMessage {
    if (lastMessage.startsWith('Chat started for order #') ||
        lastMessage.startsWith('Chat for order #')) {
      final disp = displayOrderNumber;
      if (disp != null && disp.isNotEmpty) {
        final ticket = disp.startsWith('#') ? disp : '#$disp';
        return 'Chat started for order $ticket';
      }
    }
    return lastMessage;
  }

  String getOtherParticipantName(String currentUserId, String currentRole) {
    if (chatType == ChatType.customerSupport && currentRole != 'staff') {
      return 'InfinityWash Support';
    }
    if (chatType == ChatType.riderStaff && currentRole == 'rider') {
      return 'InfinityWash Staff';
    }

    // Look for non-self participant
    for (final pId in participants) {
      if (pId != currentUserId && !pId.startsWith('role:')) {
        return participantNames[pId] ?? 'Participant';
      }
    }
    return participantNames.values.firstWhere(
      (name) => name != 'InfinityWash Support',
      orElse: () => 'Customer',
    );
  }

  String getOtherParticipantRole(String currentUserId, String currentRole) {
    if (chatType == ChatType.customerSupport && currentRole != 'staff') {
      return 'Official Store Helpdesk';
    }
    if (chatType == ChatType.riderStaff && currentRole == 'rider') {
      return 'Shop Staff';
    }

    for (final pId in participants) {
      if (pId != currentUserId && !pId.startsWith('role:')) {
        final role = participantRoles[pId]?.toLowerCase();
        if (role == 'customer') return 'Customer';
        if (role == 'rider') return 'Delivery Rider';
        if (role == 'staff') return 'Staff Member';
        return role ?? 'User';
      }
    }
    return 'Customer';
  }

  String? getOtherParticipantAvatar(String currentUserId, String currentRole) {
    for (final pId in participants) {
      if (pId != currentUserId && !pId.startsWith('role:')) {
        return participantAvatars[pId];
      }
    }
    return null;
  }

  String? getOtherParticipantPhone(String currentUserId, String currentRole) {
    for (final pId in participants) {
      if (pId != currentUserId && !pId.startsWith('role:')) {
        return participantPhones[pId];
      }
    }
    return null;
  }

  int getUnreadCount(String currentUserId, String currentRole) {
    if (currentRole == 'staff') {
      return unreadCounts['role:staff'] ?? unreadCounts[currentUserId] ?? 0;
    }
    return unreadCounts[currentUserId] ?? 0;
  }

  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(lastTimestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${lastTimestamp.day}/${lastTimestamp.month}/${lastTimestamp.year}';
    }
  }

  factory ChatConversation.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    DateTime parsedLastTime = DateTime.now();
    final rawTs = data['last_timestamp'];
    if (rawTs is Timestamp) {
      parsedLastTime = rawTs.toDate();
    } else if (rawTs is String) {
      parsedLastTime = DateTime.tryParse(rawTs) ?? DateTime.now();
    }

    final rawParticipants = data['participants'];
    final participants = rawParticipants is List
        ? rawParticipants.map((e) => e.toString()).toList()
        : <String>[];

    final rawRoles = data['participant_roles'] as Map<String, dynamic>? ?? {};
    final participantRoles = rawRoles.map((k, v) => MapEntry(k, v.toString()));

    final rawNames = data['participant_names'] as Map<String, dynamic>? ?? {};
    final participantNames = rawNames.map((k, v) => MapEntry(k, v.toString()));

    final rawAvatars = data['participant_avatars'] as Map<String, dynamic>? ?? {};
    final participantAvatars = rawAvatars.map((k, v) => MapEntry(k, v?.toString()));

    final rawPhones = data['participant_phones'] as Map<String, dynamic>? ?? {};
    final participantPhones = rawPhones.map((k, v) => MapEntry(k, v?.toString()));

    final rawUnread = data['unread_counts'] as Map<String, dynamic>? ?? {};
    final unreadCounts = rawUnread.map((k, v) {
      final count = v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0;
      return MapEntry(k, count);
    });

    return ChatConversation(
      id: doc.id,
      chatType: ChatType.fromDb(data['chat_type'] as String?),
      orderId: data['order_id'] as String?,
      orderNumber: data['order_number'] as String?,
      participants: participants,
      participantRoles: participantRoles,
      participantNames: participantNames,
      participantAvatars: participantAvatars,
      participantPhones: participantPhones,
      lastMessage: data['last_message'] as String? ?? '',
      lastSenderId: data['last_sender_id'] as String? ?? '',
      lastSenderName: data['last_sender_name'] as String?,
      lastTimestamp: parsedLastTime,
      unreadCounts: unreadCounts,
    );
  }
}
