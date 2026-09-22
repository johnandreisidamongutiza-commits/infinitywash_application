import 'loyalty_service.dart';

/// Legacy RFID Tag Service — DEPRECATED.
///
/// The old temporary `rfid_tags` table was removed during the RFID Loyalty Card
/// migration. This class is kept as a safe stub to avoid breaking any remaining
/// import sites. All functionality has moved to [LoyaltyService].
class RfidService {
  final LoyaltyService _loyaltyService = LoyaltyService();

  /// @deprecated Use [LoyaltyService.lookupCardByUid] instead.
  Future<List<String>> getAvailableRfidTags() async => [];

  /// @deprecated Temporary RFID tags no longer exist.
  Future<bool> isRfidTagAvailable(String tagCode) async => false;

  /// @deprecated Use [LoyaltyService.lookupCardByUid] instead.
  Future<Map<String, dynamic>?> getRfidTagAssignment(String tagCode) async {
    final card = await _loyaltyService.lookupCardByUid(tagCode);
    if (card == null) return null;
    return {
      'tag_code': card.uid,
      'customer_name': card.ownerName,
    };
  }

  /// @deprecated Temporary RFID tags no longer exist.
  Future<void> assignRfidTagToOrder(String orderId, String tagCode) async {
    // No-op: temporary RFID tag assignment removed in loyalty card migration.
  }

  /// @deprecated Temporary RFID tags no longer exist.
  Future<void> releaseRfidTag(String orderId) async {
    // No-op: temporary RFID tag assignment removed in loyalty card migration.
  }

  /// @deprecated Temporary RFID tags no longer exist.
  Future<String?> getRfidTagForOrder(String orderId) async => null;

  /// @deprecated Use [LoyaltyService] instead.
  Future<List<Map<String, dynamic>>> getAllRfidTags() async => [];

  /// @deprecated Temporary RFID tags no longer exist.
  Future<Map<String, dynamic>> getRfidUsageStats() async => {
        'total_tags': 0,
        'available_tags': 0,
        'in_use_tags': 0,
        'retired_tags': 0,
        'usage_percentage': 0,
      };

  /// @deprecated Temporary RFID tags no longer exist.
  Future<String> createRfidTag({
    required String tagCode,
    required String uid,
  }) async {
    throw UnsupportedError(
      'createRfidTag is no longer supported. '
      'Use LoyaltyService to register permanent loyalty cards instead.',
    );
  }
}