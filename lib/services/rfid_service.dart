import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class RfidService {
  final SupabaseClient _client = SupabaseService.client;

  /// Get all RFID tags that are available (not assigned to any active order)
  Future<List<String>> getAvailableRfidTags() async {
    try {
      // Query rfid_tags table for available tags
      final response = await _client
          .from('rfid_tags')
          .select('tag_code')
          .eq('status', 'available')
          .filter('active_order_id', 'is', null)
          .order('tag_code');

      final availableTags = response
          .map((row) => row['tag_code'] as String)
          .toList();

      print('🏷️ Available RFID tags: ${availableTags.length}');
      print('   Tags: $availableTags');

      return availableTags;
    } catch (e) {
      print('❌ Error fetching available RFID tags: $e');
      // Return empty list on error
      return [];
    }
  }

  /// Check if a specific RFID tag is available (not assigned to active orders)
  Future<bool> isRfidTagAvailable(String tagCode) async {
    try {
      // Check if tag exists and is available
      final response = await _client
          .from('rfid_tags')
          .select('id, status, active_order_id')
          .eq('tag_code', tagCode)
          .maybeSingle();

      if (response == null) {
        print('⚠️ RFID tag $tagCode does not exist in the system');
        return false;
      }

      final isAvailable = response['status'] == 'available' && 
                         response['active_order_id'] == null;

      if (!isAvailable) {
        print('⚠️ RFID tag $tagCode is not available (status: ${response['status']}, active_order: ${response['active_order_id']})');
      }

      return isAvailable;
    } catch (e) {
      print('❌ Error checking RFID tag availability: $e');
      // Return false on error (fail-safe)
      return false;
    }
  }

  /// Get RFID tag assignment details (which order it's assigned to)
  Future<Map<String, dynamic>?> getRfidTagAssignment(String tagCode) async {
    try {
      final response = await _client
          .from('rfid_tags')
          .select('''
            *,
            orders!inner(
              id, order_number, status, created_at,
              customers!inner(first_name, last_name, customer_code)
            )
          ''')
          .eq('tag_code', tagCode)
          .eq('status', 'in_use')
          .filter('active_order_id', 'neq', null)
          .maybeSingle();

      if (response == null) {
        return null; // Tag is not assigned
      }

      final order = response['orders'] as Map<String, dynamic>;
      final customer = order['customers'] as Map<String, dynamic>;
      
      return {
        'tag_id': response['id'],
        'tag_code': response['tag_code'],
        'order_id': order['id'],
        'order_number': order['order_number'],
        'order_status': order['status'],
        'created_at': order['created_at'],
        'customer_name': '${customer['first_name']} ${customer['last_name']}'.trim(),
        'customer_code': customer['customer_code'],
        'assigned_at': response['last_scanned_at'],
      };
    } catch (e) {
      print('❌ Error getting RFID tag assignment: $e');
      return null;
    }
  }

  /// Assign RFID tag to an order
  Future<void> assignRfidTagToOrder(String orderId, String tagCode) async {
    try {
      // Double-check availability before assigning
      final isAvailable = await isRfidTagAvailable(tagCode);
      if (!isAvailable) {
        throw Exception('RFID tag $tagCode is not available for assignment');
      }

      // Update the RFID tag to assign it to the order
      await _client
          .from('rfid_tags')
          .update({
            'active_order_id': orderId,
            'status': 'in_use',
            'last_scanned_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('tag_code', tagCode);

      print('✅ RFID tag $tagCode assigned to order $orderId');
    } catch (e) {
      print('❌ Error assigning RFID tag: $e');
      rethrow;
    }
  }

  /// Release RFID tag when order is completed/cancelled
  Future<void> releaseRfidTag(String orderId) async {
    try {
      // Find and release any RFID tags assigned to this order
      await _client
          .from('rfid_tags')
          .update({
            'active_order_id': null,
            'status': 'available',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('active_order_id', orderId);

      print('✅ RFID tag(s) released from order $orderId');
    } catch (e) {
      print('❌ Error releasing RFID tag: $e');
      rethrow;
    }
  }

  /// Get RFID tag by order ID
  Future<String?> getRfidTagForOrder(String orderId) async {
    try {
      final response = await _client
          .from('rfid_tags')
          .select('tag_code')
          .eq('active_order_id', orderId)
          .eq('status', 'in_use')
          .maybeSingle();

      return response?['tag_code'] as String?;
    } catch (e) {
      print('❌ Error getting RFID tag for order: $e');
      return null;
    }
  }

  /// Get all RFID tags in the system with their status
  Future<List<Map<String, dynamic>>> getAllRfidTags() async {
    try {
      final response = await _client
          .from('rfid_tags')
          .select('''
            *,
            orders(order_number, status, created_at)
          ''')
          .order('tag_code');

      return response.cast<Map<String, dynamic>>();
    } catch (e) {
      print('❌ Error getting all RFID tags: $e');
      return [];
    }
  }

  /// Get RFID usage statistics
  Future<Map<String, dynamic>> getRfidUsageStats() async {
    try {
      final response = await _client
          .from('rfid_tags')
          .select('status');

      final stats = <String, int>{
        'available': 0,
        'in_use': 0,
        'retired': 0,
      };

      for (var tag in response) {
        final status = tag['status'] as String;
        stats[status] = (stats[status] ?? 0) + 1;
      }

      final totalTags = response.length;
      final inUseCount = stats['in_use'] ?? 0;

      return {
        'total_tags': totalTags,
        'available_tags': stats['available'] ?? 0,
        'in_use_tags': inUseCount,
        'retired_tags': stats['retired'] ?? 0,
        'usage_percentage': totalTags > 0 ? (inUseCount / totalTags * 100).toInt() : 0,
      };
    } catch (e) {
      print('❌ Error getting RFID usage stats: $e');
      return {
        'total_tags': 0,
        'available_tags': 0,
        'in_use_tags': 0,
        'retired_tags': 0,
        'usage_percentage': 0,
      };
    }
  }

  /// Create a new RFID tag in the system
  Future<String> createRfidTag({
    required String tagCode,
    required String uid,
  }) async {
    try {
      final response = await _client
          .from('rfid_tags')
          .insert({
            'tag_code': tagCode,
            'uid': uid,
            'status': 'available',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();

      final tagId = response['id'] as String;
      print('✅ Created RFID tag: $tagCode ($tagId)');
      return tagId;
    } catch (e) {
      print('❌ Error creating RFID tag: $e');
      rethrow;
    }
  }
}