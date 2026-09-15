import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/custom_text_field.dart';
import '../../../models/order.dart';
import '../../../services/mock_data_service.dart';
import '../../../services/customer_service.dart';
import '../../../services/service_catalog_service.dart';
import '../../../services/order_service.dart';
import '../../../services/supabase_service.dart';

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

class _LoadEntry {
  String category;
  TextEditingController weightController;

  _LoadEntry({
    this.category = 'Regular Clothing',
    String initialWeight = '',
  }) : weightController = TextEditingController(text: initialWeight);

  void dispose() {
    weightController.dispose();
  }
}

class _CreateOrderFlowState extends State<CreateOrderFlow> {
  final CollectionMethod _selectedCollection = CollectionMethod.dropOff;
  ReturnMethod _selectedReturn = ReturnMethod.shopPickup;
  String? _selectedRfidTag;
  bool _addExtraFabCon = false;
  bool _addExtraDetergent = false;
  bool _isSubmitting = false; // Loading state for order creation
  
  // Services
  final CustomerService _customerService = CustomerService();
  final ServiceCatalogService _catalogService = ServiceCatalogService();
  final OrderService _orderService = OrderService();
  
  // Section expansion state - only one can be expanded at a time (accordion behavior)
  int? _expandedStep = 1;  // null = all collapsed, 1/2/3 = that step expanded

  _CustomerProfile? _suggestedCustomer;
  bool _dismissedSuggestion = false;

  // Multiple loads support
  final List<_LoadEntry> _loads = [];

  @override
  void initState() {
    super.initState();
    // Start with one load
    _loads.add(_LoadEntry(initialWeight: '5.0'));
    _firstNameController.addListener(_checkForCustomerSuggestion);
    _lastNameController.addListener(_checkForCustomerSuggestion);
  }

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
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _landmarkController = TextEditingController();
  final TextEditingController _instructionsController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

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

  static const double _basePricePerLoad = 170.0;
  double get _addOnsTotal => (_addExtraFabCon ? 20.0 : 0.0) + (_addExtraDetergent ? 20.0 : 0.0);
  double get _finalTotal => (_basePricePerLoad * _loads.length) + _addOnsTotal;

  String get _customerFullName {
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();
    if (first.isEmpty && last.isEmpty) return 'Walk-in Customer';
    if (last.isEmpty) return first;
    if (first.isEmpty) return last;
    return '$first $last';
  }

  double _getLoadWeight(int index) => double.tryParse(_loads[index].weightController.text) ?? 0.0;
  double _getLoadLimit(int index) => _categories[_loads[index].category]!['limit'] as double;
  bool _isLoadOverLimit(int index) => _getLoadWeight(index) > _getLoadLimit(index);
  
  double get _totalWeight => _loads.fold(0.0, (sum, load) => sum + _getLoadWeight(_loads.indexOf(load)));

  double _calculateTotalPrice() {
    double basePrice = 170.0 * _loads.length;
    double addOnsPrice = 0.0;
    
    if (_addExtraFabCon) addOnsPrice += 20.0;
    if (_addExtraDetergent) addOnsPrice += 20.0;
    
    return basePrice + addOnsPrice;
  }

  // Step completion validation
  bool get _isStep1Complete {
    return _customerFullName.isNotEmpty && _customerFullName != 'Walk-in Customer';
  }
  
  bool get _isStep2Complete {
    return _selectedRfidTag != null && 
           _loads.isNotEmpty && 
           _loads.every((load) => _getLoadWeight(_loads.indexOf(load)) > 0) &&
           (_selectedReturn != ReturnMethod.delivery || _addressController.text.trim().isNotEmpty);
  }

  void _addLoad() {
    setState(() {
      _loads.add(_LoadEntry());
    });
  }

  void _removeLoad(int index) {
    if (_loads.length > 1) {
      setState(() {
        _loads[index].dispose();
        _loads.removeAt(index);
      });
    }
  }

