import 'package:flutter/material.dart';
import 'order.dart';

class LoadDraft {
  String category;
  TextEditingController weightController;

  LoadDraft({
    this.category = 'Regular Clothing',
    String initialWeight = '',
  }) : weightController = TextEditingController(text: initialWeight);

  void dispose() {
    weightController.dispose();
  }
}

class CheckInFormResult {
  final List<OrderLoad> loads;
  final String? loyaltyCardUid;  // Optional — customer may not have a card
  final bool extraFabCon;
  final bool extraDetergent;
  final String notes;

  const CheckInFormResult({
    required this.loads,
    this.loyaltyCardUid,
    required this.extraFabCon,
    required this.extraDetergent,
    required this.notes,
  });

  double get addOnsTotal =>
      (extraFabCon ? LaundryIntake.addonPrice : 0) +
      (extraDetergent ? LaundryIntake.addonPrice : 0);

  double get subtotal =>
      (LaundryIntake.basePricePerLoad * loads.length) + addOnsTotal;
}

class LaundryIntake {
  static const double basePricePerLoad = 170.0;
  static const double addonPrice = 20.0;

  static const Map<String, Map<String, dynamic>> categories = {
    'Regular Clothing': {
      'limit': 8.0,
      'unit': 'kg',
      'icon': Icons.checkroom_outlined,
      'desc': 'T-shirts, shorts, sleeveless, socks, underwear',
    },
    'Heavy Clothing': {
      'limit': 6.0,
      'unit': 'kg',
      'icon': Icons.dry_cleaning_outlined,
      'desc': 'Jeans, cargo, jackets, sweaters, corduroy',
    },
    'Beddings & Towels': {
      'limit': 5.0,
      'unit': 'kg',
      'icon': Icons.bed_outlined,
      'desc': 'Bedsheets, blankets, towels, curtains',
    },
    'Heavyweight Beddings': {
      'limit': 1.0,
      'unit': 'pc',
      'icon': Icons.hotel_outlined,
      'desc': 'Comforter, heavy fleece blanket, duvet',
    },
  };

  static double weightOf(LoadDraft load) =>
      double.tryParse(load.weightController.text) ?? 0.0;

  static double limitOf(String category) =>
      categories[category]!['limit'] as double;

  static String unitOf(String category) =>
      categories[category]!['unit'] as String;

  static String descOf(String category) =>
      categories[category]!['desc'] as String;

  static bool isOverLimit(LoadDraft load) =>
      weightOf(load) > limitOf(load.category);

  static List<OrderLoad> toOrderLoads(List<LoadDraft> drafts) {
    return [
      for (int i = 0; i < drafts.length; i++)
        OrderLoad(
          loadNumber: i + 1,
          category: drafts[i].category,
          weight: weightOf(drafts[i]),
          categoryLimit: limitOf(drafts[i].category),
          unit: unitOf(drafts[i].category),
          description: descOf(drafts[i].category),
          isOverLimit: isOverLimit(drafts[i]),
          notes: null,
        ),
    ];
  }
}
