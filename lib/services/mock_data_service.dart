import '../models/order.dart';
import '../models/supply.dart';

class MockDataService {
  static final MockDataService _instance = MockDataService._internal();
  factory MockDataService() => _instance;
  MockDataService._internal();

  // All available RFID tags in the shop
  final List<String> _allRfidTags = [
    'RFID-001', 'RFID-002', 'RFID-003', 'RFID-004', 'RFID-005',
    'RFID-006', 'RFID-007', 'RFID-008', 'RFID-009', 'RFID-010',
  ];

  final List<LaundryOrder> _orders = [
    LaundryOrder(
      id: 'IW-001',
      customerName: 'John Doe',
      customerPhone: '0912-345-6789',
      channel: OrderChannel.walkIn,
      collectionMethod: CollectionMethod.dropOff,
      returnMethod: ReturnMethod.shopPickup,
      status: OrderStatus.processing,
      paymentStatus: PaymentStatus.unpaid,
      weight: 5.5,
      rfidTag: 'RFID-001',
      instructions: 'Heavy wash for denim | Fold neatly',
      createdAt: DateTime.now().subtract(const Duration(minutes: 45)),
    ),
    LaundryOrder(
      id: 'IW-002',
      customerName: 'Maria Santos',
      customerPhone: '0922-555-0192',
      deliveryAddress: '456 Banilad Rd, Cebu City',
      deliveryLandmark: 'Beside green pharmacy',
      channel: OrderChannel.online,
      collectionMethod: CollectionMethod.riderPickup,
      returnMethod: ReturnMethod.delivery,
      status: OrderStatus.processing,
      paymentStatus: PaymentStatus.unpaid,
      weight: 3.0,
      rfidTag: 'RFID-003',
      instructions: 'Extra gentle cycle on shirts | Extra Fab Con (+₱20)',
      createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
    ),
    LaundryOrder(
      id: 'IW-003',
      customerName: 'Carlos Reyes',
      customerPhone: '0918-999-4321',
      deliveryAddress: '123 Mango Ave, Brgy. Guadalupe, Cebu City',
      deliveryLandmark: 'Near yellow gate across 7-Eleven',
      channel: OrderChannel.walkIn,
      collectionMethod: CollectionMethod.dropOff,
      returnMethod: ReturnMethod.delivery,
      status: OrderStatus.ready,
      paymentStatus: PaymentStatus.paid,
      weight: 4.0,
      rfidTag: 'RFID-005',
      instructions: 'Separate whites, delicate wash',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
  ];

  final List<LaundryOrder> _pendingRequests = [];
  
  final List<Supply> _supplies = [
    Supply(id: '1', name: 'Liquid Detergent', currentAmount: 8.5, maxAmount: 10.0, unit: 'L'),
    Supply(id: '2', name: 'Fabric Conditioner', currentAmount: 4.2, maxAmount: 5.0, unit: 'L'),
  ];

  List<LaundryOrder> get activeOrders => _orders.where((o) => o.status != OrderStatus.completed).toList();
  List<LaundryOrder> get processingOrders => _orders.where((o) => o.status == OrderStatus.processing).toList();
  List<LaundryOrder> get readyOrders => _orders.where((o) => o.status == OrderStatus.ready).toList();
  List<LaundryOrder> get completedOrders => _orders.where((o) => o.status == OrderStatus.completed).toList();
  List<LaundryOrder> get pendingRequests => List.unmodifiable(_pendingRequests);
  List<Supply> get supplies => List.unmodifiable(_supplies);

  /// Returns RFID tags not currently assigned to any active order
  List<String> get availableRfidTags {
    final usedTags = _orders
        .where((o) => o.status != OrderStatus.completed && o.rfidTag != null)
        .map((o) => o.rfidTag!)
        .toSet();
    return _allRfidTags.where((tag) => !usedTags.contains(tag)).toList();
  }

  void addRequest(LaundryOrder order) {
    _pendingRequests.add(order);
  }

  void approveRequest(String id, double weight, String rfidTag) {
    int index = _pendingRequests.indexWhere((o) => o.id == id);
    if (index != -1) {
      final request = _pendingRequests.removeAt(index);
      
      final needsRiderPickup = request.collectionMethod == CollectionMethod.riderPickup;
      
      _orders.add(LaundryOrder(
        id: request.id,
        customerName: request.customerName,
        channel: request.channel,
        collectionMethod: request.collectionMethod,
        returnMethod: request.returnMethod,
        status: needsRiderPickup ? OrderStatus.pending_pickup : OrderStatus.processing,
        paymentStatus: request.paymentStatus,
        weight: weight,
        rfidTag: rfidTag,
        instructions: request.instructions,
        createdAt: DateTime.now(),
      ));
    }
  }

  void declineRequest(String id) {
    _pendingRequests.removeWhere((o) => o.id == id);
  }

  void addOrder(LaundryOrder order) {
    _orders.add(order);
  }

  void useSupplies(double amount) {
    for (int i = 0; i < _supplies.length; i++) {
      final s = _supplies[i];
      _supplies[i] = Supply(
        id: s.id,
        name: s.name,
        currentAmount: (s.currentAmount - (amount * 0.1)).clamp(0, s.maxAmount),
        maxAmount: s.maxAmount,
        unit: s.unit,
      );
    }
  }

  void updateOrderStatus(String id, OrderStatus newStatus) {
    int index = _orders.indexWhere((o) => o.id == id);
    if (index != -1) {
      final old = _orders[index];
      
      if (newStatus == OrderStatus.processing && old.status != OrderStatus.processing) {
        useSupplies(old.weight);
      }

      _orders[index] = LaundryOrder(
        id: old.id,
        customerName: old.customerName,
        channel: old.channel,
        collectionMethod: old.collectionMethod,
        returnMethod: old.returnMethod,
        status: newStatus,
        paymentStatus: old.paymentStatus,
        weight: old.weight,
        rfidTag: old.rfidTag,
        instructions: old.instructions,
        createdAt: old.createdAt,
      );
    }
  }

  // Rider Route State Tracking
  bool isRiderRouteCompleted = false;

  void completeRiderRoute() {
    isRiderRouteCompleted = true;
  }

  void resetRiderRoute() {
    isRiderRouteCompleted = false;
  }
}
