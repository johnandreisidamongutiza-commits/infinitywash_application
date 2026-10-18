import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_model.dart';
import 'supabase_service.dart';
import 'profile_service.dart';

class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ProfileService _profileService = ProfileService();
  
  // Collection name in Firestore
  static const String _notificationsCollection = 'announcements'; // Changed to match your Firebase collection
  static const String _notificationReadsTable = 'announcement_reads';

  // Get current user's role (null on failure — callers return empty lists)
  Future<String?> _getCurrentUserRole() async {
    try {
      final profile = await _profileService.getProfile();
      return profile['role'] as String?;
    } catch (e) {
      print('Error getting user role: $e');
      return null;
    }
  }

  // Get current user's profile ID
  String? _getCurrentUserId() {
    return SupabaseService.currentUser?.id;
  }

  // Stream of notifications for current user based on their role
  Stream<List<NotificationModel>> getNotificationsStream() async* {
    final userId = _getCurrentUserId();
    final userRole = await _getCurrentUserRole();
    
    if (userId == null || userRole == null) {
      yield [];
      return;
    }

    // Ultra-simplified query - no orderBy to avoid index requirement
    // We'll sort in-memory after fetching
    yield* _firestore
        .collection(_notificationsCollection)
        .where('status', isEqualTo: 'published')
        .limit(100)
        .snapshots()
        .asyncMap((snapshot) async {
      final notifications = snapshot.docs
          .map((doc) => NotificationModel.fromFirestore(doc))
          .toList();
      
      // Sort by created_at in-memory
      notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      final filtered = notifications
          .where((notif) => 
              notif.audienceRoles.contains(userRole) && 
              !notif.isExpired)
          .take(50)
          .toList();

      // Load read states
      for (var notification in filtered) {
        notification.isRead = await _isNotificationRead(notification.id, userId);
      }

      return filtered;
    });
  }

  // Get notifications as a Future (one-time fetch)
  Future<List<NotificationModel>> getNotifications() async {
    final userId = _getCurrentUserId();
    final userRole = await _getCurrentUserRole();
    
    print('🔍 NotificationService: Fetching notifications');
    print('   User ID: $userId');
    print('   User Role: $userRole');
    
    if (userId == null || userRole == null) {
      print('❌ User ID or role is null, returning empty list');
      return [];
    }

    try {
      // Ultra-simplified query - no orderBy to avoid index requirement
      // We'll sort in-memory after fetching
      final snapshot = await _firestore
          .collection(_notificationsCollection)
          .where('status', isEqualTo: 'published')
          .limit(100)
          .get();

      print('📦 Firestore returned ${snapshot.docs.length} documents');

      final allNotifications = snapshot.docs
          .map((doc) {
            print('   Document ${doc.id}: ${doc.data()}');
            return NotificationModel.fromFirestore(doc);
          })
          .toList();

      print('📋 Parsed ${allNotifications.length} notifications');
      
      // Sort by created_at in-memory
      allNotifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      final filteredNotifications = allNotifications
          .where((notif) {
            final matchesRole = notif.audienceRoles.contains(userRole);
            final notExpired = !notif.isExpired;
            print('   ${notif.title}: role=$matchesRole, expired=${!notExpired}');
            return matchesRole && notExpired;
          })
          .take(50)
          .toList();

      print('✅ After filtering: ${filteredNotifications.length} notifications for role $userRole');

      // Load read states
      for (var notification in filteredNotifications) {
        notification.isRead = await _isNotificationRead(notification.id, userId);
      }

      return filteredNotifications;
    } on FirebaseException catch (e) {
      // Firestore failures degrade to an empty list; screens show their own
      // error/empty state when nothing could be loaded.
      print('❌ Firestore error fetching notifications: ${e.code} ${e.message}');
      return [];
    } catch (e) {
      print('❌ Error fetching notifications: $e');
      return [];
    }
  }

  // Get unread notification count
  Future<int> getUnreadCount() async {
    final userId = _getCurrentUserId();
    final userRole = await _getCurrentUserRole();
    
    if (userId == null || userRole == null) {
      return 0;
    }

    try {
      final notifications = await getNotifications();
      return notifications.where((n) => !n.isRead).length;
    } catch (e) {
      print('Error getting unread count: $e');
      return 0;
    }
  }

  // Stream of unread count
  Stream<int> getUnreadCountStream() async* {
    await for (final notifications in getNotificationsStream()) {
      yield notifications.where((n) => !n.isRead).length;
    }
  }

  // Check if notification is read by user
  Future<bool> _isNotificationRead(String notificationId, String userId) async {
    try {
      final row = await SupabaseService.client
          .from(_notificationReadsTable)
          .select('announcement_id')
          .eq('user_id', userId)
          .eq('announcement_id', notificationId)
          .maybeSingle();
      return row != null;
    } catch (e) {
      print('Error checking read state: $e');
      return false;
    }
  }

  // Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    final userId = _getCurrentUserId();
    if (userId == null) return;

    try {
      await SupabaseService.client.from(_notificationReadsTable).upsert({
        'user_id': userId,
        'announcement_id': notificationId,
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,announcement_id');
    } catch (e) {
      print('Error marking notification as read: $e');
      throw Exception(
        'Could not mark that notification as read. Check your connection and try again.',
      );
    }
  }

  // Mark all notifications as read
  Future<void> markAllAsRead(List<String> notificationIds) async {
    final userId = _getCurrentUserId();
    if (userId == null) return;

    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await SupabaseService.client.from(_notificationReadsTable).upsert(
        notificationIds.map((notificationId) => {
          'user_id': userId,
          'announcement_id': notificationId,
          'read_at': now,
        }).toList(),
        onConflict: 'user_id,announcement_id',
      );
    } catch (e) {
      print('Error marking all notifications as read: $e');
      throw Exception(
        'Could not mark all notifications as read. Check your connection and try again.',
      );
    }
  }

  // Delete old read states (cleanup - optional, can be called periodically)
  Future<void> cleanupOldReadStates({int daysOld = 30}) async {
    final userId = _getCurrentUserId();
    if (userId == null) return;

    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
      await SupabaseService.client
          .from(_notificationReadsTable)
          .delete()
          .eq('user_id', userId)
          .lt('read_at', cutoffDate.toUtc().toIso8601String());
    } catch (e) {
      print('Error cleaning up old read states: $e');
    }
  }
}