  void _showAutoSplitDialog(int loadIndex) {
    final double weight = _getLoadWeight(loadIndex);
    final String category = _loads[loadIndex].category;
    final double limit = _categories[category]!['limit'] as double;
    final String unit = _categories[category]!['unit'] as String;
    
    if (weight <= limit) return;
    
    final int suggestedLoads = (weight / limit).ceil();
    final double weightPerLoad = weight / suggestedLoads;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text('Weight Exceeds Limit', style: TextStyle(fontSize: 17)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current: ${weight.toStringAsFixed(1)} $unit $category',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Limit: ${limit.toStringAsFixed(1)} $unit per load',
                  style: const TextStyle(color: AppTheme.textLight, fontSize: 13)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Suggested Split:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Text('$suggestedLoads loads × ${weightPerLoad.toStringAsFixed(1)} $unit each',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('Pricing: ₱170 × $suggestedLoads = ₱${(170 * suggestedLoads).toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textLight)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep Single Load'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                // Update current load with first split
                _loads[loadIndex].weightController.text = weightPerLoad.toStringAsFixed(1);
                // Add additional loads
                for (int i = 1; i < suggestedLoads; i++) {
                  _loads.add(_LoadEntry(
                    category: category,
                    initialWeight: weightPerLoad.toStringAsFixed(1),
                  ));
                }
              });
            },
            child: const Text('Auto-Split'),
          ),
        ],
      ),
    );
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

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.softGray.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildProgressStep(1, 'Customer', _isStep1Complete),
          Expanded(child: _buildProgressConnector(_isStep1Complete)),
          _buildProgressStep(2, 'Laundry', _isStep2Complete),
          Expanded(child: _buildProgressConnector(_isStep2Complete)),
          _buildProgressStep(3, 'Add-ons', false),
        ],
      ),
    );
  }

  Widget _buildProgressStep(int stepNumber, String label, bool isComplete) {
    Color color;
    if (isComplete) {
      color = Colors.green;
    } else if (stepNumber <= 2 || (stepNumber == 3 && _isStep2Complete)) {
      color = AppTheme.accentBlue;
    } else {
      color = AppTheme.textLight.withValues(alpha: 0.3);
    }

    return SizedBox(
      width: 60,
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isComplete ? Colors.green : Colors.transparent,
              border: Border.all(color: color, width: 2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isComplete 
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : Text(
                    '$stepNumber',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressConnector(bool isComplete) {
    return Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: isComplete ? Colors.green : AppTheme.borderGray,
        borderRadius: BorderRadius.circular(1),
      ),
    );
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
    _addressController.dispose();
    _landmarkController.dispose();
    _instructionsController.dispose();
    _notesController.dispose();
    for (var load in _loads) {
      load.dispose();
    }
    super.dispose();
  }

  Future<void> _submitOrder({required bool isPaidImmediately, String? paymentMethod}) async {
    // Prevent duplicate submissions
    if (_isSubmitting) return;
    
    // Validation 1: RFID Tag
    final availableTags = MockDataService().availableRfidTags;
    if (_selectedRfidTag == null || availableTags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an RFID tag before confirming.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validation 2: Customer name
    if (_customerFullName.trim().isEmpty || _customerFullName == 'Walk-in Customer') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter customer name (first and/or last name).'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validation 3: Delivery address for delivery orders
    if (_selectedReturn == ReturnMethod.delivery && _addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a delivery address for delivery orders.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validation 4: At least one load
    if (_loads.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one load.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validation 5: All loads must have valid weight
    for (int i = 0; i < _loads.length; i++) {
      final weight = _getLoadWeight(i);
      if (weight <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Load ${i + 1} must have a weight greater than 0.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      
      // Warning for very high weights (possible typo)
      if (weight > 50) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm Weight'),
            content: Text('Load ${i + 1} has ${weight}kg. Is this correct? This seems unusually high.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
        
        if (confirmed != true) return;
      }
    }

    // Start loading
    setState(() {
      _isSubmitting = true;
    });

    try {
      // Step 1: Create customer
      print('🔄 Creating customer...');
      
      // Split customer name into first and last name
      final nameParts = _customerFullName.trim().split(' ');
      final firstName = nameParts.first;
      final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : null;
      
      final customerId = await _customerService.createCustomer(
        firstName: firstName,
        lastName: lastName,
        phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
        email: null, // Email not collected in walk-in flow
        address: _selectedReturn == ReturnMethod.delivery ? _addressController.text.trim() : null,
        landmark: _selectedReturn == ReturnMethod.delivery ? _landmarkController.text.trim() : null,
      );
      
      print('✅ Customer created: $customerId');

      // Step 2: Get service and pricing information
      print('🔄 Loading service catalog...');
      
      // Debug: Test connection first
      await _catalogService.testConnection();
      
      final service = await _catalogService.getFullService();
      final serviceId = service['id'] as String;
      final serviceName = service['service_name'] as String;
      final basePrice = (service['base_price'] as num).toDouble();

      // Step 3: Get add-ons if selected
      final List<Map<String, dynamic>> addons = [];
      
      if (_addExtraFabCon) {
        final fabConAddon = await _catalogService.getAddonByName('Extra Fab Con');
        addons.add({
          'addon_id': fabConAddon['id'],
          'addon_name': fabConAddon['addon_name'],
          'quantity': 1,
          'unit_price': (fabConAddon['price'] as num).toDouble(),
          'line_total': (fabConAddon['price'] as num).toDouble(),
        });
      }
      
      if (_addExtraDetergent) {
        final detergentAddon = await _catalogService.getAddonByName('Extra Detergent');
        addons.add({
          'addon_id': detergentAddon['id'],
          'addon_name': detergentAddon['addon_name'],
          'quantity': 1,
          'unit_price': (detergentAddon['price'] as num).toDouble(),
          'line_total': (detergentAddon['price'] as num).toDouble(),
        });
      }

      // Step 4: Create OrderLoad objects
      final List<OrderLoad> orderLoads = [];
      for (int i = 0; i < _loads.length; i++) {
        final load = _loads[i];
        final category = load.category;
        final weight = _getLoadWeight(i);
        final limit = _categories[category]!['limit'] as double;
        final unit = _categories[category]!['unit'] as String;
        final desc = _categories[category]!['desc'] as String;
        
        orderLoads.add(OrderLoad(
          loadNumber: i + 1,
          category: category,
          weight: weight,
          categoryLimit: limit,
          unit: unit,
          description: desc,
          isOverLimit: weight > limit,
          notes: null,
        ));
      }

      // Step 5: Calculate totals
      final subtotal = (basePrice * _loads.length) + addons.fold(0.0, (sum, addon) => sum + (addon['line_total'] as double));
      final totalAmount = subtotal; // delivery_fee is always 0

      // Step 6: Build customer notes
      final String? customerNotes = _instructionsController.text.trim().isNotEmpty 
          ? _instructionsController.text.trim() 
          : null;

      // Step 7: Build staff notes with order details
      final String staffNotes = [
        if (_loads.length > 1) '${_loads.length} loads: ${orderLoads.map((l) => '${l.weight}${l.unit} ${l.category}').join(', ')}',
        if (_loads.length == 1) 'Load: ${orderLoads[0].weight}${orderLoads[0].unit} ${orderLoads[0].category}',
        if (_selectedReturn == ReturnMethod.delivery && _addressController.text.trim().isNotEmpty)
          'Delivery Address: ${_addressController.text.trim()}${_landmarkController.text.trim().isNotEmpty ? ' (Landmark: ${_landmarkController.text.trim()})' : ''}',
        if (_addExtraFabCon) 'Extra Fab Con (+₱20)',
        if (_addExtraDetergent) 'Extra Detergent (+₱20)',
      ].join(' | ');

      // Step 8: Generate order number
      print('🔄 Generating order number...');
      final orderNumber = await _orderService.generateOrderNumber();
      print('✅ Order number: $orderNumber');

      // Step 9: Get current staff ID from auth
      final currentUser = SupabaseService.currentUser;
      String? assignedStaffId;
      
      if (currentUser != null) {
        // Get staff profile_id from profiles table
        final profile = await SupabaseService.client
            .from('profiles')
            .select('id')
            .eq('supabase_user_id', currentUser.id)
            .maybeSingle();
        
        if (profile != null) {
          // Get employee record
          final employee = await SupabaseService.client
              .from('employees')
              .select('id')
              .eq('profile_id', profile['id'])
              .maybeSingle();
          
          if (employee != null) {
            assignedStaffId = employee['id'] as String;
          }
        }
      }

      // Step 10: Create order in database
      print('🔄 Creating order in database...');
      final orderId = await _orderService.createOrder(
        customerId: customerId,
        orderNumber: orderNumber,
        serviceId: serviceId,
        serviceName: serviceName,
        loads: orderLoads,
        subtotal: subtotal,
        totalAmount: totalAmount,
        assignedStaffId: assignedStaffId,
        pickupRequested: false, // Walk-in orders don't need pickup
        deliveryRequested: _selectedReturn == ReturnMethod.delivery,
        deliveryAddress: _selectedReturn == ReturnMethod.delivery ? _addressController.text.trim() : null,
        deliveryLandmark: _selectedReturn == ReturnMethod.delivery ? _landmarkController.text.trim() : null,
        customerNotes: customerNotes,
        staffNotes: staffNotes.isNotEmpty ? staffNotes : null,
        rfidTag: _selectedRfidTag,
        addons: addons,
        isPaid: isPaidImmediately,
        paymentMethod: paymentMethod,
      );
      
      print('✅ Order created: $orderId');

      print('✅ Order created: $orderId');

      setState(() {
        _isSubmitting = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPaidImmediately
                ? 'Order $orderNumber Created! ₱${totalAmount.toStringAsFixed(2)} paid via $paymentMethod.'
                : 'Order $orderNumber Created! Saved as UNPAID (to pay on claiming).',
          ),
          backgroundColor: isPaidImmediately ? Colors.green : AppTheme.accentBlue,
          duration: const Duration(seconds: 3),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      setState(() {
        _isSubmitting = false;
      });

      if (!mounted) return;

      print('❌ Error creating order: $e');
      
      // Parse error for user-friendly messages
      String errorMessage = 'Error creating order';
      
      if (e.toString().contains('connection')) {
        errorMessage = 'Connection error. Please check your internet and try again.';
      } else if (e.toString().contains('permission') || e.toString().contains('denied')) {
        errorMessage = 'Access denied. Please contact your administrator.';
      } else if (e.toString().contains('service_catalog') || e.toString().contains('service not found')) {
        errorMessage = 'Service configuration error. Please contact support.';
      } else if (e.toString().contains('addon')) {
        errorMessage = 'Add-on configuration error. Please try without add-ons or contact support.';
      } else if (e.toString().contains('duplicate') || e.toString().contains('unique')) {
        errorMessage = 'Duplicate order detected. Please refresh and try again.';
      } else {
        // Show partial error details for debugging
        final errorStr = e.toString();
        if (errorStr.length > 100) {
          errorMessage = 'Error: ${errorStr.substring(0, 100)}...';
        } else {
          errorMessage = 'Error: $errorStr';
        }
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () {
              _submitOrder(
                isPaidImmediately: isPaidImmediately,
                paymentMethod: paymentMethod,
              );
            },
          ),
        ),
      );
    }
  }

  void _showPaymentMethodModal() {
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
                  const Text('Confirm Payment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Amount:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    Text('₱${_finalTotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('Payment Method', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setModalState(() => method = 'Cash'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: method == 'Cash' ? Colors.green.withValues(alpha: 0.1) : AppTheme.softGray,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: method == 'Cash' ? Colors.green : AppTheme.borderGray,
                            width: method == 'Cash' ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.money,
                              size: 32,
                              color: method == 'Cash' ? Colors.green : AppTheme.textLight,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Cash',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: method == 'Cash' ? Colors.green : AppTheme.textDark,
                              ),
                            ),
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
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: method == 'GCash' ? Colors.green.withValues(alpha: 0.1) : AppTheme.softGray,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: method == 'GCash' ? Colors.green : AppTheme.borderGray,
                            width: method == 'GCash' ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.account_balance_wallet,
                              size: 32,
                              color: method == 'GCash' ? Colors.green : AppTheme.textLight,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'GCash',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: method == 'GCash' ? Colors.green : AppTheme.textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : () {
                    Navigator.pop(ctx);
                    _submitOrder(isPaidImmediately: true, paymentMethod: method);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isSubmitting 
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Confirm Payment',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textLight)),
                ),
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
            // Progress indicator
            _buildProgressIndicator(),
            const SizedBox(height: 20),
            
            // 1. Customer Section (Step 1)
            _buildCustomerSection(),
            const SizedBox(height: 14),

            // 2. Laundry & Intake Section (Step 2)
            _buildLaundryIntakeSection(availableTags, hasRfidSelected),
            const SizedBox(height: 14),
            
            // 3. Add-ons & Notes Section (Step 3)
            _buildAddOnsSection(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerSection() {
    final isExpanded = _expandedStep == 1;
    
    return Container(
      decoration: AppStyles.cardDecoration.copyWith(
        border: Border.all(
          color: isExpanded ? AppTheme.accentBlue.withValues(alpha: 0.3) : AppTheme.borderGray, 
          width: isExpanded ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Header - always visible and clickable
          InkWell(
            onTap: () => setState(() => _expandedStep = isExpanded ? null : 1),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Step indicator
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _isStep1Complete 
                        ? Colors.green.withValues(alpha: 0.12)
                        : AppTheme.accentBlue.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: _isStep1Complete
                      ? const Icon(Icons.check, size: 16, color: Colors.green)
                      : const Text('1', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
                  ),
                  const SizedBox(width: 12),
                  
                  // Title and summary
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Customer Details',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                        ),
                        if (!isExpanded && _isStep1Complete) ...[
                          const SizedBox(height: 2),
                          Text(
                            _customerFullName + (_phoneController.text.trim().isNotEmpty 
                              ? ' • ${_phoneController.text.trim()}' 
                              : ''),
                            style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  
                  // Status indicators
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isStep1Complete)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Complete',
                              style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      const SizedBox(width: 8),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: AppTheme.textLight,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Content - expandable
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer suggestion banner
                  if (_suggestedCustomer != null && !_dismissedSuggestion)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildCustomerSuggestionBanner(_suggestedCustomer!),
                    ),

                  // Form fields
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
                  const SizedBox(height: 10),
                  CustomTextField(
                    label: 'Phone Number (Optional)',
                    hint: '09XX-XXX-XXXX',
                    prefixIcon: Icons.phone_android,
                    controller: _phoneController,
                  ),
                ],
              ),
            ),
          ],
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
    final isExpanded = _expandedStep == 2;
    
    // Always accessible - no locked state
    return Container(
      decoration: AppStyles.cardDecoration.copyWith(
        border: Border.all(
          color: isExpanded ? AppTheme.accentBlue.withValues(alpha: 0.3) : AppTheme.borderGray,
          width: isExpanded ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Header - always visible and clickable
          InkWell(
            onTap: () => setState(() => _expandedStep = isExpanded ? null : 2),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Step indicator
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _isStep2Complete
                          ? Colors.green.withValues(alpha: 0.12)
                          : AppTheme.accentBlue.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: _isStep2Complete
                        ? const Icon(Icons.check, size: 16, color: Colors.green)
                        : const Text('2', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
                  ),
                  const SizedBox(width: 12),

                  // Title and summary
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Laundry & Intake',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                        ),
                        if (!isExpanded && _isStep2Complete) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${_loads.length} load(s) • ${_totalWeight.toStringAsFixed(1)}kg • Tag: $_selectedRfidTag',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Status indicators
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isStep2Complete)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Complete',
                              style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      const SizedBox(width: 8),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: AppTheme.textLight,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Content - expandable
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Multiple loads
                  ...List.generate(_loads.length, (index) => _buildLoadCard(index)),

                  // Add Load Button - Right Aligned
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _addLoad,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Another Load', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          side: BorderSide(color: AppTheme.accentBlue.withValues(alpha: 0.5)),
                        ),
                      ),
                    ],
                  ),

                  const Divider(height: 24),

                  // Total Weight Summary
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.accentBlue.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Weight:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('${_totalWeight.toStringAsFixed(1)}kg across ${_loads.length} load(s)',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.accentBlue)),
                      ],
                    ),
                  ),

                  const Divider(height: 24),

                  // RFID Tag Assignment Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.nfc_outlined, size: 16, color: AppTheme.accentBlue),
                          SizedBox(width: 6),
                          Text(
                            'RFID Tag Assignment (Shared)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: availableTags.isEmpty
                              ? AppTheme.errorRed.withValues(alpha: 0.1)
                              : AppTheme.accentBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${availableTags.length} Available',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: availableTags.isEmpty ? AppTheme.errorRed : AppTheme.accentBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedRfidTag,
                    hint: const Text('Select RFID Tag', style: TextStyle(fontSize: 13)),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.borderGray),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.accentBlue, width: 2),
                      ),
                    ),
                    items: availableTags.map((tag) {
                      return DropdownMenuItem(value: tag, child: Text(tag, style: const TextStyle(fontSize: 13)));
                    }).toList(),
                    onChanged: availableTags.isEmpty ? null : (value) => setState(() => _selectedRfidTag = value),
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
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadCard(int index) {
    final load = _loads[index];
    final isOver = _isLoadOverLimit(index);
    final weight = _getLoadWeight(index);
    final limit = _getLoadLimit(index);
    final unit = _categories[load.category]!['unit'] as String;
    final categoriesList = _categories.entries.toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.softGray.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Load ${index + 1} of ${_loads.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
              if (_loads.length > 1)
                InkWell(
                  onTap: () => _removeLoad(index),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.close, size: 16, color: Colors.red),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Category Selection - Compact Grid
          const Text('Category:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLight)),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 2.2,
            children: [
              _buildCompactCategoryTile(categoriesList[0], load, index),
              _buildCompactCategoryTile(categoriesList[1], load, index),
              _buildCompactCategoryTile(categoriesList[2], load, index),
              _buildCompactCategoryTile(categoriesList[3], load, index),
            ],
          ),

          const SizedBox(height: 10),

          // Weight Input with Status - Compact Design
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Weight:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: load.weightController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: '5.0',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.borderGray),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.accentBlue, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                unit,
                style: const TextStyle(fontSize: 13, color: AppTheme.textLight, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              // Status indicator
              if (weight > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isOver ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isOver ? Colors.red : Colors.green, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isOver ? Icons.warning_amber_rounded : Icons.check_circle,
                        size: 14,
                        color: isOver ? Colors.red : Colors.green,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isOver ? 'Over' : 'OK',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isOver ? Colors.red : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          if (isOver) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Exceeds ${limit.toStringAsFixed(1)} $unit limit by ${(weight - limit).toStringAsFixed(1)} $unit',
                    style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.w500),
                  ),
                ),
                TextButton(
                  onPressed: () => _showAutoSplitDialog(index),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Auto-Split', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactCategoryTile(MapEntry<String, Map<String, dynamic>> entry, _LoadEntry load, int loadIndex) {
    final isSelected = load.category == entry.key;

    return InkWell(
      onTap: () => setState(() => load.category = entry.key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentBlue.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.accentBlue : AppTheme.borderGray.withValues(alpha: 0.4),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            entry.key,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isSelected ? AppTheme.accentBlue : AppTheme.textDark,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
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

  Widget _buildAddOnsSection() {
    final isExpanded = _expandedStep == 3;
    
    // Always accessible - no locked state
    return Container(
      decoration: AppStyles.cardDecoration.copyWith(
        border: Border.all(
          color: isExpanded ? AppTheme.accentBlue.withValues(alpha: 0.3) : AppTheme.borderGray,
          width: isExpanded ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Header - always visible and clickable
          InkWell(
            onTap: () => setState(() => _expandedStep = isExpanded ? null : 3),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Step indicator
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.accentBlue.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Text('3', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
                  ),
                  const SizedBox(width: 12),

                  // Title and summary
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Add-ons & Notes',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                        ),
                        if (!isExpanded && (_addExtraFabCon || _addExtraDetergent)) ...[
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (_addExtraFabCon) 'Extra Fabric Conditioner',
                              if (_addExtraDetergent) 'Extra Detergent',
                            ].join(' • '),
                            style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Status indicators
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_addExtraFabCon || _addExtraDetergent)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '+₱${(_addExtraFabCon ? 20 : 0) + (_addExtraDetergent ? 20 : 0)}',
                            style: const TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: AppTheme.textLight,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Content - expandable
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Add-ons Section
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.softGray.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Optional Add-ons',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                        ),
                        const SizedBox(height: 8),

                        // Extra Fabric Conditioner
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _addExtraFabCon,
                          onChanged: (value) => setState(() => _addExtraFabCon = value ?? false),
                          title: const Text('Extra Fabric Conditioner', style: TextStyle(fontSize: 13)),
                          subtitle: const Text('+₱20.00',
                              style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: AppTheme.accentBlue,
                        ),

                        // Extra Detergent
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _addExtraDetergent,
                          onChanged: (value) => setState(() => _addExtraDetergent = value ?? false),
                          title: const Text('Extra Detergent', style: TextStyle(fontSize: 13)),
                          subtitle: const Text('+₱20.00',
                              style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: AppTheme.accentBlue,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Order Notes Section
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Order Notes & Instructions',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _notesController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Special instructions, preferences, or notes...',
                          hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textLight),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: AppTheme.borderGray),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: AppTheme.accentBlue, width: 2),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Final Pricing Summary
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.2), width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.receipt_outlined, size: 16, color: Colors.green),
                            SizedBox(width: 6),
                            Text(
                              'Final Pricing Summary',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Base price
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Laundry (${_loads.length} load${_loads.length > 1 ? 's' : ''}):', style: const TextStyle(fontSize: 13)),
                            Text('₱${(170 * _loads.length).toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),

                        // Add-ons
                        if (_addExtraFabCon || _addExtraDetergent) ...[
                          const SizedBox(height: 4),
                          if (_addExtraFabCon)
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Extra Fabric Conditioner:', style: TextStyle(fontSize: 13)),
                                Text('₱20.00', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          if (_addExtraDetergent)
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Extra Detergent:', style: TextStyle(fontSize: 13)),
                                Text('₱20.00', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              ],
                            ),
                        ],

                        const Divider(height: 16),

                        // Total
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Amount:',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                            Text('₱${_calculateTotalPrice().toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStickyBottomBar(List<String> availableTags) {
    final bool canSubmit = _isStep1Complete && _isStep2Complete;

    // Only show submit options when all requirements are met
    if (!canSubmit) {
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
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline, size: 12, color: Colors.orange.shade800),
                    const SizedBox(width: 4),
                    Text(
                      !_isStep1Complete 
                        ? 'Complete customer details to continue'
                        : !_isStep2Complete
                        ? 'Complete laundry details to enable order creation'
                        : 'All requirements met',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade800),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

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
            // Order summary
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.nfc, size: 12, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        'RFID: $_selectedRfidTag • ${_loads.length} load(s) • ${_totalWeight.toStringAsFixed(1)}kg',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                  Text(
                    '₱${_calculateTotalPrice().toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                ],
              ),
            ),
            
            // Payment Buttons Row
            Row(
              children: [
                // Pay Later Button
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : () => _submitOrder(isPaidImmediately: false, paymentMethod: null),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentBlue,
                      side: const BorderSide(color: AppTheme.accentBlue, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: AppTheme.accentBlue,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Pay Later',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                // Pay Now Button
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _showPaymentMethodModal,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Pay Now',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
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
