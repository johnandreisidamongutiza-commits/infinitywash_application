import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/custom_text_field.dart';
import '../../../models/order.dart';
import '../../../services/mock_data_service.dart';

class _CustomerProfile {
  final String firstName;
  final String lastName;
  final String phone;
  final ReturnMethod returnMethod;
  final String? address;
  final String? landmark;
  final String? instructions;

  const _CustomerProfile({
    required this.firstName,
    required this.lastName,
    required this.phone,
    this.returnMethod = ReturnMethod.shopPickup,
    this.address,
    this.landmark,
    this.instructions,
  });

  String get fullName => '$firstName $lastName'.trim();
}

class CreateOrderFlow extends StatefulWidget {
  const CreateOrderFlow({super.key});

  @override
  State<CreateOrderFlow> createState() => _CreateOrderFlowState();
}

class _CreateOrderFlowState extends State<CreateOrderFlow> {
  final CollectionMethod _selectedCollection = CollectionMethod.dropOff;
  ReturnMethod _selectedReturn = ReturnMethod.shopPickup;
  String _selectedCategory = 'Regular Clothing';
  String? _selectedRfidTag;
  bool _addExtraFabCon = false;
  bool _addExtraDetergent = false;
  int _activeStep = 1; // 1 = Customer Details, 2 = Laundry & Intake

  _CustomerProfile? _suggestedCustomer;
  bool _dismissedSuggestion = false;

  static const List<_CustomerProfile> _knownCustomers = [
    _CustomerProfile(
      firstName: 'Juan',
      lastName: 'Dela Cruz',
      phone: '0917-123-4567',
      returnMethod: ReturnMethod.delivery,
      address: '123 Mango Ave, Brgy. Guadalupe, Cebu City',
      landmark: 'Near yellow gate across 7-Eleven',
      instructions: 'Separate whites, delicate wash',
    ),
    _CustomerProfile(
      firstName: 'Maria',
      lastName: 'Santos',
      phone: '0922-555-0192',
      returnMethod: ReturnMethod.delivery,
      address: '456 Banilad Rd, Cebu City',
      landmark: 'Beside green pharmacy',
      instructions: 'Extra gentle cycle on shirts',
    ),
    _CustomerProfile(
      firstName: 'Carlos',
      lastName: 'Reyes',
      phone: '0918-999-4321',
      returnMethod: ReturnMethod.shopPickup,
      instructions: 'Fold neatly in plastic',
    ),
    _CustomerProfile(
      firstName: 'John',
      lastName: 'Doe',
      phone: '0912-345-6789',
      returnMethod: ReturnMethod.shopPickup,
      instructions: 'Heavy wash for denim',
    ),
    _CustomerProfile(
      firstName: 'Jane',
      lastName: 'Smith',
      phone: '0920-111-2233',
      returnMethod: ReturnMethod.delivery,
      address: '789 Parkmall Area, Mandaue City',
      landmark: 'Opposite Shell station',
      instructions: 'Gentle cycle, hypoallergenic detergent',
    ),
    _CustomerProfile(
      firstName: 'Bob',
      lastName: 'Brown',
      phone: '0919-888-7766',
      returnMethod: ReturnMethod.delivery,
      address: '88 Jones Ave, Cebu City',
      landmark: 'Beside BDO bank',
      instructions: 'Extra fabric softener please',
    ),
  ];

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _weightController = TextEditingController(text: '5.0');
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _landmarkController = TextEditingController();
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

  String get _customerFullName {
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();
    if (first.isEmpty && last.isEmpty) return 'Walk-in Customer';
    if (last.isEmpty) return first;
    if (first.isEmpty) return last;
    return '$first $last';
  }

  double get _currentWeight => double.tryParse(_weightController.text) ?? 0.0;
  double get _categoryLimit => _categories[_selectedCategory]!['limit'] as double;
  bool get _isOverLimit => _currentWeight > _categoryLimit;

