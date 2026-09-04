class Supply {
  final String id;
  final String name;
  final double currentAmount; // in Liters or Units
  final double maxAmount;
  final String unit; // e.g., 'L', 'units'

  Supply({
    required this.id,
    required this.name,
    required this.currentAmount,
    required this.maxAmount,
    required this.unit,
  });

  bool get isLow => (currentAmount / maxAmount) < 0.2; // Low if less than 20%

  double get percentage => currentAmount / maxAmount;
}
