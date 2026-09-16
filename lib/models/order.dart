
enum OrderStatus { pending_approval, rejected, cancelled, pending_pickup, processing, ready, out_for_delivery, completed }
enum CollectionMethod { dropOff, riderPickup }
enum ReturnMethod { shopPickup, delivery }
enum OrderChannel { walkIn, online }
enum PaymentStatus { paid, unpaid }

// DEPRECATED: Load-level status tracking removed. Use order-level status only.
// Kept for backward compatibility with unmigrated screens.
@Deprecated('Load status tracking removed. Use order-level status instead.')
enum LoadStatus { queued, washing, drying, folded }

class OrderLoad {
  final int loadNumber;
  final String category;
  final double weight;
  final double categoryLimit;
  final String unit;
  final String description;
  final bool isOverLimit;
  final String? notes;
  
  // DEPRECATED: Load status tracking removed. Always returns null.
  // Kept for backward compatibility with unmigrated screens.
  @Deprecated('Load status tracking removed. Use order-level status instead.')
  LoadStatus? get loadStatus => null;
  
  @Deprecated('Load status tracking removed. Returns default icon.')
  String get statusIcon => '📥'; // Inbox emoji
  
  @Deprecated('Load status tracking removed. Returns default text.')
  String get statusText => 'Queued';

  OrderLoad({
    required this.loadNumber,
    required this.category,
    required this.weight,
    required this.categoryLimit,
    required this.unit,
    required this.description,
    required this.isOverLimit,
    this.notes,
    @Deprecated('Load status parameter ignored') LoadStatus? loadStatus, // Ignored parameter for compatibility
  });

  OrderLoad copyWith({
    int? loadNumber,
    String? category,
    double? weight,
    double? categoryLimit,
    String? unit,
    String? description,
    bool? isOverLimit,
    String? notes,
    @Deprecated('Load status parameter ignored') LoadStatus? loadStatus, // Ignored parameter for compatibility
  }) {
    return OrderLoad(
      loadNumber: loadNumber ?? this.loadNumber,
      category: category ?? this.category,
      weight: weight ?? this.weight,
      categoryLimit: categoryLimit ?? this.categoryLimit,
      unit: unit ?? this.unit,
      description: description ?? this.description,
      isOverLimit: isOverLimit ?? this.isOverLimit,
      notes: notes ?? this.notes,
    );
  }

  // Convert to JSON for Supabase (database column names in snake_case)
  Map<String, dynamic> toJson() {
    return {
      'load_number': loadNumber,
      'laundry_type': category,
      'weight': weight,
      'unit': unit,
      'description': description,
      'notes': notes,
    };
  }

  // Create from JSON (database response)
  factory OrderLoad.fromJson(Map<String, dynamic> json) {
    return OrderLoad(
      loadNumber: json['load_number'] as int,
      category: json['laundry_type'] as String,
      weight: (json['weight'] as num).toDouble(),
      categoryLimit: 0.0, // Not stored in database, set based on category
      unit: json['unit'] as String? ?? 'kg',
      description: json['description'] as String? ?? '',
      isOverLimit: false, // Computed field, not from database
      notes: json['notes'] as String?,
    );
  }
}

class LaundryOrder {
  final String id;
  final String? orderNumber; // Human-readable order number (ORD-YYYYMMDD-00001)
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
    this.orderNumber,
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
  
  bool get allLoadsReady => true; // Order-level status only, no per-load status
  
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