  @override
  void initState() {
    super.initState();
    _firstNameController.addListener(_checkForCustomerSuggestion);
    _lastNameController.addListener(_checkForCustomerSuggestion);
  }

  void _checkForCustomerSuggestion() {
    if (_dismissedSuggestion) return;
    final first = _firstNameController.text.trim().toLowerCase();
    final last = _lastNameController.text.trim().toLowerCase();
    final query = '$first $last'.trim();

    if (query.length < 2) {
      if (_suggestedCustomer != null) {
        setState(() => _suggestedCustomer = null);
      }
      return;
    }

    _CustomerProfile? match;
    for (final customer in _knownCustomers) {
      final custFirst = customer.firstName.toLowerCase();
      final custLast = customer.lastName.toLowerCase();
      final custFull = customer.fullName.toLowerCase();

      if (custFirst.startsWith(first) && (last.isEmpty || custLast.startsWith(last))) {
        match = customer;
        break;
      } else if (custLast.startsWith(first) || custFull.contains(query)) {
        match = customer;
        break;
      }
    }

    // Hide if fields already match this customer
    if (match != null &&
        _firstNameController.text.trim().toLowerCase() == match.firstName.toLowerCase() &&
        _lastNameController.text.trim().toLowerCase() == match.lastName.toLowerCase() &&
        _phoneController.text.trim() == match.phone) {
      match = null;
    }

    if (_suggestedCustomer != match) {
      setState(() => _suggestedCustomer = match);
    }
  }

