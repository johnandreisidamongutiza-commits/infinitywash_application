enum ChatParticipantType { customer, rider, staff }

class ChatParticipant {
  final String id;
  final String name;
  final ChatParticipantType type;
  final String? phone;
  final bool isOnline;
  final String? avatarUrl;

  ChatParticipant({
    required this.id,
    required this.name,
    required this.type,
    this.phone,
    this.isOnline = false,
    this.avatarUrl,
  });

  String get role {
    switch (type) {
      case ChatParticipantType.customer:
        return 'Customer';
      case ChatParticipantType.rider:
        return 'Delivery Rider';
      case ChatParticipantType.staff:
        return 'Staff Member';
    }
  }
}

class StaffChatMessage {
  final String id;
  final String text;
  final String senderId;
  final String recipientId;
  final DateTime timestamp;
  final bool isRead;
  final String? attachmentUrl;
  final bool isFromStaff;

  StaffChatMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.recipientId,
    required this.timestamp,
    this.isRead = true,
    this.attachmentUrl,
    required this.isFromStaff,
  });
}

class StaffConversation {
  final String id;
  final ChatParticipant participant;
  final String? orderId;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final String? orderStatus;

  StaffConversation({
    required this.id,
    required this.participant,
    this.orderId,
    required this.lastMessage,
    required this.lastMessageTime,
    this.unreadCount = 0,
    this.orderStatus,
  });

  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(lastMessageTime);

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
      return '${lastMessageTime.day}/${lastMessageTime.month}/${lastMessageTime.year}';
    }
  }
}