  // Convert to JSON for Supabase (database column names in snake_case)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_number': orderNumber ?? id, // Use orderNumber if available, fallback to id
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'delivery_address': deliveryAddress,
      'delivery_landmark': deliveryLandmark,
      'source': channel == OrderChannel.walkIn ? 'walk_in' : 'online',
      'pickup_requested': collectionMethod == CollectionMethod.riderPickup,
      'delivery_requested': returnMethod == ReturnMethod.delivery,
      'status': _orderStatusToString(status),
      'payment_status': paymentStatus == PaymentStatus.paid ? 'paid' : 'pending',
      'customer_notes': instructions,
      'rfid_tag': rfidTag,
      'created_at': createdAt.toIso8601String(),
      'payment_method': paymentMethod,
      'paid_at': paidAt?.toIso8601String(),
      // Photo request fields
      'laundry_photo_urls': laundryPhotoUrls,
      'customer_description': customerDescription,
      'estimated_loads': estimatedLoads,
      'rejection_reason': rejectionReason,
      'staff_message': staffMessage,
      'reviewed_at': reviewedAt?.toIso8601String(),
      'reviewed_by': reviewedBy,
      'expires_at': expiresAt?.toIso8601String(),
      'under_review_by': underReviewBy,
    };
  }

  // Create from JSON (database response)
  factory LaundryOrder.fromJson(Map<String, dynamic> json) {
    return LaundryOrder(
      id: json['id'] as String,
      orderNumber: json['order_number'] as String?, // Get order number from database
      customerName: json['customer_name'] as String? ?? 'Unknown',
      customerPhone: json['customer_phone'] as String?,
      deliveryAddress: json['delivery_address'] as String?,
      deliveryLandmark: json['delivery_landmark'] as String?,
      channel: (json['source'] as String?) == 'walk_in' ? OrderChannel.walkIn : OrderChannel.online,
      collectionMethod: (json['pickup_requested'] as bool?) == true 
          ? CollectionMethod.riderPickup 
          : CollectionMethod.dropOff,
      returnMethod: (json['delivery_requested'] as bool?) == true 
          ? ReturnMethod.delivery 
          : ReturnMethod.shopPickup,
      status: _orderStatusFromString(json['status'] as String? ?? 'processing'),
      paymentStatus: (json['payment_status'] as String?) == 'paid' 
          ? PaymentStatus.paid 
          : PaymentStatus.unpaid,
      loads: [], // Loads loaded separately via join
      instructions: json['customer_notes'] as String?,
      rfidTag: json['rfid_tag'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      paymentMethod: json['payment_method'] as String?,
      paidAt: json['paid_at'] != null ? DateTime.parse(json['paid_at'] as String) : null,
      laundryPhotoUrls: (json['laundry_photo_urls'] as List?)?.cast<String>(),
      customerDescription: json['customer_description'] as String?,
      estimatedLoads: json['estimated_loads'] as int?,
      rejectionReason: json['rejection_reason'] as String?,
      staffMessage: json['staff_message'] as String?,
      reviewedAt: json['reviewed_at'] != null ? DateTime.parse(json['reviewed_at'] as String) : null,
      reviewedBy: json['reviewed_by'] as String?,
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at'] as String) : null,
      underReviewBy: json['under_review_by'] as String?,
    );
  }

  // Helper method to convert OrderStatus enum to string for database
  static String _orderStatusToString(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_approval: return 'pending_approval';
      case OrderStatus.rejected: return 'rejected';
      case OrderStatus.pending_pickup: return 'pending_pickup';
      case OrderStatus.processing: return 'processing';
      case OrderStatus.ready: return 'ready';
      case OrderStatus.out_for_delivery: return 'out_for_delivery';
      case OrderStatus.completed: return 'completed';
    }
  }

  // Helper method to convert string from database to OrderStatus enum
  static OrderStatus _orderStatusFromString(String status) {
    switch (status) {
      case 'pending_approval': return OrderStatus.pending_approval;
      case 'rejected': return OrderStatus.rejected;
      case 'pending_pickup': return OrderStatus.pending_pickup;
      case 'processing': return OrderStatus.processing;
      case 'ready': return OrderStatus.ready;
      case 'out_for_delivery': return OrderStatus.out_for_delivery;
      case 'completed': return OrderStatus.completed;
      default: return OrderStatus.processing;
    }
  }
}
