import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Data class returned when a loyalty card is looked up by UID.
class LoyaltyCardInfo {
  final String cardId;
  final String uid;
  final String status;
  final String? customerId;
  final String ownerName;
  final String? ownerPhone;
  final String? ownerEmail;
  final int totalOrders;
  final int totalLoads;
  final int pointsBalance;
  final DateTime createdAt;

  const LoyaltyCardInfo({
    required this.cardId,
    required this.uid,
    required this.status,
    this.customerId,
    required this.ownerName,
    this.ownerPhone,
    this.ownerEmail,
    required this.totalOrders,
    required this.totalLoads,
    required this.pointsBalance,
    required this.createdAt,
  });

  bool get isActive => status == 'active';
  bool get hasOwner => customerId != null;

  /// Alias for UI consistency (same as pointsBalance)
  int get currentPoints => pointsBalance;
  
  /// Alias for UI consistency (same as totalLoads)
  int get totalLoadsCompleted => totalLoads;

  /// Points needed for next free load (10 points = 1 free load)
  int get pointsToNextRedemption {
    final remainder = pointsBalance % 10;
    return remainder == 0 ? (pointsBalance > 0 ? 0 : 10) : 10 - remainder;
  }

  int get freeLoadsAvailable => pointsBalance ~/ 10;