  void _applyCustomerSuggestion(_CustomerProfile customer) {
    setState(() {
      _firstNameController.text = customer.firstName;
      _lastNameController.text = customer.lastName;
      _phoneController.text = customer.phone;

      if (customer.returnMethod == ReturnMethod.delivery) {
        _selectedReturn = ReturnMethod.delivery;
        if (customer.address != null) {
          _addressController.text = customer.address!;
        }
        if (customer.landmark != null) {
          _landmarkController.text = customer.landmark!;
        }
      } else {
        _selectedReturn = ReturnMethod.shopPickup;
      }

      if (customer.instructions != null && customer.instructions!.isNotEmpty) {
        _instructionsController.text = customer.instructions!;
      }

      _suggestedCustomer = null;
      _dismissedSuggestion = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Loaded previous details for ${customer.fullName}')),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _firstNameController.removeListener(_checkForCustomerSuggestion);
    _lastNameController.removeListener(_checkForCustomerSuggestion);
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _weightController.dispose();
    _addressController.dispose();
    _landmarkController.dispose();
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

    if (_selectedReturn == ReturnMethod.delivery && _addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a delivery address for rider delivery.')),
      );
      return;
    }

    final double weight = double.tryParse(_weightController.text) ?? 1.0;
    final String fullInstructions = [
      'Category: $_selectedCategory',
      if (_selectedReturn == ReturnMethod.delivery && _addressController.text.trim().isNotEmpty)
        'Delivery Address: ${_addressController.text.trim()}${_landmarkController.text.trim().isNotEmpty ? ' (Landmark: ${_landmarkController.text.trim()})' : ''}',
      if (_addExtraFabCon) 'Extra Fab Con (+₱20)',
      if (_addExtraDetergent) 'Extra Detergent (+₱20)',
      if (_instructionsController.text.trim().isNotEmpty) _instructionsController.text.trim(),
    ].join(' | ');

    final newOrder = LaundryOrder(
      id: 'IW-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      customerName: _customerFullName,
      customerPhone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
      deliveryAddress: _selectedReturn == ReturnMethod.delivery && _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
      deliveryLandmark: _selectedReturn == ReturnMethod.delivery && _landmarkController.text.trim().isNotEmpty ? _landmarkController.text.trim() : null,
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
    final bool hasRfidSelected = _selectedRfidTag != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('New Walk-in Order'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: availableTags.isEmpty
                  ? AppTheme.errorRed.withValues(alpha: 0.1)
                  : AppTheme.accentBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.nfc_outlined,
                  size: 14,
                  color: availableTags.isEmpty ? AppTheme.errorRed : AppTheme.accentBlue,
                ),
                const SizedBox(width: 4),
                Text(
                  '${availableTags.length} Tags Available',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: availableTags.isEmpty ? AppTheme.errorRed : AppTheme.accentBlue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildStickyBottomBar(availableTags),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Customer Section (Collapsible Step 1)
            _buildCustomerSection(),
            const SizedBox(height: 14),

            // 2. Laundry & Intake Section (Collapsible Step 2)
            _buildLaundryIntakeSection(availableTags, hasRfidSelected),
            if (_activeStep == 2) ...[
              const SizedBox(height: 14),
              // 3. Optional Extras & Notes
              _buildExtrasSection(),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerSection() {
    if (_activeStep != 1) {
      final customerName = _customerFullName;
      final customerPhone = _phoneController.text.trim();

      return InkWell(
        onTap: () => setState(() => _activeStep = 1),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.green.withValues(alpha: 0.4), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 16, color: Colors.green),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('1. Customer Details',
                        style: TextStyle(fontSize: 11, color: AppTheme.textLight, fontWeight: FontWeight.w600)),
                    Text(
                      customerName,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (customerPhone.isNotEmpty)
                      Text(customerPhone, style: const TextStyle(fontSize: 11, color: AppTheme.textLight)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_outlined, size: 13, color: AppTheme.accentBlue),
                    SizedBox(width: 4),
                    Text('Change',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.person_outline, size: 18, color: AppTheme.accentBlue),
                  SizedBox(width: 8),
                  Text(
                    '1. Customer Details',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Active Step',
                    style: TextStyle(color: AppTheme.accentBlue, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: CustomTextField(
                  label: 'First Name',
                  hint: 'Juan',
                  prefixIcon: Icons.person_outline,
                  controller: _firstNameController,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CustomTextField(
                  label: 'Last Name (Optional)',
                  hint: 'Dela Cruz',
                  prefixIcon: Icons.badge_outlined,
                  controller: _lastNameController,
                ),
              ),
            ],
          ),
          if (_suggestedCustomer != null) ...[
            const SizedBox(height: 10),
            _buildCustomerSuggestionBanner(_suggestedCustomer!),
          ],
          const SizedBox(height: 10),
          CustomTextField(
            label: 'Phone Number (Optional)',
            hint: '09XX-XXX-XXXX',
            prefixIcon: Icons.phone_android,
            controller: _phoneController,
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerSuggestionBanner(_CustomerProfile customer) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.accentBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.history, size: 15, color: AppTheme.accentBlue),
                  const SizedBox(width: 6),
                  const Text(
                    'Returning Customer Found',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accentBlue,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => setState(() {
                  _suggestedCustomer = null;
                  _dismissedSuggestion = true;
                }),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 16, color: AppTheme.textLight),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${customer.fullName} • ${customer.phone}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
          ),
          if (customer.returnMethod == ReturnMethod.delivery && customer.address != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.delivery_dining_outlined, size: 13, color: AppTheme.textLight),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${customer.address!}${customer.landmark != null ? " (${customer.landmark!})" : ""}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (customer.instructions != null && customer.instructions!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.notes, size: 13, color: AppTheme.textLight),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Notes: ${customer.instructions!}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _applyCustomerSuggestion(customer),
              icon: const Icon(Icons.bolt, size: 15),
              label: const Text('Auto-fill Previous Details'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLaundryIntakeSection(List<String> availableTags, bool hasRfidSelected) {
    if (_activeStep != 2) {
      return InkWell(
        onTap: () => setState(() => _activeStep = 2),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: AppStyles.cardDecoration,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.softGray,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.local_laundry_service_outlined, size: 18, color: AppTheme.textLight),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '2. Laundry & Intake',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                    ),
                    Text(
                      'Category, Scale Weight, RFID Tag & Return Method',
                      style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: AppTheme.textLight),
            ],
          ),
        ),
      );
    }

    final categoriesList = _categories.entries.toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.local_laundry_service_outlined, size: 18, color: AppTheme.accentBlue),
                  SizedBox(width: 8),
                  Text(
                    '2. Laundry & Intake',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('₱170 Full Service',
                    style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2x2 Category Grid
          Row(
            children: [
              Expanded(child: _buildCategoryTile(categoriesList[0])),
              const SizedBox(width: 8),
              Expanded(child: _buildCategoryTile(categoriesList[1])),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildCategoryTile(categoriesList[2])),
              const SizedBox(width: 8),
              Expanded(child: _buildCategoryTile(categoriesList[3])),
            ],
          ),
          const SizedBox(height: 14),

          // Scale Weight Input
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: CustomTextField(
                  label: 'Measured Scale Weight',
                  hint: '5.0',
                  prefixIcon: Icons.monitor_weight_outlined,
                  controller: _weightController,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _isOverLimit ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _isOverLimit ? Colors.red : Colors.green),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isOverLimit ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                      size: 15,
                      color: _isOverLimit ? Colors.red : Colors.green,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isOverLimit ? 'EXCEEDS' : 'OK (≤ $_categoryLimit)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _isOverLimit ? Colors.red : Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isOverLimit) ...[
            const SizedBox(height: 6),
            Text(
              'Selected category limit is $_categoryLimit ${_categories[_selectedCategory]!['unit']}. Additional load or split needed.',
              style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w500),
            ),
          ],

          const Divider(height: 24),

          // Manual RFID Tag Assignment Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.nfc_outlined, size: 16, color: AppTheme.accentBlue),
                  SizedBox(width: 6),
                  Text(
                    'Manual RFID Tag Assignment',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  ),
                ],
              ),
              if (hasRfidSelected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check, size: 12, color: Colors.green),
                      const SizedBox(width: 3),
                      Text(
                        'Assigned: $_selectedRfidTag',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Selection Required',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Select the physical RFID tag you are clipping onto the customer\'s laundry bag:',
            style: TextStyle(fontSize: 11, color: AppTheme.textLight),
          ),
          const SizedBox(height: 10),

