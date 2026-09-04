enum OrderStatus { washing, drying, folding, ready, completed }
enum OrderType { walkIn, pickUpAndDelivery }
enum PaymentStatus { paid, unpaid }

class LaundryOrder {
  final String id;
  final String customerName;
  final OrderType type;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final double weight;
  final String? instructions;
  final DateTime createdAt;

  LaundryOrder({
    required this.id,
    required this.customerName,
    required this.type,
    required this.status,
    required this.paymentStatus,
    required this.weight,
    this.instructions,
    required this.createdAt,
  });

  String get statusText {
    switch (status) {
      case OrderStatus.washing: return 'Washing';
      case OrderStatus.drying: return 'Drying';
      case OrderStatus.folding: return 'Folding';
      case OrderStatus.ready: return 'Ready for Pickup';
      case OrderStatus.completed: return 'Completed';
    }
  }
}
