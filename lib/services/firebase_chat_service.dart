import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_model.dart';
import 'photo_file_service.dart';
import 'supabase_service.dart';


class FirebaseChatService {
  static final FirebaseChatService _instance = FirebaseChatService._internal();
  factory FirebaseChatService() => _instance;
  static FirebaseChatService get instance => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  CollectionReference get _chatsCollection => _firestore.collection('chats');

  FirebaseChatService._internal() {
    try {
      _firestore.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (e) {
      debugPrint('Firestore settings note: $e');
    }
  }

  /// Deterministic ID generator for customer <-> staff support
  String getSupportChatId(String customerId) => 'support_$customerId';

  /// Deterministic ID generator for rider <-> staff dispatch
  String getRiderStaffChatId(String riderId) => 'dispatch_$riderId';

  /// Deterministic ID generator for customer <-> rider order chat
  String getOrderChatId(String orderId, String customerId, String riderId) =>
      'order_${orderId.replaceAll('#', '').trim()}_${customerId}_$riderId';

  /// Retrieves or creates a customer <-> shop support conversation
  Future<ChatConversation> getOrCreateSupportChat({
    required String customerId,
    required String customerName,
    String? customerPhone,
    String? customerAvatar,
    String? orderId,
  }) async {
    final chatId = getSupportChatId(customerId);
    final docRef = _chatsCollection.doc(chatId);
    final authId = SupabaseService.currentUser?.id;
    final Set<String> pList = {customerId, 'role:staff'};
    if (authId != null && authId.isNotEmpty) pList.add(authId);

    try {
      final snapshot = await docRef.get();

      if (!snapshot.exists) {
        final now = FieldValue.serverTimestamp();
        final data = {
          'id': chatId,
          'chat_type': 'customer_support',
          'order_id': orderId,
          'participants': pList.toList(),
          'participant_roles': {
            customerId: 'customer',
            'role:staff': 'staff',
          },
          'participant_names': {
            customerId: customerName,
            'role:staff': 'InfinityWash Support',
          },
          'participant_avatars': {
            customerId: customerAvatar,
            'role:staff': null,
          },
          'participant_phones': {
            customerId: customerPhone,
            'role:staff': '0912-345-6789',
          },
          'last_message':
              'Hello! Welcome to InfinityWash Support. 🫧 How can we assist you?',
          'last_sender_id': 'role:staff',
          'last_sender_name': 'InfinityWash Support',
          'last_timestamp': now,
          'unread_counts': {
            customerId: 0,
            'role:staff': 0,
          },
          'created_at': now,
          'updated_at': now,
        };

        await docRef.set(data);

        await docRef.collection('messages').add({
          'chat_id': chatId,
          'sender_id': 'role:staff',
          'sender_name': 'InfinityWash Support',
          'sender_role': 'staff',
          'text':
              'Hello! Welcome to InfinityWash Support. 🫧 How can we assist you today?',
          'timestamp': now,
          'is_read': true,
        });

        final createdDoc = await docRef.get();
        return ChatConversation.fromFirestore(createdDoc);
      }

      return ChatConversation.fromFirestore(snapshot);
    } catch (e) {
      debugPrint('⚠️ Notice: getOrCreateSupportChat ($chatId): $e');
      return ChatConversation(
        id: chatId,
        chatType: ChatType.customerSupport,
        orderId: orderId,
        participants: pList.toList(),
        participantRoles: {customerId: 'customer', 'role:staff': 'staff'},
        participantNames: {customerId: customerName, 'role:staff': 'InfinityWash Support'},
        participantAvatars: {customerId: customerAvatar, 'role:staff': null},
        participantPhones: {customerId: customerPhone, 'role:staff': '0912-345-6789'},
        lastMessage: 'Connecting to support...',
        lastSenderId: 'role:staff',
        lastTimestamp: DateTime.now(),
        unreadCounts: {customerId: 0, 'role:staff': 0},
      );
    }
  }

  /// Retrieves or creates a rider <-> shop dispatch conversation
  Future<ChatConversation> getOrCreateRiderStaffChat({
    required String riderId,
    required String riderName,
    String? riderPhone,
    String? riderAvatar,
  }) async {
    final chatId = getRiderStaffChatId(riderId);
    final docRef = _chatsCollection.doc(chatId);
    final authId = SupabaseService.currentUser?.id;
    final Set<String> pList = {riderId, 'role:staff'};
    if (authId != null && authId.isNotEmpty) pList.add(authId);

    try {
      final snapshot = await docRef.get();

      if (!snapshot.exists) {
        final now = FieldValue.serverTimestamp();
        final data = {
          'id': chatId,
          'chat_type': 'rider_staff',
          'participants': pList.toList(),
          'participant_roles': {
            riderId: 'rider',
            'role:staff': 'staff',
          },
          'participant_names': {
            riderId: riderName,
            'role:staff': 'InfinityWash Dispatch',
          },
          'participant_avatars': {
            riderId: riderAvatar,
            'role:staff': null,
          },
          'participant_phones': {
            riderId: riderPhone,
            'role:staff': '0912-345-6789',
          },
          'last_message': 'Rider dispatch channel opened.',
          'last_sender_id': 'role:staff',
          'last_sender_name': 'InfinityWash Dispatch',
          'last_timestamp': now,
          'unread_counts': {
            riderId: 0,
            'role:staff': 0,
          },
          'created_at': now,
          'updated_at': now,
        };

        await docRef.set(data);
        final createdDoc = await docRef.get();
        return ChatConversation.fromFirestore(createdDoc);
      }

      return ChatConversation.fromFirestore(snapshot);
    } catch (e) {
      debugPrint('⚠️ Notice: getOrCreateRiderStaffChat ($chatId): $e');
      return ChatConversation(
        id: chatId,
        chatType: ChatType.riderStaff,
        participants: pList.toList(),
        participantRoles: {riderId: 'rider', 'role:staff': 'staff'},
        participantNames: {riderId: riderName, 'role:staff': 'InfinityWash Dispatch'},
        participantAvatars: {riderId: riderAvatar, 'role:staff': null},
        participantPhones: {riderId: riderPhone, 'role:staff': '0912-345-6789'},
        lastMessage: 'Rider dispatch channel opened.',
        lastSenderId: 'role:staff',
        lastTimestamp: DateTime.now(),
        unreadCounts: {riderId: 0, 'role:staff': 0},
      );
    }
  }

  /// Retrieves or creates a customer <-> assigned rider conversation for an order
  Future<ChatConversation> getOrCreateOrderChat({
    required String orderId,
    required String customerId,
    required String customerName,
    required String riderId,
    required String riderName,
    String? customerPhone,
    String? riderPhone,
    String? customerAvatar,
    String? riderAvatar,
  }) async {
    final chatId = getOrderChatId(orderId, customerId, riderId);
    final docRef = _chatsCollection.doc(chatId);
    final authId = SupabaseService.currentUser?.id;
    final Set<String> pList = {customerId, riderId};
    if (authId != null && authId.isNotEmpty) pList.add(authId);

    try {
      final snapshot = await docRef.get();

      if (!snapshot.exists) {
        final now = FieldValue.serverTimestamp();
        final data = {
          'id': chatId,
          'chat_type': 'customer_rider',
          'order_id': orderId,
          'participants': pList.toList(),
          'participant_roles': {
            customerId: 'customer',
            riderId: 'rider',
          },
          'participant_names': {
            customerId: customerName,
            riderId: riderName,
          },
          'participant_avatars': {
            customerId: customerAvatar,
            riderId: riderAvatar,
          },
          'participant_phones': {
            customerId: customerPhone,
            riderId: riderPhone,
          },
          'last_message': 'Chat started for order #$orderId',
          'last_sender_id': customerId,
          'last_sender_name': customerName,
          'last_timestamp': now,
          'unread_counts': {
            customerId: 0,
            riderId: 0,
          },
          'created_at': now,
          'updated_at': now,
        };

        await docRef.set(data);
        final createdDoc = await docRef.get();
        return ChatConversation.fromFirestore(createdDoc);
      }

      return ChatConversation.fromFirestore(snapshot);
    } catch (e) {
      debugPrint('⚠️ Notice: getOrCreateOrderChat ($chatId): $e');
      return ChatConversation(
        id: chatId,
        chatType: ChatType.customerRider,
        orderId: orderId,
        participants: pList.toList(),
        participantRoles: {customerId: 'customer', riderId: 'rider'},
        participantNames: {customerId: customerName, riderId: riderName},
        participantAvatars: {customerId: customerAvatar, riderId: riderAvatar},
        participantPhones: {customerId: customerPhone, riderId: riderPhone},
        lastMessage: 'Chat for order #$orderId',
        lastSenderId: customerId,
        lastTimestamp: DateTime.now(),
        unreadCounts: {customerId: 0, riderId: 0},
      );
    }
  }

  /// Real-time stream of conversations for any user role.
  /// Free tier protection: limits staff query to the top [limit] conversations.
  Stream<List<ChatConversation>> streamConversations({
    required String currentUserId,
    required String currentRole,
    int limit = 30,
  }) {
    Query query;

    if (currentRole == 'staff') {
      // All staff members see conversations involving the store support pool, bounded by limit
      query = _chatsCollection
          .where('participants', arrayContains: 'role:staff')
          .limit(limit);
    } else {
      // Customer or Rider sees their own conversations
      query = _chatsCollection.where(
        'participants',
        arrayContains: currentUserId,
      );
    }

    return query.snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => ChatConversation.fromFirestore(doc))
          .toList();

      // Sort newest first in-memory (guarantees fast loading without Firestore composite index errors)
      list.sort((a, b) => b.lastTimestamp.compareTo(a.lastTimestamp));
      return list;
    }).handleError((error) {
      debugPrint('⚠️ Chat conversations stream notice: $error');
      return <ChatConversation>[];
    });
  }

  /// Real-time stream of the total unread badge count for the current user/role
  Stream<int> streamTotalUnreadCount({
    required String currentUserId,
    required String currentRole,
  }) {
    return streamConversations(
      currentUserId: currentUserId,
      currentRole: currentRole,
    ).map((conversations) {
      int total = 0;
      for (final conv in conversations) {
        total += conv.getUnreadCount(currentUserId, currentRole);
      }
      return total;
    }).handleError((error) {
      debugPrint('⚠️ Unread badge stream notice: $error');
      return 0;
    });
  }

  /// Real-time stream of latest messages in a single conversation.
  /// Default limit is set to 20 to preserve Firebase Spark (free tier) quota.
  Stream<List<ChatMessage>> streamMessages(String chatId, {int limit = 20}) {
    return _chatsCollection
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .limitToLast(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ChatMessage.fromFirestore(doc))
          .toList();
    }).handleError((error) {
      debugPrint('⚠️ Chat messages stream notice: $error');
      return <ChatMessage>[];
    });
  }

  /// Fetches a historical batch of earlier messages before a given timestamp using a one-time get().
  /// This saves free-tier reads because older messages are NOT continuously re-read by realtime listeners.
  Future<List<ChatMessage>> loadEarlierMessages({
    required String chatId,
    required DateTime beforeTimestamp,
    int limit = 20,
  }) async {
    try {
      final snapshot = await _chatsCollection
          .doc(chatId)
          .collection('messages')
          .where('timestamp', isLessThan: Timestamp.fromDate(beforeTimestamp))
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      final list = snapshot.docs
          .map((doc) => ChatMessage.fromFirestore(doc))
          .toList();

      // Return chronological order (oldest -> newest)
      return list.reversed.toList();
    } catch (e) {
      debugPrint('⚠️ Error loading earlier messages for $chatId: $e');
      return [];
    }
  }

  /// Sends a text message or image attachment
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String senderRole,
    required String text,
    String? attachmentUrl,
    String? attachmentType,
    required List<String> participants,
  }) async {
    final docRef = _chatsCollection.doc(chatId);
    final messagesRef = docRef.collection('messages');
    final now = FieldValue.serverTimestamp();

    // 1. Add message document
    await messagesRef.add({
      'chat_id': chatId,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_role': senderRole,
      'text': text,
      'timestamp': now,
      'attachment_url': attachmentUrl,
      'attachment_type': attachmentType,
      'is_read': false,
    });

    // 2. Prepare unread count increments for recipients
    final summaryText = (attachmentUrl != null && text.trim().isEmpty)
        ? '📷 Photo'
        : text.trim();

    final Map<String, dynamic> updateData = {
      'last_message': summaryText,
      'last_sender_id': senderId,
      'last_sender_name': senderName,
      'last_timestamp': now,
      'updated_at': now,
    };

    for (final p in participants) {
      if (p == senderId) continue;

      if (senderRole == 'staff') {
        // Staff sending message: increment non-staff recipient
        if (p != 'role:staff') {
          updateData['unread_counts.$p'] = FieldValue.increment(1);
        }
      } else {
        // Customer or Rider sending message:
        if (p == 'role:staff') {
          updateData['unread_counts.role:staff'] = FieldValue.increment(1);
        } else {
          updateData['unread_counts.$p'] = FieldValue.increment(1);
        }
      }
    }

    await docRef.update(updateData);
  }

  /// Resets unread count for current viewer
  Future<void> markAsRead({
    required String chatId,
    required String currentUserId,
    required String currentRole,
  }) async {
    try {
      final docRef = _chatsCollection.doc(chatId);
      final key = currentRole == 'staff' ? 'role:staff' : currentUserId;
      await docRef.update({
        'unread_counts.$key': 0,
      });
    } catch (e) {
      debugPrint('Chat markAsRead error: $e');
    }
  }

  /// Uploads compressed image to Firebase Storage and returns download URL.
  /// If Firebase Storage fails or is restricted, falls back gracefully to
  /// Supabase Storage so photo sending never fails for the user.
  Future<String> uploadChatImage(File originalImage, String chatId) async {
    File? compressedFile;
    try {
      // 1. Compress image client-side to save bandwidth and storage
      compressedFile = await PhotoFileService.prepareForUpload(originalImage);

      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // 2. Attempt upload to Firebase Storage
      try {
        final ref =
            _storage.ref().child('chat_attachments/$chatId/$timestamp.jpg');

        final uploadTask = ref.putFile(
          compressedFile,
          SettableMetadata(contentType: 'image/jpeg'),
        );

        final snapshot = await uploadTask.whenComplete(() {});
        final downloadUrl = await snapshot.ref.getDownloadURL();
        debugPrint('✅ Chat photo uploaded to Firebase Storage: $downloadUrl');
        return downloadUrl;
      } catch (firebaseError) {
        debugPrint(
            '⚠️ Firebase Storage upload error: $firebaseError. Falling back to Supabase Storage...');

        // 3. Fallback to Supabase Storage if Firebase rules/bucket are not yet active
        try {
          final bytes = await compressedFile.readAsBytes();
          final supabasePath = 'chat_attachments/$chatId/$timestamp.jpg';

          await SupabaseService.client.storage
              .from('payment-receipts')
              .uploadBinary(
                supabasePath,
                bytes,
                fileOptions: const FileOptions(
                  contentType: 'image/jpeg',
                  upsert: true,
                ),
              );

          final fallbackUrl = SupabaseService.client.storage
              .from('payment-receipts')
              .getPublicUrl(supabasePath);
          debugPrint('✅ Chat photo uploaded via fallback storage: $fallbackUrl');
          return fallbackUrl;
        } catch (fallbackError) {
          debugPrint(
              '❌ Fallback storage also failed: $fallbackError. Original: $firebaseError');
          // Throw the primary error so caller displays a meaningful message
          throw firebaseError;
        }
      }
    } finally {
      if (compressedFile != null) {
        await PhotoFileService.deleteTemporary(compressedFile);
      }
    }
  }

  /// Search for customers or riders from Supabase to start a new chat
  Future<List<Map<String, dynamic>>> searchChatRecipients({
    required String role, // 'customer' or 'rider'
    String query = '',
  }) async {
    try {
      var queryBuilder = SupabaseService.client
          .from('profiles')
          .select('id, first_name, last_name, role, phone, avatar_url')
          .eq('role', role);

      if (query.trim().isNotEmpty) {
        final q = query.trim();
        queryBuilder = queryBuilder.or('first_name.ilike.%$q%,last_name.ilike.%$q%,phone.ilike.%$q%');
      }

      final response = await queryBuilder
          .order('first_name', ascending: true)
          .limit(30);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error searching chat recipients: $e');
      return [];
    }
  }
}
