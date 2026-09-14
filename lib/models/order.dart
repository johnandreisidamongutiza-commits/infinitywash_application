enum OrderStatus { pending_approval, rejected, pending_pickup, processing, ready, out_for_delivery, completed }
enum CollectionMethod { dropOff, riderPickup }
enum ReturnMethod { shopPickup, delivery }
enum OrderChannel { walkIn, online }
enum PaymentStatus { paid, unpaid }
enum LoadStatus { queued, washing, drying, folded }

class OrderLoad {
  final int loadNumber;
  final String category;
  final double weight;
  final double categoryLimit;
  final String unit;
  final String description;
  final bool isOverLimit;
  final LoadStatus loadStatus;
  final String? notes;

  OrderLoad({
    required this.loadNumber,
    required this.category,
    required this.weight,
    required this.categoryLimit,
    required this.unit,
    required this.description,
    required this.isOverLimit,
    this.loadStatus = LoadStatus.queued,
    this.notes,
  });

  String get statusText {
    switch (loadStatus) {
      case LoadStatus.queued: return 'Queued';
      case LoadStatus.washing: return 'Washing';
      case LoadStatus.drying: return 'Drying';
      case LoadStatus.folded: return 'Folded & Ready';
    }
  }

  String get statusIcon {
    switch (loadStatus) {
      case LoadStatus.queued: return '⏸️';
      case LoadStatus.washing: return '🔄';
      case LoadStatus.drying: return '⏳';
      case LoadStatus.folded: return '✓';
    }
  }

  OrderLoad copyWith({
    int? loadNumber,
    String? category,
    double? weight,
    double? categoryLimit,
    String? unit,
    String? description,
    bool? isOverLimit,
    LoadStatus? loadStatus,
    String? notes,
  }) {
    return OrderLoad(
      loadNumber: loadNumber ?? this.loadNumber,
      category: category ?? this.category,
      weight: weight ?? this.weight,
      categoryLimit: categoryLimit ?? this.categoryLimit,
      unit: unit ?? this.unit,
      description: description ?? this.description,
      isOverLimit: isOverLimit ?? this.isOverLimit,
      loadStatus: loadStatus ?? this.loadStatus,
      notes: notes ?? this.notes,
    );
  }
}

class LaundryOrder {
  final String id;
  final String customerName;
  final String? customerPhone;
  final String? deliveryAddress;
  final String? deliveryLandmark;
  final OrderChannel channel;
  final CollectionMethod collectionMethod;
  final ReturnMethod returnMethod;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final List<OrderLoad> loads;
  final String? instructions;
  final String? rfidTag;
  final DateTime createdAt;
  final String? paymentMethod; // 'Cash', 'GCash', null
  final DateTime? paidAt; // When payment was received
  
  // Photo request fields
  final List<String>? laundryPhotoUrls; // URLs/paths to uploaded images
  final String? customerDescription; // Customer's text description of laundry
  final int? estimatedLoads; // Staff's estimate from photos (2, 3, 4, 5+)
  final String? rejectionReason; // Why request was rejected
  final String? staffMessage; // Message from staff to customer
  final DateTime? reviewedAt; // When staff approved/rejected
  final String? reviewedBy; // Which staff member reviewed
  final DateTime? expiresAt; // Auto-reject after 24 hours if not reviewed
  final String? underReviewBy; // Staff member currently reviewing (lock)

  LaundryOrder({
    required this.id,
    required this.customerName,
    this.customerPhone,
    this.deliveryAddress,
    this.deliveryLandmark,
    required this.channel,
    this.collectionMethod = CollectionMethod.dropOff,
    this.returnMethod = ReturnMethod.shopPickup,
    required this.status,
    required this.paymentStatus,
    required this.loads,
    this.instructions,
    this.rfidTag,
    required this.createdAt,
    this.paymentMethod,
    this.paidAt,
    this.laundryPhotoUrls,
    this.customerDescription,
    this.estimatedLoads,
    this.rejectionReason,
    this.staffMessage,
    this.reviewedAt,
    this.reviewedBy,
    this.expiresAt,
    this.underReviewBy,
  });

  // Computed properties
  double get totalWeight => loads.fold(0.0, (sum, load) => sum + load.weight);
  
  int get totalLoads => loads.length;
  
  double get basePrice => 170.0 * totalLoads;
  
  bool get allLoadsReady => loads.every((load) => load.loadStatus == LoadStatus.folded);
  
  bool get hasMultipleLoads => loads.length > 1;
  
  String get weightDisplay {
    // Check if there are any piece-based loads (heavyweight beddings)
    final kgLoads = loads.where((l) => l.unit == 'kg');
    final pcLoads = loads.where((l) => l.unit == 'pc');
    
    if (pcLoads.isEmpty) {
      return '${totalWeight.toStringAsFixed(1)}kg';
    } else if (kgLoads.isEmpty) {
      return '${totalWeight.toStringAsFixed(0)}pc';
    } else {
      final kgTotal = kgLoads.fold(0.0, (sum, l) => sum + l.weight);
      final pcTotal = pcLoads.fold(0.0, (sum, l) => sum + l.weight);
      return '${kgTotal.toStringAsFixed(1)}kg + ${pcTotal.toStringAsFixed(0)}pc';
    }
  }

  String get statusText {
    switch (status) {
      case OrderStatus.pending_approval: return 'Pending Approval';
      case OrderStatus.rejected: return 'Rejected';
      case OrderStatus.pending_pickup: return 'Waiting for Rider';
      case OrderStatus.processing: return 'Processing';
      case OrderStatus.ready: return 'Ready for Pickup';
      case OrderStatus.out_for_delivery: return 'Out for Delivery';
      case OrderStatus.completed: return 'Completed';
    }
  }

  String get collectionText {
    switch (collectionMethod) {
      case CollectionMethod.dropOff: return 'Drop-off';
      case CollectionMethod.riderPickup: return 'Rider Pickup';
    }
  }

  String get returnText {
    switch (returnMethod) {
      case ReturnMethod.shopPickup: return 'Shop Pickup';
      case ReturnMethod.delivery: return 'Delivery';
    }
  }
}
