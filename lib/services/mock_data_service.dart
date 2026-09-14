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
      loads: [
        OrderLoad(
          loadNumber: 1,
          category: 'Regular Clothing',
          weight: 5.5,
          categoryLimit: 8.0,
          unit: 'kg',
          description: 'T-shirts, shorts, sleeveless, socks, underwear',
          isOverLimit: false,
          loadStatus: LoadStatus.washing,
        ),
      ],
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
      loads: [
        OrderLoad(
          loadNumber: 1,
          category: 'Regular Clothing',
          weight: 3.0,
          categoryLimit: 8.0,
          unit: 'kg',
          description: 'T-shirts, shorts, sleeveless, socks, underwear',
          isOverLimit: false,
          loadStatus: LoadStatus.drying,
        ),
      ],
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
      loads: [
        OrderLoad(
          loadNumber: 1,
          category: 'Regular Clothing',
          weight: 7.5,
          categoryLimit: 8.0,
          unit: 'kg',
          description: 'T-shirts, shorts, sleeveless, socks, underwear',
          isOverLimit: false,
          loadStatus: LoadStatus.folded,
        ),
        OrderLoad(
          loadNumber: 2,
          category: 'Heavy Clothing',
          weight: 4.5,
          categoryLimit: 6.0,
          unit: 'kg',
          description: 'Jeans, cargo, jackets, sweaters, corduroy',
          isOverLimit: false,
          loadStatus: LoadStatus.folded,
        ),
      ],
      rfidTag: 'RFID-005',
      instructions: 'Separate whites, delicate wash',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    // Test order: Photo request pending pickup (TBD loads)
    LaundryOrder(
      id: 'IW-999',
      customerName: 'Test Customer (Photo Request)',
      customerPhone: '0915-123-4567',
      deliveryAddress: '789 IT Park, Cebu City',
      deliveryLandmark: 'Near Starbucks',
      channel: OrderChannel.online,
      collectionMethod: CollectionMethod.riderPickup,
      returnMethod: ReturnMethod.delivery,
      status: OrderStatus.pending_pickup,
      paymentStatus: PaymentStatus.unpaid,
      loads: [], // Empty - TBD at pickup
      instructions: null,
      rfidTag: null,
      createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
      laundryPhotoUrls: ['assets/images/laundry1.jpg', 'assets/images/laundry2.jpg'],
      customerDescription: 'Please separate whites from colors. Handle with care.',
    ),
    // Test order: Walk-in pickup with known loads
    LaundryOrder(
      id: 'IW-998',
      customerName: 'Alice Green',
      customerPhone: '0917-888-5555',
      deliveryAddress: '321 Escario St, Cebu City',
      deliveryLandmark: 'Blue building near church',
      channel: OrderChannel.walkIn,
      collectionMethod: CollectionMethod.riderPickup,
      returnMethod: ReturnMethod.delivery,
      status: OrderStatus.pending_pickup,
      paymentStatus: PaymentStatus.unpaid,
      loads: [
        OrderLoad(
          loadNumber: 1,
          category: 'Regular Clothing',
          weight: 7.0,
          categoryLimit: 8.0,
          unit: 'kg',
          description: 'Mixed clothing',
          isOverLimit: false,
        ),
        OrderLoad(
          loadNumber: 2,
          category: 'Regular Clothing',
          weight: 6.5,
          categoryLimit: 8.0,
          unit: 'kg',
          description: 'Mixed clothing',
          isOverLimit: false,
        ),
      ],
      rfidTag: 'RFID-007',
      instructions: 'Customer called to request pickup',
      createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
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

  void approveRequest(String id, List<OrderLoad> loads, String rfidTag) {
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
        loads: loads,
        rfidTag: rfidTag,
        instructions: request.instructions,
        createdAt: DateTime.now(),
      ));
    }
  }

  void declineRequest(String id) {
    _pendingRequests.removeWhere((o) => o.id == id);
  }
  
  void lockRequestForReview(String id, String staffName) {
    final index = _pendingRequests.indexWhere((o) => o.id == id);
    if (index != -1) {
      final request = _pendingRequests[index];
      _pendingRequests[index] = LaundryOrder(
        id: request.id,
        customerName: request.customerName,
        customerPhone: request.customerPhone,
        deliveryAddress: request.deliveryAddress,
        deliveryLandmark: request.deliveryLandmark,
        channel: request.channel,
        collectionMethod: request.collectionMethod,
        returnMethod: request.returnMethod,
        status: request.status,
        paymentStatus: request.paymentStatus,
        loads: request.loads,
        instructions: request.instructions,
        rfidTag: request.rfidTag,
        createdAt: request.createdAt,
        paymentMethod: request.paymentMethod,
        paidAt: request.paidAt,
        laundryPhotoUrls: request.laundryPhotoUrls,
        customerDescription: request.customerDescription,
        estimatedLoads: request.estimatedLoads,
        rejectionReason: request.rejectionReason,
        staffMessage: request.staffMessage,
        reviewedAt: request.reviewedAt,
        reviewedBy: request.reviewedBy,
        expiresAt: request.expiresAt,
        underReviewBy: staffName, // Lock it
      );
    }
  }
  
  void unlockRequest(String id) {
    final index = _pendingRequests.indexWhere((o) => o.id == id);
    if (index != -1) {
      final request = _pendingRequests[index];
      _pendingRequests[index] = LaundryOrder(
        id: request.id,
        customerName: request.customerName,
        customerPhone: request.customerPhone,
        deliveryAddress: request.deliveryAddress,
        deliveryLandmark: request.deliveryLandmark,
        channel: request.channel,
        collectionMethod: request.collectionMethod,
        returnMethod: request.returnMethod,
        status: request.status,
        paymentStatus: request.paymentStatus,
        loads: request.loads,
        instructions: request.instructions,
        rfidTag: request.rfidTag,
        createdAt: request.createdAt,
        paymentMethod: request.paymentMethod,
        paidAt: request.paidAt,
        laundryPhotoUrls: request.laundryPhotoUrls,
        customerDescription: request.customerDescription,
        estimatedLoads: request.estimatedLoads,
        rejectionReason: request.rejectionReason,
        staffMessage: request.staffMessage,
        reviewedAt: request.reviewedAt,
        reviewedBy: request.reviewedBy,
        expiresAt: request.expiresAt,
        underReviewBy: null, // Unlock it
      );
    }
  }
  
  void approvePhotoRequest(String id, int estimatedLoads, String? message) {
    final index = _pendingRequests.indexWhere((o) => o.id == id);
    if (index != -1) {
      final request = _pendingRequests.removeAt(index);
      // Move to orders list with pending_pickup status
      _orders.add(LaundryOrder(
        id: request.id,
        customerName: request.customerName,
        customerPhone: request.customerPhone,
        deliveryAddress: request.deliveryAddress,
        deliveryLandmark: request.deliveryLandmark,
        channel: request.channel,
        collectionMethod: request.collectionMethod,
        returnMethod: request.returnMethod,
        status: OrderStatus.pending_pickup, // Changed status
        paymentStatus: request.paymentStatus,
        loads: request.loads,
        instructions: request.instructions,
        rfidTag: request.rfidTag,
        createdAt: request.createdAt,
        paymentMethod: request.paymentMethod,
        paidAt: request.paidAt,
        laundryPhotoUrls: request.laundryPhotoUrls,
        customerDescription: request.customerDescription,
        estimatedLoads: estimatedLoads,
        rejectionReason: null,
        staffMessage: message,
        reviewedAt: DateTime.now(),
        reviewedBy: 'Staff User', // TODO: Get from auth
        expiresAt: request.expiresAt,
        underReviewBy: null,
      ));
    }
  }
  
  void rejectRequest(String id, String reason, String message) {
    final index = _pendingRequests.indexWhere((o) => o.id == id);
    if (index != -1) {
      final request = _pendingRequests.removeAt(index);
      // Move to orders list with rejected status
      _orders.add(LaundryOrder(
        id: request.id,
        customerName: request.customerName,
        customerPhone: request.customerPhone,
        deliveryAddress: request.deliveryAddress,
        deliveryLandmark: request.deliveryLandmark,
        channel: request.channel,
        collectionMethod: request.collectionMethod,
        returnMethod: request.returnMethod,
        status: OrderStatus.rejected, // Rejected status
        paymentStatus: request.paymentStatus,
        loads: request.loads,
        instructions: request.instructions,
        rfidTag: request.rfidTag,
        createdAt: request.createdAt,
        paymentMethod: request.paymentMethod,
        paidAt: request.paidAt,
        laundryPhotoUrls: request.laundryPhotoUrls,
        customerDescription: request.customerDescription,
        estimatedLoads: request.estimatedLoads,
        rejectionReason: reason,
        staffMessage: message,
        reviewedAt: DateTime.now(),
        reviewedBy: 'Staff User', // TODO: Get from auth
        expiresAt: request.expiresAt,
        underReviewBy: null,
      ));
    }
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
        useSupplies(old.totalWeight);
      }

      _orders[index] = LaundryOrder(
        id: old.id,
        customerName: old.customerName,
        channel: old.channel,
        collectionMethod: old.collectionMethod,
        returnMethod: old.returnMethod,
        status: newStatus,
        paymentStatus: old.paymentStatus,
        loads: old.loads,
        rfidTag: old.rfidTag,
        instructions: old.instructions,
        createdAt: old.createdAt,
      );
    }
  }

  void updateLoadStatus(String orderId, int loadNumber, LoadStatus newStatus) {
    int index = _orders.indexWhere((o) => o.id == orderId);
    if (index != -1) {
      final old = _orders[index];
      final updatedLoads = old.loads.map((load) {
        if (load.loadNumber == loadNumber) {
          return load.copyWith(loadStatus: newStatus);
        }
        return load;
      }).toList();

      // Update order status based on all loads
      OrderStatus orderStatus = old.status;
      final allFolded = updatedLoads.every((load) => load.loadStatus == LoadStatus.folded);
      if (allFolded && old.status == OrderStatus.processing) {
        orderStatus = OrderStatus.ready;
      }

      _orders[index] = LaundryOrder(
        id: old.id,
        customerName: old.customerName,
        customerPhone: old.customerPhone,
        deliveryAddress: old.deliveryAddress,
        deliveryLandmark: old.deliveryLandmark,
        channel: old.channel,
        collectionMethod: old.collectionMethod,
        returnMethod: old.returnMethod,
        status: orderStatus,
        paymentStatus: old.paymentStatus,
        loads: updatedLoads,
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

  // Rider Pickup Methods
  List<LaundryOrder> getRiderPickups() {
    return _orders.where((o) => 
      o.status == OrderStatus.pending_pickup &&
      o.collectionMethod == CollectionMethod.riderPickup
    ).toList();
  }

  List<LaundryOrder> getRiderDeliveries() {
    return _orders.where((o) => 
      (o.status == OrderStatus.ready || o.status == OrderStatus.out_for_delivery) &&
      o.returnMethod == ReturnMethod.delivery
    ).toList();
  }

  void confirmPickupWithLoads(String orderId, List<OrderLoad> loads) {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index != -1) {
      final old = _orders[index];
      _orders[index] = LaundryOrder(
        id: old.id,
        customerName: old.customerName,
        customerPhone: old.customerPhone,
        deliveryAddress: old.deliveryAddress,
        deliveryLandmark: old.deliveryLandmark,
        channel: old.channel,
        collectionMethod: old.collectionMethod,
        returnMethod: old.returnMethod,
        status: OrderStatus.processing, // Move to processing after pickup
        paymentStatus: old.paymentStatus,
        loads: loads, // Update with scanned loads
        rfidTag: old.rfidTag,
        instructions: old.instructions,
        createdAt: old.createdAt,
        paymentMethod: old.paymentMethod,
        paidAt: old.paidAt,
        laundryPhotoUrls: old.laundryPhotoUrls,
        customerDescription: old.customerDescription,
        estimatedLoads: old.estimatedLoads,
        rejectionReason: old.rejectionReason,
        staffMessage: old.staffMessage,
        reviewedAt: old.reviewedAt,
        reviewedBy: old.reviewedBy,
        expiresAt: old.expiresAt,
        underReviewBy: old.underReviewBy,
      );
    }
  }

  bool isRfidAvailable(String tag) {
    // Check if tag is not already assigned to an active order
    return !_orders.any((o) => 
      o.rfidTag == tag && 
      o.status != OrderStatus.completed
    );
  }
}
