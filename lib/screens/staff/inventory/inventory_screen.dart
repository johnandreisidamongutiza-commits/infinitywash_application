import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/supply.dart';
import 'manage_supply_screen.dart';

import '../../../services/mock_data_service.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  @override
  Widget build(BuildContext context) {
    final supplies = MockDataService().supplies;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Inventory'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current Supplies', style: AppTheme.lightTheme.textTheme.titleMedium),
            const SizedBox(height: 16),
            ...supplies.map((s) => _buildSupplyCard(s)),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ManageSupplyScreen(mode: ManageSupplyMode.add)),
                );
                setState(() {});
              },
              child: const Text('Add New Supply Type'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupplyCard(Supply supply) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(supply.name, style: AppTheme.lightTheme.textTheme.titleMedium),
              if (supply.isLow)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppTheme.errorRed.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Text('LOW STOCK', style: TextStyle(color: AppTheme.errorRed, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: supply.percentage,
            backgroundColor: AppTheme.softGray,
            valueColor: AlwaysStoppedAnimation<Color>(supply.isLow ? AppTheme.errorRed : Colors.green),
            minHeight: 10,
            borderRadius: BorderRadius.circular(5),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${supply.currentAmount} ${supply.unit} / ${supply.maxAmount} ${supply.unit}', style: AppTheme.lightTheme.textTheme.bodyMedium),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => ManageSupplyScreen(mode: ManageSupplyMode.update, supply: supply)),
                  );
                },
                child: const Text('Update', style: TextStyle(color: AppTheme.accentBlue)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