  factory LoyaltyCardInfo.fromJson(Map<String, dynamic> json) {
    return LoyaltyCardInfo(
      cardId: json['card_id'] as String,
      uid: json['uid'] as String,
      status: json['status'] as String? ?? 'active',
      customerId: json['customer_id'] as String?,
      ownerName: json['owner_name'] as String? ?? 'Unassigned Customer',
      ownerPhone: json['owner_phone'] as String?,
      ownerEmail: json['owner_email'] as String?,
      totalOrders: (json['total_orders'] as num?)?.toInt() ?? 0,
      totalLoads: (json['total_loads'] as num?)?.toInt() ?? 0,
      pointsBalance: (json['points_balance'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

/// Data class for a single loyalty points history entry.
class LoyaltyHistoryEntry {
  final String id;
  final String transactionType; // 'earned' | 'redeemed' | 'adjusted'
  final int points;
  final int loadsCount;
  final double discountAmount;
  final String description;
  final String? orderId;
  final DateTime createdAt;

  const LoyaltyHistoryEntry({
    required this.id,
    required this.transactionType,
    required this.points,
    required this.loadsCount,
    required this.discountAmount,
    required this.description,
    this.orderId,
    required this.createdAt,
  });

  factory LoyaltyHistoryEntry.fromJson(Map<String, dynamic> json) {
    return LoyaltyHistoryEntry(
      id: json['id'] as String,
      transactionType: json['transaction_type'] as String,
      points: (json['points'] as num).toInt(),
      loadsCount: (json['loads_count'] as num?)?.toInt() ?? 0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0.0,
      description: json['description'] as String? ?? '',
      orderId: json['order_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class LoyaltyService {
  final SupabaseClient _client = SupabaseService.client;

  // ─── Card Lookup ─────────────────────────────────────────────────────────────

  /// Look up a loyalty card by its physical UID.
  /// Uses the `vw_rfid_loyalty_cards` view which joins profile info.
  /// Returns null if no card found.
  Future<LoyaltyCardInfo?> lookupCardByUid(String uid) async {
    try {
      final cleanUid = uid.trim().toUpperCase();
      print('🔍 Looking up loyalty card: $cleanUid');

      final response = await _client
          .from('vw_rfid_loyalty_cards')
          .select()
          .eq('uid', cleanUid)
          .maybeSingle();

      if (response == null) {
        print('⚠️ No loyalty card found for UID: $cleanUid');
        return null;
      }

      final card = LoyaltyCardInfo.fromJson(response);
      print('✅ Found card for: ${card.ownerName} (${card.pointsBalance} pts)');
      return card;
    } catch (e) {
      print('❌ Error looking up loyalty card: $e');
      rethrow;
    }
  }

  /// Check if a card UID is already registered.
  Future<bool> isCardUidRegistered(String uid) async {
    try {
      final result = await _client
          .from('rfid_loyalty_cards')
          .select('id')
          .eq('uid', uid.trim().toUpperCase())
          .maybeSingle();
      return result != null;
    } catch (e) {
      print('❌ Error checking card UID: $e');
      return false;
    }
  }

  // ─── Card Registration ────────────────────────────────────────────────────────

  /// Register a new loyalty card for an existing customer (by profile_id).
  Future<String> registerCard({
    required String uid,
    required String customerId, // profiles.id
  }) async {
    try {
      final cleanUid = uid.trim().toUpperCase();
      print('🆕 Registering card $cleanUid for customer $customerId');

      final response = await _client
          .from('rfid_loyalty_cards')
          .insert({
            'uid': cleanUid,
            'customer_id': customerId,
            'status': 'active',
            'points_balance': 0,
            'total_orders': 0,
            'total_loads': 0,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();

      final cardId = response['id'] as String;
      print('✅ Card registered: $cardId');
      return cardId;
    } catch (e) {
      print('❌ Error registering loyalty card: $e');
      rethrow;
    }
  }

  /// Register a new unassigned card (no customer yet).
  Future<String> registerUnassignedCard({required String uid}) async {
    try {
      final cleanUid = uid.trim().toUpperCase();
      final response = await _client
          .from('rfid_loyalty_cards')
          .insert({
            'uid': cleanUid,
            'customer_id': null,
            'status': 'active',
            'points_balance': 0,
            'total_orders': 0,
            'total_loads': 0,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();

      return response['id'] as String;
    } catch (e) {
      print('❌ Error registering unassigned card: $e');
      rethrow;
    }
  }

  /// Assign an existing unassigned card to a customer profile.
  Future<void> assignCardToCustomer({
    required String cardId,
    required String customerId,
  }) async {
    try {
      await _client
          .from('rfid_loyalty_cards')
          .update({
            'customer_id': customerId,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', cardId);
      print('✅ Card $cardId assigned to customer $customerId');
    } catch (e) {
      print('❌ Error assigning card to customer: $e');
      rethrow;
    }
  }

  // ─── Points Engine ────────────────────────────────────────────────────────────

  /// Award points to a card when an order is completed.
  /// 1 load = 1 point.
  Future<void> awardPoints({
    required String cardId,
    required String? customerId,
    required String orderId,
    required int loadsCompleted,
    String? orderNumber,
  }) async {
    if (loadsCompleted <= 0) return;

    try {
      // 1. Get current balance
      final cardRow = await _client
          .from('rfid_loyalty_cards')
          .select('points_balance, total_orders, total_loads')
          .eq('id', cardId)
          .single();

      final currentBalance = (cardRow['points_balance'] as num).toInt();
      final currentOrders = (cardRow['total_orders'] as num).toInt();
      final currentLoads = (cardRow['total_loads'] as num).toInt();
      final newBalance = currentBalance + loadsCompleted;

      // 2. Update card totals
      await _client
          .from('rfid_loyalty_cards')
          .update({
            'points_balance': newBalance,
            'total_orders': currentOrders + 1,
            'total_loads': currentLoads + loadsCompleted,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', cardId);

      // 3. Log history entry
      await _client.from('loyalty_points_history').insert({
        'card_id': cardId,
        'customer_id': customerId,
        'order_id': orderId,
        'transaction_type': 'earned',
        'points': loadsCompleted,
        'loads_count': loadsCompleted,
        'discount_amount': 0.00,
        'description':
            'Earned $loadsCompleted pt${loadsCompleted > 1 ? 's' : ''} for completing ${orderNumber ?? 'order'} ($loadsCompleted load${loadsCompleted > 1 ? 's' : ''})',
        'created_at': DateTime.now().toIso8601String(),
      });

      print('✅ Awarded $loadsCompleted pt(s) — new balance: $newBalance');
    } catch (e) {
      print('❌ Error awarding points: $e');
      rethrow;
    }
  }

  /// Redeem points for free loads.
  /// 10 points = 1 free load (₱170 discount).
  Future<double> redeemPoints({
    required String cardId,
    required String? customerId,
    required int freeLoadsToRedeem,
    required String orderId,
    String? orderNumber,
  }) async {
    const int pointsPerLoad = 10;
    const double discountPerLoad = 170.0;

    final pointsToDeduct = freeLoadsToRedeem * pointsPerLoad;
    final discountAmount = freeLoadsToRedeem * discountPerLoad;

    try {
      // 1. Get current balance
      final cardRow = await _client
          .from('rfid_loyalty_cards')
          .select('points_balance')
          .eq('id', cardId)
          .single();

      final currentBalance = (cardRow['points_balance'] as num).toInt();
      if (currentBalance < pointsToDeduct) {
        throw Exception(
            'Insufficient points: $currentBalance < $pointsToDeduct required');
      }

      final newBalance = currentBalance - pointsToDeduct;

      // 2. Update card balance
      await _client
          .from('rfid_loyalty_cards')
          .update({
            'points_balance': newBalance,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', cardId);

      // 3. Log history entry
      await _client.from('loyalty_points_history').insert({
        'card_id': cardId,
        'customer_id': customerId,
        'order_id': orderId,
        'transaction_type': 'redeemed',
        'points': -pointsToDeduct,
        'loads_count': freeLoadsToRedeem,
        'discount_amount': discountAmount,
        'description':
            'Redeemed $pointsToDeduct pts for $freeLoadsToRedeem free load${freeLoadsToRedeem > 1 ? 's' : ''} (₱${discountAmount.toStringAsFixed(0)} off) on ${orderNumber ?? 'order'}',
        'created_at': DateTime.now().toIso8601String(),
      });

      print(
          '✅ Redeemed $pointsToDeduct pts — new balance: $newBalance — discount: ₱$discountAmount');
      return discountAmount;
    } catch (e) {
      print('❌ Error redeeming points: $e');
      rethrow;
    }
  }

  // ─── Points History ───────────────────────────────────────────────────────────

  /// Fetch the points transaction history for a card.
  Future<List<LoyaltyHistoryEntry>> getPointsHistory(String cardId,
      {int limit = 20}) async {
    try {
      final response = await _client
          .from('loyalty_points_history')
          .select()
          .eq('card_id', cardId)
          .order('created_at', ascending: false)
          .limit(limit);

      return response
          .map((row) => LoyaltyHistoryEntry.fromJson(row))
          .toList();
    } catch (e) {
      print('❌ Error fetching points history: $e');
      return [];
    }
  }

  // ─── Customer Search ──────────────────────────────────────────────────────────

  /// Search profiles by name or phone (for card registration flow).
  Future<List<Map<String, dynamic>>> searchCustomers(String query) async {
    try {
      final q = query.trim().toLowerCase();
      if (q.isEmpty) return [];

      final response = await _client
          .from('profiles')
          .select('id, first_name, last_name, phone, email, username')
          .or('first_name.ilike.%$q%,last_name.ilike.%$q%,phone.ilike.%$q%,email.ilike.%$q%')
          .limit(10);

      return response.cast<Map<String, dynamic>>();
    } catch (e) {
      print('❌ Error searching customers: $e');
      return [];
    }
  }

  /// Get all loyalty cards for a specific customer (by profile_id).
  Future<List<LoyaltyCardInfo>> getCardsForCustomer(
      String customerId) async {
    try {
      final response = await _client
          .from('vw_rfid_loyalty_cards')
          .select()
          .eq('customer_id', customerId);

      return response
          .map((row) => LoyaltyCardInfo.fromJson(row))
          .toList();
    } catch (e) {
      print('❌ Error fetching cards for customer: $e');
      return [];
    }
  }

  // ─── Customer Card Linking (Mobile App) ──────────────────────────────────────

  /// Link a loyalty card to a customer profile via card code entry.
  /// This is the mobile app version where customers manually enter their card code.
  Future<void> linkCardToCustomer({
    required String cardUid,
    required String customerId,
  }) async {
    try {
      final cleanUid = cardUid.trim().toUpperCase();
      print('🔗 Linking card $cleanUid to customer $customerId');

      // Verify card exists
      final card = await lookupCardByUid(cleanUid);
      if (card == null) {
        throw Exception('Card not found. Please check the card code and try again.');
      }

      // Check if already linked to another customer
      if (card.hasOwner && card.customerId != customerId) {
        throw Exception('This card is already linked to another customer.');
      }

      // Link card to customer by updating customer_id in rfid_loyalty_cards table
      await _client.from('rfid_loyalty_cards').update({
        'customer_id': customerId,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('uid', cleanUid);

      print('✅ Successfully linked card $cleanUid to customer $customerId');
    } catch (e) {
      print('❌ Error linking card: $e');
      rethrow;
    }
  }

  /// Get the linked loyalty card for a customer (returns first active card).
  /// Used in mobile app to auto-detect customer's loyalty card.
  Future<LoyaltyCardInfo?> getLinkedCard(String customerId) async {
    try {
      final response = await _client
          .from('vw_rfid_loyalty_cards')
          .select()
          .eq('customer_id', customerId)
          .eq('status', 'active')
          .maybeSingle();

      if (response == null) {
        print('ℹ️ No linked card found for customer $customerId');
        return null;
      }

      final card = LoyaltyCardInfo.fromJson(response);
      print('✅ Found linked card for customer: ${card.uid} (${card.pointsBalance} pts)');
      return card;
    } catch (e) {
      print('❌ Error getting linked card: $e');
      return null;
    }
  }

  /// Unlink a card from customer (removes customer_id association).
  /// Card remains active but unassigned.
  Future<void> unlinkCard(String cardUid) async {
    try {
      final cleanUid = cardUid.trim().toUpperCase();
      print('🔓 Unlinking card $cleanUid');

      await _client.from('rfid_loyalty_cards').update({
        'customer_id': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('uid', cleanUid);

      print('✅ Card $cleanUid unlinked successfully');
    } catch (e) {
      print('❌ Error unlinking card: $e');
      rethrow;
    }
  }
}
