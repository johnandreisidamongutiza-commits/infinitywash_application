import '../models/supply.dart';
import '../models/order.dart';
import 'supabase_service.dart';

class MockDataService {
  static final MockDataService _instance = MockDataService._internal();
  factory MockDataService() => _instance;
  MockDataService._internal();

  // All available RFID tags in the shop
  final List<String> _allRfidTags = [
    'RFID-001', 'RFID-002', 'RFID-003', 'RFID-004', 'RFID-005',
    'RFID-006', 'RFID-007', 'RFID-008', 'RFID-009', 'RFID-010',
  ];
  
  final List<Supply> _supplies = [
    Supply(id: '1', name: 'Liquid Detergent', currentAmount: 8.5, maxAmount: 10.0, unit: 'L'),
    Supply(id: '2', name: 'Fabric Conditioner', currentAmount: 4.2, maxAmount: 5.0, unit: 'L'),
  ];

  // STUB: Empty lists for unmigrated features (rider, customer, service requests)
  // Walk-in orders use real Supabase data via OrderService
  final List<LaundryOrder> _stubOrders = [];
  final List<LaundryOrder> _stubRequests = [];

  List<Supply> get supplies => List.unmodifiable(_supplies);
  
  // STUB getters for unmigrated features
  List<LaundryOrder> get activeOrders => _stubOrders;
  List<LaundryOrder> get completedOrders => [];
  List<LaundryOrder> get pendingRequests => _stubRequests;
  
  // Rider route state (stub for unmigrated rider feature)
  bool isRiderRouteCompleted = false;

  /// Returns RFID tags not currently assigned to any active order (queries real database)
  List<String> get availableRfidTags {
    // This should return a Future, but to maintain backward compatibility with existing UI code,
    // we return all tags and let the UI handle validation
    return List.from(_allRfidTags);
  }

  /// Checks if an RFID tag is available (not assigned to active orders)
  Future<bool> isRfidAvailableAsync(String tag) async {
    try {
      if (!_allRfidTags.contains(tag)) {
        return false; // Tag doesn't exist in our system
      }

      // Query database for active orders using this RFID tag
      final response = await SupabaseService.client
          .from('orders')
          .select('rfid_tag')
          .eq('rfid_tag', tag)
          .inFilter('status', ['processing', 'ready', 'out_for_delivery'])
          .limit(1);

      // If we found any active orders with this RFID, it's not available
      return response.isEmpty;
    } catch (e) {
      print('❌ Error checking RFID availability: $e');
      // If there's an error, assume tag is available (fail-safe)
      return true;
    }
  }

  /// Get list of available RFID tags (async version that checks database)
  Future<List<String>> getAvailableRfidTags() async {
    try {
      // Get all RFID tags currently assigned to active orders
      final response = await SupabaseService.client
          .from('orders')
          .select('rfid_tag')
          .inFilter('status', ['processing', 'ready', 'out_for_delivery'])
          .not('rfid_tag', 'is', null);

      final assignedTags = response
          .map((row) => row['rfid_tag'] as String?)
          .where((tag) => tag != null)
          .cast<String>()
          .toSet();

      // Return tags that are not assigned
      return _allRfidTags.where((tag) => !assignedTags.contains(tag)).toList();
    } catch (e) {
      print('❌ Error fetching available RFID tags: $e');
      // If there's an error, return all tags (fail-safe)
      return List.from(_allRfidTags);
    }
  }

  bool isRfidAvailable(String tag) {
    // Synchronous version - kept for backward compatibility
    // This now only checks if the tag exists in our system
    // For real availability checking, use isRfidAvailableAsync
    return _allRfidTags.contains(tag);
  }

  // STUB methods for unmigrated features (to prevent compilation errors)
  // These do nothing - they're placeholders until those features are migrated
  
  void addRequest(LaundryOrder order) {
    // STUB: Does nothing. Online service requests not migrated yet.
  }

  void lockRequestForReview(String id, String staffName) {
    // STUB: Does nothing. Service request approval not migrated yet.
  }

  void unlockRequest(String id) {
    // STUB: Does nothing. Service request approval not migrated yet.
  }

  void approvePhotoRequest(String id, int estimatedLoads, String? message) {
    // STUB: Does nothing. Photo request approval not migrated yet.
  }

  void rejectRequest(String id, String reason, String message) {
    // STUB: Does nothing. Request rejection not migrated yet.
  }

  List<LaundryOrder> getRiderPickups() {
    // STUB: Returns empty list. Rider pickups not migrated yet.
    return [];
  }

  List<LaundryOrder> getRiderDeliveries() {
    // STUB: Returns empty list. Rider deliveries not migrated yet.
    return [];
  }

  void confirmPickupWithLoads(String orderId, List<OrderLoad> loads) {
    // STUB: Does nothing. Rider pickup confirmation not migrated yet.
  }

  void completeRiderRoute() {
    // STUB: Does nothing. Rider route completion not migrated yet.
    isRiderRouteCompleted = true;
  }

  void resetRiderRoute() {
    // STUB: Does nothing. Rider route reset not migrated yet.
    isRiderRouteCompleted = false;
  }

  List<LaundryOrder> getCustomerRequests(String customerPhone) {
    // STUB: Returns empty list. Customer orders not migrated yet.
    return [];
  }

  List<LaundryOrder> getCustomerActiveOrders(String customerPhone) {
    // STUB: Returns empty list. Customer orders not migrated yet.
    return [];
  }

  List<LaundryOrder> getCustomerHistory(String customerPhone) {
    // STUB: Returns empty list. Customer history not migrated yet.
    return [];
  }

  // Service request approval/decline methods
  void declineRequest(String requestId) {
    // STUB: Does nothing. Service request decline not migrated yet.
    print('📝 STUB: Declined service request $requestId');
  }

  void approveRequest(String requestId, List<OrderLoad> loads, String rfidTag) {
    // STUB: Does nothing. Service request approval not migrated yet.
    print('📝 STUB: Approved service request $requestId with ${loads.length} loads, RFID: $rfidTag');
  }
}
