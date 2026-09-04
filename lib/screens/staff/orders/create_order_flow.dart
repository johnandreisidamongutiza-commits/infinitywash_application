import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/custom_text_field.dart';
import '../../../models/order.dart';

class CreateOrderFlow extends StatefulWidget {
  const CreateOrderFlow({super.key});

  @override
  State<CreateOrderFlow> createState() => _CreateOrderFlowState();
}

class _CreateOrderFlowState extends State<CreateOrderFlow> {
  OrderType _selectedType = OrderType.walkIn;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _instructionsController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('New Order'),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Order Type', style: AppTheme.lightTheme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildTypeCard(OrderType.walkIn, Icons.directions_walk, 'Walk-in')),
                const SizedBox(width: 16),
                Expanded(child: _buildTypeCard(OrderType.pickUpAndDelivery, Icons.delivery_dining, 'Pick-up')),
              ],
            ),
            const SizedBox(height: 30),
            CustomTextField(
              label: 'Customer Name',
              hint: 'Enter customer name',
              prefixIcon: Icons.person_outline,
              controller: _nameController,
            ),
            const SizedBox(height: 20),
            CustomTextField(
              label: 'Weight (kg)',
              hint: 'Enter weight in kg',
              prefixIcon: Icons.scale_outlined,
              controller: _weightController,
            ),
            const SizedBox(height: 20),
            Text('Special Instructions', style: AppTheme.lightTheme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _instructionsController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Any special handling?',
                hintStyle: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(color: AppTheme.textLight.withOpacity(0.5)),
                filled: true,
                fillColor: AppTheme.softGray,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                // Mock order creation logic
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Order Created Successfully!')),
                );
                Navigator.pop(context);
              },
              child: const Text('Confirm Order'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeCard(OrderType type, IconData icon, String label) {
    bool isSelected = _selectedType == type;
    return GestureDetector(
      onTap: () => setState(() => _selectedType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: isSelected ? AppStyles.selectedCardDecoration : AppStyles.cardDecoration,
        child: Column(
          children: [
            Icon(icon, color: isSelected ? AppTheme.accentBlue : AppTheme.textLight, size: 32),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: isSelected ? AppTheme.accentBlue : AppTheme.textDark, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
