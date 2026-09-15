import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String title;
  final String message;
  final String type; // announcement, order_update, payment, delivery, alert, etc.
  final List<String> audienceRoles; // customer, staff, rider
  final String? createdBy;
  final DateTime createdAt;
  final DateTime? publishedAt;
  final DateTime? expiresAt;
  final String status; // draft, published, archived
  final String? relatedOrderId;
  final String? announcementId;
  bool isRead;

  NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.audienceRoles,
    this.createdBy,
    required this.createdAt,
    this.publishedAt,
    this.expiresAt,
    required this.status,
    this.relatedOrderId,
    this.announcementId,
    this.isRead = false,
  });

  // Create from Firestore document
  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return NotificationModel(
      id: doc.id,
      title: data['title'] ?? '',
      message: data['message'] ?? data['body'] ?? '',
      type: data['type'] ?? 'announcement',
      audienceRoles: List<String>.from(data['audience_roles'] ?? data['audienceRoles'] ?? []),
      createdBy: data['created_by'] ?? data['createdBy'],
      createdAt: _parseDateTime(data['created_at'] ?? data['createdAt'], required: true)!,
      publishedAt: _parseDateTime(data['published_at'] ?? data['publishedAt']),
      expiresAt: _parseDateTime(data['expires_at'] ?? data['expiresAt']),
      status: data['status'] ?? 'published',
      relatedOrderId: data['related_order_id'] ?? data['relatedOrderId'],
      announcementId: data['announcement_id'] ?? data['announcementId'],
      isRead: data['is_read'] ?? data['isRead'] ?? false,
    );
  }

  // Helper to parse DateTime from various formats
  static DateTime? _parseDateTime(dynamic value, {bool required = false}) {
    if (value == null) {
      return required ? DateTime.now() : null; // Only return DateTime.now() if required
    }
    
    if (value is Timestamp) {
      return value.toDate();
    }
    
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return required ? DateTime.now() : null;
      }
    }
    
    if (value is DateTime) {
      return value;
    }
    
    return required ? DateTime.now() : null;
  }

  // Convert to map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'message': message,
      'type': type,
      'audience_roles': audienceRoles,
      'created_by': createdBy,
      'created_at': Timestamp.fromDate(createdAt),
      'published_at': publishedAt != null ? Timestamp.fromDate(publishedAt!) : null,
      'expires_at': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'status': status,
      'related_order_id': relatedOrderId,
      'announcement_id': announcementId,
      'is_read': isRead,
    };
  }

  // Copy with method for updating properties
  NotificationModel copyWith({
    String? id,
    String? title,
    String? message,
    String? type,
    List<String>? audienceRoles,
    String? createdBy,
    DateTime? createdAt,
    DateTime? publishedAt,
    DateTime? expiresAt,
    String? status,
    String? relatedOrderId,
    String? announcementId,
    bool? isRead,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      audienceRoles: audienceRoles ?? this.audienceRoles,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      publishedAt: publishedAt ?? this.publishedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      status: status ?? this.status,
      relatedOrderId: relatedOrderId ?? this.relatedOrderId,
      announcementId: announcementId ?? this.announcementId,
      isRead: isRead ?? this.isRead,
    );
  }

  // Check if notification is expired
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  // Get time ago string
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays > 7) {
      return '${createdAt.month}/${createdAt.day}/${createdAt.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} min${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }
}