          // RFID Tag Dropdown Picker (Space Saving)
          if (availableTags.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.errorRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppTheme.errorRed, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No free RFID tags available in shop inventory.',
                      style: TextStyle(color: AppTheme.errorRed, fontSize: 12),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: hasRfidSelected ? AppTheme.accentBlue.withValues(alpha: 0.06) : AppTheme.softGray,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hasRfidSelected ? AppTheme.accentBlue : AppTheme.borderGray,
                  width: hasRfidSelected ? 1.5 : 1,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedRfidTag,
                  isExpanded: true,
                  hint: const Row(
                    children: [
                      Icon(Icons.nfc, color: AppTheme.textLight, size: 16),
                      SizedBox(width: 8),
                      Text('Select physical RFID tag...', style: TextStyle(fontSize: 13, color: AppTheme.textLight)),
                    ],
                  ),
                  items: availableTags.map((tag) {
                    return DropdownMenuItem<String>(
                      value: tag,
                      child: Row(
                        children: [
                          const Icon(Icons.nfc, color: AppTheme.accentBlue, size: 16),
                          const SizedBox(width: 10),
                          Text(tag, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const Spacer(),
                          const Text('Available',
                              style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedRfidTag = val),
                ),
              ),
            ),

          const Divider(height: 24),

          // Return Method
          const Text(
            'Return Method',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildReturnOption(
                  icon: Icons.storefront_outlined,
                  title: 'Shop Pickup',
                  isSelected: _selectedReturn == ReturnMethod.shopPickup,
                  onTap: () => setState(() => _selectedReturn = ReturnMethod.shopPickup),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildReturnOption(
                  icon: Icons.delivery_dining_outlined,
                  title: 'Rider Delivery',
                  isSelected: _selectedReturn == ReturnMethod.delivery,
                  onTap: () => setState(() => _selectedReturn = ReturnMethod.delivery),
                ),
              ),
            ],
          ),
          if (_selectedReturn == ReturnMethod.delivery) ...[
            const SizedBox(height: 12),
            CustomTextField(
              label: 'Delivery Address',
              hint: 'House/Unit No., Street, Barangay, City',
              prefixIcon: Icons.location_on_outlined,
              controller: _addressController,
            ),
            const SizedBox(height: 10),
            CustomTextField(
              label: 'Landmark (Optional)',
              hint: 'Near blue gate, across grocery store...',
              prefixIcon: Icons.flag_outlined,
              controller: _landmarkController,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryTile(MapEntry<String, Map<String, dynamic>> entry) {
    final isSelected = _selectedCategory == entry.key;
    final limit = entry.value['limit'];
    final unit = entry.value['unit'];
    final icon = entry.value['icon'] as IconData;

    return InkWell(
      onTap: () => setState(() => _selectedCategory = entry.key),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentBlue.withValues(alpha: 0.08) : AppTheme.softGray,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.accentBlue : AppTheme.borderGray.withValues(alpha: 0.6),
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? AppTheme.accentBlue : AppTheme.textLight),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppTheme.accentBlue : AppTheme.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Max $limit $unit',
                    style: TextStyle(fontSize: 10, color: isSelected ? AppTheme.accentBlue : AppTheme.textLight),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReturnOption({
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentBlue.withValues(alpha: 0.08) : AppTheme.softGray,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.accentBlue : AppTheme.borderGray.withValues(alpha: 0.6),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isSelected ? AppTheme.accentBlue : AppTheme.textLight),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? AppTheme.accentBlue : AppTheme.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExtrasSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_outlined, size: 18, color: AppTheme.accentBlue),
              SizedBox(width: 8),
              Text(
                'Add-ons & Notes (Optional)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilterChip(
                  label: const Text('+ Fab Con (₱20)', style: TextStyle(fontSize: 12)),
                  selected: _addExtraFabCon,
                  onSelected: (val) => setState(() => _addExtraFabCon = val),
                  selectedColor: AppTheme.accentBlue.withValues(alpha: 0.15),
                  checkmarkColor: AppTheme.accentBlue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilterChip(
                  label: const Text('+ Detergent (₱20)', style: TextStyle(fontSize: 12)),
                  selected: _addExtraDetergent,
                  onSelected: (val) => setState(() => _addExtraDetergent = val),
                  selectedColor: AppTheme.accentBlue.withValues(alpha: 0.15),
                  checkmarkColor: AppTheme.accentBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _instructionsController,
            maxLines: 1,
            decoration: InputDecoration(
              hintText: 'Special instructions (e.g. gentle cycle, separate whites)...',
              hintStyle: TextStyle(color: AppTheme.textLight.withValues(alpha: 0.6), fontSize: 12),
              filled: true,
              fillColor: AppTheme.softGray,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyBottomBar(List<String> availableTags) {
    final bool canSubmit = _selectedRfidTag != null && availableTags.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedRfidTag == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline, size: 12, color: Colors.orange.shade800),
                    const SizedBox(width: 4),
                    Text(
                      'Please manually select an RFID tag to enable order creation',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade800),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.nfc, size: 12, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      'Assigned RFID Tag: $_selectedRfidTag',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                // Total
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Bill', style: TextStyle(fontSize: 11, color: AppTheme.textLight)),
                    Text(
                      '₱${_finalTotal.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppTheme.accentBlue),
                    ),
                    if (_addOnsTotal > 0)
                      Text(
                        '+₱${_addOnsTotal.toStringAsFixed(0)} add-ons',
                        style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                // Actions
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: canSubmit ? () => _submitOrder(isPaidImmediately: false) : null,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Pay Later', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: canSubmit ? _showImmediatePaymentModal : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            'Collect ₱${_finalTotal.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
