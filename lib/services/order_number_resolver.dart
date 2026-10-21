import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';
import '../models/order.dart';

/// Resolves true database order numbers (e.g. REQ-261003-002) for chats
/// that only store raw database UUIDs.
class OrderNumberResolver {
  static final Map<String, String> _cache = {};
  static final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool isUuid(String? val) {
    if (val == null) return false;
    return _uuidRegex.hasMatch(val.trim());
  }

  /// Synchronously returns the formatted order number using cache if available.
  static String resolveSync({String? orderId, String? orderNumber}) {
    if (orderNumber != null &&
        orderNumber.trim().isNotEmpty &&
        !isUuid(orderNumber)) {
      return orderNumber.trim();
    }
    if (orderId == null || orderId.trim().isEmpty) return '';
    final trimmedId = orderId.trim();
    if (!isUuid(trimmedId)) return trimmedId;

    if (_cache.containsKey(trimmedId)) {
      return _cache[trimmedId]!;
    }
    return LaundryOrder.formatDisplayNumber(id: trimmedId);
  }

  /// Asynchronously queries Supabase for the true order_number (e.g. REQ-261003-002),
  /// caches the result, notifies listeners, and optionally updates the Firestore chat document.
  static Future<String> resolveAsync({
    required String orderId,
    String? orderNumber,
    String? chatId,
  }) async {
    final trimmedId = orderId.trim();
    if (orderNumber != null &&
        orderNumber.trim().isNotEmpty &&
        !isUuid(orderNumber)) {
      _cache[trimmedId] = orderNumber.trim();
      return orderNumber.trim();
    }

    if (!isUuid(trimmedId)) {
      _cache[trimmedId] = trimmedId;
      return trimmedId;
    }

    if (_cache.containsKey(trimmedId)) {
      return _cache[trimmedId]!;
    }

    try {
      final res = await SupabaseService.client
          .from('orders')
          .select('order_number')
          .eq('id', trimmedId)
          .maybeSingle();

      if (res != null && res['order_number'] != null) {
        final realNumber = res['order_number'].toString().trim();
        if (realNumber.isNotEmpty) {
          _cache[trimmedId] = realNumber;
          changeNotifier.value++;

          // Patch Firestore document so future reads from Firestore don't need Supabase
          if (chatId != null && chatId.isNotEmpty) {
            FirebaseFirestore.instance
                .collection('chats')
                .doc(chatId)
                .update({'order_number': realNumber})
                .catchError((_) {});
          }

          return realNumber;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error resolving order_number for $trimmedId: $e');
    }

    final fallback = LaundryOrder.formatDisplayNumber(id: trimmedId);
    _cache[trimmedId] = fallback;
    return fallback;
  }
}
