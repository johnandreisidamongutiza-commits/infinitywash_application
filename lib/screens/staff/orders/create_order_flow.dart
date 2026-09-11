import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/custom_text_field.dart';
import '../../../models/order.dart';
import '../../../services/mock_data_service.dart';

class CreateOrderFlow extends StatefulWidget {
  const CreateOrderFlow({super.key});

  @override
  State<CreateOrderFlow> createState() => _CreateOrderFlowState();
}

class _CreateOrderFlowState extends State<CreateOrderFlow> {
  CollectionMethod _selectedCollection = CollectionMethod.dropOff;
  ReturnMethod _selectedReturn = ReturnMethod.shopPickup;
  String _selectedCategory = 'Regular Clothing';
  String? _selectedRfidTag;
  bool _addExtraFabCon = false;
  bool _addExtraDetergent = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _weightController = TextEditingController(text: '5.0');
  final TextEditingController _instructionsController = TextEditingController();

  final Map<String, Map<String, dynamic>> _categories = {
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

  static const double _basePrice = 170.0;
  double get _addOnsTotal => (_addExtraFabCon ? 20.0 : 0.0) + (_addExtraDetergent ? 20.0 : 0.0);
  double get _finalTotal => _basePrice + _addOnsTotal;

  double get _currentWeight => double.tryParse(_weightController.text) ?? 0.0;
  double get _categoryLimit => _categories[_selectedCategory]!['limit'] as double;
  bool get _isOverLimit => _currentWeight > _categoryLimit;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _weightController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  void _submitOrder({required bool isPaidImmediately}) {
    final availableTags = MockDataService().availableRfidTags;
    if (_selectedRfidTag == null || availableTags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an RFID tag before confirming.')),
      );
      return;
    }

    final double weight = double.tryParse(_weightController.text) ?? 1.0;
    final String fullInstructions = [
      'Category: $_selectedCategory',
      if (_addExtraFabCon) 'Extra Fab Con (+₱20)',
      if (_addExtraDetergent) 'Extra Detergent (+₱20)',
      if (_instructionsController.text.trim().isNotEmpty) _instructionsController.text.trim(),
    ].join(' | ');

    final newOrder = LaundryOrder(
      id: 'IW-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      customerName: _nameController.text.trim().isEmpty ? 'Walk-in Customer' : _nameController.text.trim(),
      channel: OrderChannel.walkIn,
      collectionMethod: _selectedCollection,
      returnMethod: _selectedReturn,
      status: OrderStatus.processing,
      paymentStatus: isPaidImmediately ? PaymentStatus.paid : PaymentStatus.unpaid,
      weight: weight,
      rfidTag: _selectedRfidTag,
      instructions: fullInstructions,
      createdAt: DateTime.now(),
    );

    MockDataService().addOrder(newOrder);
    MockDataService().useSupplies(weight);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isPaidImmediately
              ? 'Order Created! Payment of ₱${_finalTotal.toStringAsFixed(2)} marked as PAID.'
              : 'Order Created! Saved as UNPAID (to pay on claiming).',
        ),
        backgroundColor: isPaidImmediately ? Colors.green : AppTheme.accentBlue,
      ),
    );
    Navigator.pop(context);
  }

  void _showImmediatePaymentModal() {
    String method = 'Cash';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Collect Counter Payment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Amount Due:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    Text('₱${_finalTotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('Select Payment Method', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setModalState(() => method = 'Cash'),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: method == 'Cash' ? AppTheme.accentBlue.withValues(alpha: 0.1) : AppTheme.softGray,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: method == 'Cash' ? AppTheme.accentBlue : AppTheme.borderGray),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.money, color: method == 'Cash' ? AppTheme.accentBlue : AppTheme.textLight),
                            const SizedBox(width: 8),
                            const Text('Cash', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setModalState(() => method = 'GCash'),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: method == 'GCash' ? AppTheme.accentBlue.withValues(alpha: 0.1) : AppTheme.softGray,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: method == 'GCash' ? AppTheme.accentBlue : AppTheme.borderGray),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.account_balance_wallet_outlined,
                                color: method == 'GCash' ? AppTheme.accentBlue : AppTheme.textLight),
                            const SizedBox(width: 8),
                            const Text('GCash', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _submitOrder(isPaidImmediately: true);
                },
                child: Text('Confirm Paid (₱${_finalTotal.toStringAsFixed(2)})'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final availableTags = MockDataService().availableRfidTags;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('New Walk-in Order'),
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
            // 1. Laundry Category Selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Laundry Type & Load Limit', style: AppTheme.lightTheme.textTheme.titleMedium),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('₱170 Full Service',
                      style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Select the category to enforce the machine load limit.',
              style: TextStyle(fontSize: 12, color: AppTheme.textLight),
            ),
            const SizedBox(height: 14),

            ..._categories.entries.map((entry) {
              final isSelected = _selectedCategory == entry.key;
              final limit = entry.value['limit'];
              final unit = entry.value['unit'];
              final icon = entry.value['icon'] as IconData;
              final desc = entry.value['desc'] as String;

              return GestureDetector(
                onTap: () => setState(() => _selectedCategory = entry.key),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? AppTheme.accentBlue : AppTheme.borderGray,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.accentBlue.withValues(alpha: 0.1) : AppTheme.softGray,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: isSelected ? AppTheme.accentBlue : AppTheme.textLight, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 2),
                            Text(desc, style: const TextStyle(fontSize: 11, color: AppTheme.textLight)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.accentBlue : AppTheme.softGray,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$limit $unit',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : AppTheme.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 20),

            // 2. Customer Details & Measured Weight
            CustomTextField(
              label: 'Customer Name',
              hint: 'Enter customer name',
              prefixIcon: Icons.person_outline,
              controller: _nameController,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Phone Number (Optional)',
              hint: '09XX-XXX-XXXX',
              prefixIcon: Icons.phone_android,
              controller: _phoneController,
            ),
            const SizedBox(height: 16),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomTextField(
                        label: 'Scale Weight',
                        hint: 'Weight',
                        prefixIcon: Icons.scale_outlined,
                        controller: _weightController,
                        onChanged: (val) => setState(() {}),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  margin: const EdgeInsets.only(top: 28),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: _isOverLimit ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _isOverLimit ? Colors.red : Colors.green),
                  ),
                  child: Text(
                    _isOverLimit ? 'EXCEEDS LIMIT' : 'OK (≤ $_categoryLimit)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _isOverLimit ? Colors.red : Colors.green,
                    ),
                  ),
                ),
              ],
            ),

            if (_isOverLimit)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Warning: Selected category limit is $_categoryLimit ${_categories[_selectedCategory]!['unit']}. Additional load or split may be needed.',
                  style: const TextStyle(fontSize: 11, color: Colors.red),
                ),
              ),

            const SizedBox(height: 24),

            // 3. Optional Add-ons (+₱20 each)
            Text('Optional Add-ons', style: AppTheme.lightTheme.textTheme.titleMedium),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilterChip(
                    label: const Text('Extra Fab Con (+₱20)'),
                    selected: _addExtraFabCon,
                    onSelected: (val) => setState(() => _addExtraFabCon = val),
                    selectedColor: AppTheme.accentBlue.withValues(alpha: 0.15),
                    checkmarkColor: AppTheme.accentBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilterChip(
                    label: const Text('Extra Detergent (+₱20)'),
                    selected: _addExtraDetergent,
                    onSelected: (val) => setState(() => _addExtraDetergent = val),
                    selectedColor: AppTheme.accentBlue.withValues(alpha: 0.15),
                    checkmarkColor: AppTheme.accentBlue,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 4. Return Method
            Text('Return Method', style: AppTheme.lightTheme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildOptionCard(
                    icon: Icons.storefront_outlined,
                    label: 'Shop Pickup',
                    subtitle: 'Customer collects',
                    isSelected: _selectedReturn == ReturnMethod.shopPickup,
                    onTap: () => setState(() => _selectedReturn = ReturnMethod.shopPickup),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildOptionCard(
                    icon: Icons.local_shipping_outlined,
                    label: 'Rider Delivery',
                    subtitle: 'Delivery included',
                    isSelected: _selectedReturn == ReturnMethod.delivery,
                    onTap: () => setState(() => _selectedReturn = ReturnMethod.delivery),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 5. RFID Tag Assignment
            Text('Assign RFID Tag', style: AppTheme.lightTheme.textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              'Select an available RFID tag for machine tracking.',
              style: TextStyle(fontSize: 12, color: AppTheme.textLight),
            ),
            const SizedBox(height: 10),
            if (availableTags.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.errorRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppTheme.errorRed, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('No RFID tags available. Please wait for one to free up.',
                          style: TextStyle(color: AppTheme.errorRed, fontSize: 12)),
                    ),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppTheme.softGray,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.borderGray),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedRfidTag,
                    isExpanded: true,
                    hint: const Text('Select Free RFID Tag'),
                    items: availableTags.map((tag) {
                      return DropdownMenuItem<String>(
                        value: tag,
                        child: Row(
                          children: [
                            const Icon(Icons.nfc_outlined, color: AppTheme.accentBlue, size: 18),
                            const SizedBox(width: 10),
                            Text(tag, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedRfidTag = value),
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // 6. Special Instructions
            Text('Special Instructions (Optional)', style: AppTheme.lightTheme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _instructionsController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'e.g. Separate whites, gentle cycle, no bleach...',
                hintStyle: TextStyle(color: AppTheme.textLight.withValues(alpha: 0.5), fontSize: 13),
                filled: true,
                fillColor: AppTheme.softGray,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),

            const SizedBox(height: 28),

            // 7. Order Bill Calculation Summary Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderGray),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Bill Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const Divider(height: 20),
                  _buildSummaryRow('Full Service: Wash, Dry & Fold', '₱170.00'),
                  _buildSummaryRow('Detergent + Fab Con', 'INCLUDED (FREE)'),
                  _buildSummaryRow('Pick Up & Delivery', 'INCLUDED (FREE)'),
                  if (_addExtraFabCon) _buildSummaryRow('Extra Fab Con Add-on', '+₱20.00'),
                  if (_addExtraDetergent) _buildSummaryRow('Extra Detergent Add-on', '+₱20.00'),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Bill', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(
                        '₱${_finalTotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.accentBlue),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 8. Payment Action Buttons
            Text('Payment Action', style: AppTheme.lightTheme.textTheme.titleMedium),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: (_selectedRfidTag == null || availableTags.isEmpty) ? null : _showImmediatePaymentModal,
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: Text('Collect Payment Now (₱${_finalTotal.toStringAsFixed(2)})'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: (_selectedRfidTag == null || availableTags.isEmpty)
                  ? null
                  : () => _submitOrder(isPaidImmediately: false),
              icon: const Icon(Icons.schedule, size: 18),
              label: const Text('Pay upon Pickup / Claiming'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textLight)),
          Text(amount, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: isSelected ? AppStyles.selectedCardDecoration : AppStyles.cardDecoration,
        child: Column(
          children: [
            Icon(icon, color: isSelected ? AppTheme.accentBlue : AppTheme.textLight, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppTheme.accentBlue : AppTheme.textDark,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: isSelected ? AppTheme.accentBlue.withValues(alpha: 0.7) : AppTheme.textLight,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
