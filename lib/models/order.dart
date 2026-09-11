enum OrderStatus { pending_approval, pending_pickup, processing, ready, out_for_delivery, completed }
enum CollectionMethod { dropOff, riderPickup }
enum ReturnMethod { shopPickup, delivery }
enum OrderChannel { walkIn, online }
enum PaymentStatus { paid, unpaid }

class LaundryOrder {
  final String id;
  final String customerName;
  final OrderChannel channel;
  final CollectionMethod collectionMethod;
  final ReturnMethod returnMethod;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final double weight;
  final String? instructions;
  final String? rfidTag;
  final DateTime createdAt;

  LaundryOrder({
    required this.id,
    required this.customerName,
    required this.channel,
    this.collectionMethod = CollectionMethod.dropOff,
    this.returnMethod = ReturnMethod.shopPickup,
    required this.status,
    required this.paymentStatus,
    required this.weight,
    this.instructions,
    this.rfidTag,
    required this.createdAt,
  });

  String get statusText {
    switch (status) {
      case OrderStatus.pending_approval: return 'Pending Approval';
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
