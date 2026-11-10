import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/location_constants.dart';
import '../../../utils/app_error.dart';
import '../../../utils/input_formatters.dart';
import '../../../utils/validators.dart';
import '../../../widgets/location_picker_widget.dart';
import '../../../widgets/address_input_widget.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/custom_text_field.dart';
import '../../../models/order.dart';
import '../../../models/laundry_intake.dart';
import '../../../services/customer_service.dart';
import '../../../services/service_catalog_service.dart';
import '../../../services/order_service.dart';
import '../../../services/loyalty_service.dart';
import '../../../services/payment_service.dart';
import '../../../services/supabase_service.dart';
import '../../shared/gcash_qr_payment_screen.dart';

class _CustomerProfile {
  final String? customerId;
  final String firstName;
  final String lastName;
  final String phone;
  final ReturnMethod returnMethod;
  final String? address;
  final String? landmark;
  final String? instructions;
  final DateTime? lastOrderDate;
  final double? pinLatitude;
  final double? pinLongitude;

  const _CustomerProfile({
    this.customerId,
    required this.firstName,
    required this.lastName,
    required this.phone,
    this.returnMethod = ReturnMethod.shopPickup,
    this.address,
    this.landmark,
    this.instructions,
    this.lastOrderDate,
    this.pinLatitude,
    this.pinLongitude,
  });

  String get fullName => '$firstName $lastName'.trim();

  /// Create from database JSON
  factory _CustomerProfile.fromJson(Map<String, dynamic> json) {
    // Parse return method from last order
    ReturnMethod returnMethod = ReturnMethod.shopPickup;
    final lastOrder = json['last_order'] as Map<String, dynamic>?;
    if (lastOrder != null && lastOrder['delivery_requested'] != null) {
      final deliveryRequested = lastOrder['delivery_requested'] as bool;
      returnMethod = deliveryRequested ? ReturnMethod.delivery : ReturnMethod.shopPickup;
    }

    return _CustomerProfile(
      customerId: json['id'] as String?,
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      returnMethod: returnMethod,
      address: json['address'] as String?,
      landmark: json['landmark'] as String?,
      instructions: lastOrder?['customer_notes'] as String?,
      lastOrderDate: json['last_order_date'] != null 
          ? DateTime.tryParse(json['last_order_date'] as String)
          : null,
      pinLatitude: (json['pin_latitude'] as num?)?.toDouble(),
      pinLongitude: (json['pin_longitude'] as num?)?.toDouble(),
    );
  }
}

enum _SuggestionType {
  none,        // No matches or search not triggered
  confident,   // 1-3 matches - show all
  uncertain,   // 4-10 matches - show with warning
  tooMany,     // >10 matches - show helpful prompt only
}

class CreateOrderFlow extends StatefulWidget {
  final LaundryOrder? orderToEdit;
  const CreateOrderFlow({super.key, this.orderToEdit});

  @override
  State<CreateOrderFlow> createState() => _CreateOrderFlowState();
}

class _CreateOrderFlowState extends State<CreateOrderFlow> {
  bool get _isEditing => widget.orderToEdit != null;
  // Services
  final CustomerService _customerService = CustomerService();
  final ServiceCatalogService _catalogService = ServiceCatalogService();
  final OrderService _orderService = OrderService();
  final LoyaltyService _loyaltyService = LoyaltyService();

  // Loyalty card controller (manual entry / NFC tap)
  final TextEditingController _loyaltyCardController = TextEditingController();
  RealtimeChannel? _rfidScanChannel;

  // Form controllers
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  
  // Separated Address Controllers & 20m Meetup Zone
  final TextEditingController _houseStreetController = TextEditingController();
  String? _selectedBarangay;
  final TextEditingController _customBarangayController = TextEditingController();
  final TextEditingController _landmarkController = TextEditingController();
  LatLng? _deliveryPinLocation;


  final TextEditingController _instructionsController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  String get _fullDeliveryAddress => AddressInputWidget.buildFullAddress(
    houseStreet: _houseStreetController.text.trim(),
    selectedBarangay: _selectedBarangay,
    customBarangay: _customBarangayController.text.trim(),
  );

  void _parseAndSetCustomerAddress(String address) {
    AddressInputWidget.parseAndPopulate(
      address: address,
      houseStreetController: _houseStreetController,
      setBarangay: (v) => _selectedBarangay = v,
      customBarangayController: _customBarangayController,
    );
  }

  Future<void> _openPinLocationPicker() async {
    final result = await LocationPickerDialog.show(
      context,
      initialPosition: _deliveryPinLocation,
      enforceDeliveryRadius: true,
      title: 'Pin 20m Meetup Zone',
    );

    if (result != null && mounted) {
      setState(() {
        _deliveryPinLocation = result.coordinates;

        if (_houseStreetController.text.trim().isEmpty && result.address != null) {
          _parseAndSetCustomerAddress(result.address!);
          if (_houseStreetController.text.trim().isEmpty) {
            _houseStreetController.text = 'Blk _ Lot _';
            _houseStreetController.selection = const TextSelection(baseOffset: 4, extentOffset: 5);
          } else if (!_houseStreetController.text.startsWith('Blk')) {
            _houseStreetController.text = 'Blk _ Lot _, ${_houseStreetController.text}';
            _houseStreetController.selection = const TextSelection(baseOffset: 4, extentOffset: 5);
          }
        }
      });
    }
  }

  // State variables
  CollectionMethod _selectedCollection = CollectionMethod.dropOff; // Pickup or drop-off
  ReturnMethod _selectedReturn = ReturnMethod.shopPickup;

  // Loyalty card state (optional — customer may not have a card yet)
  String? _loyaltyCardUid;       // Raw UID from scan / manual entry
  LoyaltyCardInfo? _loyaltyCardInfo; // Looked-up card data (null if not found / not scanned)
  bool _lookingUpCard = false;
  int _loyaltyLookupRequest = 0;
  String? _lastRealtimeUid;
  DateTime? _lastRealtimeScanAt;

  bool _addExtraFabCon = false;
  bool _addExtraDetergent = false;
  bool _isSubmitting = false; // Loading state for order creation

  // Section expansion state - only one can be expanded at a time (accordion behavior)
  int? _expandedStep = 1;  // null = all collapsed, 1/2/3 = that step expanded

  // Scroll controller & section keys for auto-scroll on expand
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _step1Key = GlobalKey();
  final GlobalKey _step2Key = GlobalKey();
  final GlobalKey _step3Key = GlobalKey();

  // Customer suggestion state
  List<_CustomerProfile> _suggestedCustomers = []; // Changed to list for multiple matches
  _SuggestionType _suggestionType = _SuggestionType.none;
  String? _suggestionMessage;
  bool _dismissedSuggestion = false;
  String? _dismissedQuery;
  Timer? _searchDebounce;
  String? _acceptedCustomerId; // Track if staff accepted an existing customer
  
  // Match thresholds
  static const int _showAllThreshold = 3;      // Show all if ≤3 matches
  static const int _showWithWarningThreshold = 10;  // Show with warning if ≤10 matches
  // If >10 matches, just show prompt

  // Multiple loads support
  final List<LoadDraft> _loads = [];

  @override
  void initState() {
    super.initState();

    if (widget.orderToEdit != null) {
      final o = widget.orderToEdit!;
      _acceptedCustomerId = o.customerId;

      // Customer name
      final parts = o.customerName.trim().split(' ');
      if (parts.isNotEmpty) {
        _firstNameController.text = parts.first;
        if (parts.length > 1) {
          _lastNameController.text = parts.sublist(1).join(' ');
        }
      }
      if (o.customerPhone != null && o.customerPhone!.isNotEmpty) {
        _phoneController.text = o.customerPhone!;
      }

      // Logistics
      _selectedCollection = o.collectionMethod;
      _selectedReturn = o.returnMethod;
      if (o.deliveryAddress != null && o.deliveryAddress!.isNotEmpty) {
        _parseAndSetCustomerAddress(o.deliveryAddress!);
      }
      if (o.deliveryLandmark != null) {
        _landmarkController.text = o.deliveryLandmark!;
      }
      if (o.instructions != null) {
        _instructionsController.text = o.instructions!;
      }
      if (o.staffMessage != null) {
        _notesController.text = o.staffMessage!;
      }

      // Loads
      if (o.loads.isNotEmpty) {
        for (final load in o.loads) {
          _loads.add(LoadDraft(
            category: load.category,
            initialWeight: load.weight > 0 ? load.weight.toString() : '',
          ));
        }
      } else if (_selectedCollection == CollectionMethod.dropOff) {
        _loads.add(LoadDraft(initialWeight: ''));
      }

      // Addons
      _loadOrderAddonsForEdit(o.id);
    } else {
      // Initialize with one load only if drop-off is selected (default)
      // For rider pickup, loads will be empty until staff checks in the order
      if (_selectedCollection == CollectionMethod.dropOff) {
        _loads.add(LoadDraft(initialWeight: ''));
      }
    }
    
    _firstNameController.addListener(_checkForCustomerSuggestion);
    _lastNameController.addListener(_checkForCustomerSuggestion);
    _phoneController.addListener(_checkForCustomerSuggestion);
    _subscribeToLiveRfidScans();
  }

  Future<void> _loadOrderAddonsForEdit(String orderId) async {
    try {
      final addons = await _orderService.getOrderAddons(orderId);
      if (!mounted) return;
      setState(() {
        for (final addon in addons) {
          final code = (addon['addon_code'] as String?)?.toLowerCase() ?? '';
          final name = (addon['addon_name'] as String?)?.toLowerCase() ?? '';
          if (code.contains('fabric') || name.contains('fabric') || name.contains('fab con')) {
            _addExtraFabCon = true;
          }
          if (code.contains('detergent') || name.contains('detergent')) {
            _addExtraDetergent = true;
          }
        }
      });
    } catch (e) {
      print('Could not load addons for edit: $e');
    }
  }

  void _subscribeToLiveRfidScans() {
    try {
      _rfidScanChannel = SupabaseService.client
          .channel('staff_walkin_rfid_scans')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'scanned_rfid_events',
            callback: (payload) {
              final uid = payload.newRecord['uid'];
              if (uid is! String || uid.trim().isEmpty || !mounted) return;

              final cleanUid = uid.trim().toUpperCase();
              final now = DateTime.now();
              if (_lastRealtimeUid == cleanUid &&
                  _lastRealtimeScanAt != null &&
                  now.difference(_lastRealtimeScanAt!) <
                      const Duration(milliseconds: 1500)) {
                return;
              }
              _lastRealtimeUid = cleanUid;
              _lastRealtimeScanAt = now;
              _lookupLoyaltyCard(cleanUid);
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Could not listen for RFID scans in walk-in order: $e');
    }
  }

  /// Look up a loyalty card by UID and optionally auto-fill customer info.
  Future<void> _lookupLoyaltyCard(String uid) async {
    final cleanUid = uid.trim().toUpperCase();
    if (cleanUid.isEmpty) return;

    final requestId = ++_loyaltyLookupRequest;
    setState(() {
      _lookingUpCard = true;
      _loyaltyCardController.text = cleanUid;
      _loyaltyCardUid = null;
      _loyaltyCardInfo = null;
    });

    try {
      final card = await _loyaltyService.lookupCardByUid(cleanUid);
      if (!mounted || requestId != _loyaltyLookupRequest) return;

      if (card == null) {
        setState(() => _lookingUpCard = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Card UID "$cleanUid" was not found.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      Map<String, dynamic>? owner;
      if (card.customerId != null) {
        owner = await _customerService.getCustomerById(card.customerId!);
        if (!mounted || requestId != _loyaltyLookupRequest) return;
      }

      final hasCurrentCustomerData = _acceptedCustomerId != null ||
          _firstNameController.text.trim().isNotEmpty ||
          _lastNameController.text.trim().isNotEmpty ||
          _phoneController.text.trim().isNotEmpty ||
          _houseStreetController.text.trim().isNotEmpty ||
          (_selectedBarangay != null && _selectedBarangay!.isNotEmpty) ||
          _customBarangayController.text.trim().isNotEmpty ||
          _landmarkController.text.trim().isNotEmpty ||
          _deliveryPinLocation != null ||
          _instructionsController.text.trim().isNotEmpty;
      final ownerConflictsWithForm = card.isActive &&
          card.customerId != null &&
          hasCurrentCustomerData &&
          _acceptedCustomerId != card.customerId;

      if (ownerConflictsWithForm) {
        final useCardOwner = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Use loyalty card customer?'),
            content: Text(
              'This card belongs to ${card.ownerName}. Replace the customer details and saved address currently entered in this order?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep current details'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Use card customer'),
              ),
            ],
          ),
        );
        if (!mounted || requestId != _loyaltyLookupRequest) return;
        if (useCardOwner != true) {
          setState(() => _lookingUpCard = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Card was not linked to this order.')),
          );
          return;
        }
      }

      setState(() {
        _loyaltyCardInfo = card;
        _loyaltyCardUid = cleanUid;
        _lookingUpCard = false;

        if (card.isActive && card.customerId != null) {
          _applyLoyaltyCardOwner(card, owner);
        }
      });

      if (!card.isActive) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This loyalty card is inactive.')),
        );
      } else if (!card.hasOwner) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Card found, but it has no customer assigned yet.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error looking up loyalty card: $e');
      if (!mounted || requestId != _loyaltyLookupRequest) return;
      setState(() {
        _lookingUpCard = false;
        _loyaltyCardUid = null;
        _loyaltyCardInfo = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mapErrorToMessage(e))),
      );
    }
  }

  void _applyLoyaltyCardOwner(
    LoyaltyCardInfo card,
    Map<String, dynamic>? owner,
  ) {
    _searchDebounce?.cancel();
    _dismissedSuggestion = true;
    final firstName = (owner?['first_name'] as String?)?.trim() ?? '';
    final lastName = (owner?['last_name'] as String?)?.trim() ?? '';
    final cardNameParts = card.ownerName.trim().split(RegExp(r'\s+'));
    _firstNameController.text = firstName.isNotEmpty
        ? firstName
        : (cardNameParts.isNotEmpty ? cardNameParts.first : '');
    _lastNameController.text = lastName.isNotEmpty
        ? lastName
        : (cardNameParts.length > 1 ? cardNameParts.skip(1).join(' ') : '');
    _phoneController.text =
        (owner?['phone'] as String?) ?? card.ownerPhone ?? '';
    _acceptedCustomerId = card.customerId;

    final address = (owner?['address'] as String?)?.trim() ?? '';
    if (address.isNotEmpty) {
      _parseAndSetCustomerAddress(address);
    } else {
      _houseStreetController.clear();
      _customBarangayController.clear();
      _selectedBarangay = null;
    }
    _landmarkController.text = (owner?['landmark'] as String?) ?? '';
    _deliveryPinLocation = _latLngFromCustomer(owner);

    _suggestedCustomers = [];
    _suggestionType = _SuggestionType.none;
    _suggestionMessage = null;
    _dismissedQuery =
        '${_firstNameController.text}|${_lastNameController.text}|${_phoneController.text}';
  }

  LatLng? _latLngFromCustomer(Map<String, dynamic>? customer) {
    final latitude = customer?['pin_latitude'];
    final longitude = customer?['pin_longitude'];
    if (latitude is num && longitude is num) {
      return LatLng(latitude.toDouble(), longitude.toDouble());
    }
    return null;
  }

  void _clearLoyaltyCard() {
    _loyaltyLookupRequest++;
    setState(() {
      _loyaltyCardUid = null;
      _loyaltyCardInfo = null;
      _lookingUpCard = false;
      _loyaltyCardController.clear();
    });
  }

  Map<String, Map<String, dynamic>> get _categories => LaundryIntake.categories;

  static const double _basePricePerLoad = LaundryIntake.basePricePerLoad;
  double get _addOnsTotal =>
      (_addExtraFabCon ? LaundryIntake.addonPrice : 0.0) +
          (_addExtraDetergent ? LaundryIntake.addonPrice : 0.0);
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
    // For rider pickup orders, step 2 is complete if address is provided
    if (_selectedCollection == CollectionMethod.riderPickup) {
      final brgyValid = _selectedBarangay != null &&
          (_selectedBarangay != 'Other / Outside Sta. Cruz' ||
              _customBarangayController.text.trim().isNotEmpty);
      return _houseStreetController.text.trim().isNotEmpty && brgyValid;
    }
    
    // For drop-off orders, require loads with weights
    final brgyValid = _selectedBarangay != null &&
        (_selectedBarangay != 'Other / Outside Sta. Cruz' ||
            _customBarangayController.text.trim().isNotEmpty);
    return _loads.isNotEmpty &&
        _loads.length <= LaundryIntake.maxLoadsLimit &&
        _loads.every((load) => _getLoadWeight(_loads.indexOf(load)) > 0) &&
        (_selectedReturn != ReturnMethod.delivery || 
         (_houseStreetController.text.trim().isNotEmpty && brgyValid));
  }

  void _addLoad() {
    if (_loads.length >= LaundryIntake.maxLoadsLimit) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
              SizedBox(width: 8),
              Text('Load Limit Reached', style: TextStyle(fontSize: 17)),
            ],
          ),
          content: const Text(
            'Only 25 split loads limit per order.',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() {
      _loads.add(LoadDraft());
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
    final int resultingTotalLoads = (_loads.length - 1) + suggestedLoads;

    if (resultingTotalLoads > LaundryIntake.maxLoadsLimit) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
              SizedBox(width: 8),
              Text('Split Limit Exceeded', style: TextStyle(fontSize: 17)),
            ],
          ),
          content: Text(
            'Only 25 split loads limit. This order will lead to $resultingTotalLoads loads if split.',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

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
              if ((_loads.length - 1 + suggestedLoads) > LaundryIntake.maxLoadsLimit) {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
                        SizedBox(width: 8),
                        Text('Split Limit Exceeded', style: TextStyle(fontSize: 17)),
                      ],
                    ),
                    content: const Text(
                      'Only 25 split loads limit per order.',
                      style: TextStyle(fontSize: 14),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
                return;
              }
              setState(() {
                // Update current load with first split
                _loads[loadIndex].weightController.text = weightPerLoad.toStringAsFixed(1);
                // Add additional loads
                for (int i = 1; i < suggestedLoads; i++) {
                  _loads.add(LoadDraft(
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
    // Cancel previous search timer
    _searchDebounce?.cancel();

    // Check if input changed from the previously dismissed query
    final curFirst = _firstNameController.text.trim();
    final curLast = _lastNameController.text.trim();
    final curPhone = _phoneController.text.trim();
    final currentQuery = '$curFirst|$curLast|$curPhone';

    if (_dismissedQuery != null && _dismissedQuery != currentQuery) {
      _dismissedSuggestion = false;
      _dismissedQuery = null;
    }

    // If suggestion was already dismissed for this exact query, don't search again
    if (_dismissedSuggestion) return;

    // Debounce the search to avoid excessive database queries
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final firstName = _firstNameController.text.trim();
        final lastName = _lastNameController.text.trim();
        final phone = _phoneController.text.trim();

        // Require minimum characters
        final hasValidFirstName = firstName.length >= 2;
        final hasValidLastName = lastName.length >= 2;
        final hasValidPhone = phone.length >= 4;

        if (!hasValidFirstName && !hasValidLastName && !hasValidPhone) {
          // Clear suggestion if query too short
          if (!mounted) return; // Add mounted check
          if (_suggestionType != _SuggestionType.none) {
            setState(() {
              _suggestedCustomers = [];
              _suggestionType = _SuggestionType.none;
              _suggestionMessage = null;
            });
          }
          return;
        }

        final combinedName = '$firstName $lastName'.trim();

        // Search database by first name, last name, combined name, and/or phone
        final results = await _customerService.searchCustomersWithHistory(
          firstName: hasValidFirstName ? firstName : null,
          lastName: hasValidLastName ? lastName : null,
          name: combinedName.length >= 2 ? combinedName : null,
          phone: hasValidPhone ? phone : null,
        );

        if (!mounted) return;

        final matchCount = results.length;

        if (matchCount == 0) {
          // No matches found - new customer
          if (!mounted) return; // Add mounted check
          setState(() {
            _suggestedCustomers = [];
            _suggestionType = _SuggestionType.none;
            _suggestionMessage = null;
          });
          return;
        }

        // Convert results to customer profiles
        final matches = results.map((json) => _CustomerProfile.fromJson(json)).toList();

        // Normalize phone numbers for comparison
        final normalizePhone = (String? phone) {
          if (phone == null) return '';
          return phone.replaceAll(RegExp(r'[^\d]'), '');
        };

        // Check if current form data already matches first result exactly
        if (matches.isNotEmpty) {
          final firstMatch = matches.first;
          final firstNameMatches = firstName.toLowerCase() == firstMatch.firstName.toLowerCase();
          final lastNameMatches = lastName.toLowerCase() == firstMatch.lastName.toLowerCase();
          final phoneMatches = normalizePhone(phone) == normalizePhone(firstMatch.phone);

          if (firstNameMatches && lastNameMatches && phoneMatches) {
            // Already filled with this customer's data exactly
            if (!mounted) return; // Add mounted check
            setState(() {
              _suggestedCustomers = [];
              _suggestionType = _SuggestionType.none;
              _suggestionMessage = null;
            });
            return;
          }
        }

        if (!mounted) return; // Add mounted check before all setState calls

        // Apply hybrid threshold strategy
        if (matchCount <= _showAllThreshold) {
          // 1-3 matches: Show all with high confidence
          setState(() {
            _suggestedCustomers = matches;
            _suggestionType = _SuggestionType.confident;
            _suggestionMessage = matchCount == 1 
                ? 'Returning customer found'
                : '$matchCount customers found';
          });
        } else if (matchCount <= _showWithWarningThreshold) {
          // 4-10 matches: Show with warning
          setState(() {
            _suggestedCustomers = matches;
            _suggestionType = _SuggestionType.uncertain;
            _suggestionMessage = '$matchCount customers named "${combinedName.isNotEmpty ? combinedName : firstName}"';
          });
        } else {
          // >10 matches: Too many - show prompt only
          setState(() {
            _suggestedCustomers = [];
            _suggestionType = _SuggestionType.tooMany;
            _suggestionMessage = '$matchCount customers named "${combinedName.isNotEmpty ? combinedName : firstName}". '
                'Add ${lastName.isEmpty ? "last name or " : ""}phone number to narrow down.';
          });
        }
      } catch (e) {
        print('❌ Error in customer suggestion: $e');
        // Don't show error to user, just fail silently
      }
    });
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
    final linkedCardCustomerId = _loyaltyCardInfo?.customerId;
    if (linkedCardCustomerId != null &&
        linkedCardCustomerId != customer.customerId) {
      _clearLoyaltyCard();
    }

    setState(() {
      _firstNameController.text = customer.firstName;
      _lastNameController.text = customer.lastName;
      _phoneController.text = customer.phone;
      
      // IMPORTANT: Track that we're reusing this customer
      _acceptedCustomerId = customer.customerId;

      if (customer.returnMethod == ReturnMethod.delivery) {
        _selectedReturn = ReturnMethod.delivery;
      } else {
        _selectedReturn = ReturnMethod.shopPickup;
      }

      if (customer.address != null && customer.address!.isNotEmpty) {
        _parseAndSetCustomerAddress(customer.address!);
      }
      if (customer.landmark != null) {
        _landmarkController.text = customer.landmark!;
      }
      if (customer.pinLatitude != null && customer.pinLongitude != null) {
        _deliveryPinLocation = LatLng(customer.pinLatitude!, customer.pinLongitude!);
      }

      if (customer.instructions != null && customer.instructions!.isNotEmpty) {
        _instructionsController.text = customer.instructions!;
      }

      // Clear suggestions after accepting
      _suggestedCustomers = [];
      _suggestionType = _SuggestionType.none;
      _suggestionMessage = null;
      _dismissedSuggestion = true;
      _dismissedQuery = '${customer.firstName}|${customer.lastName}|${customer.phone}';
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

  void _dismissCurrentSuggestions() {
    final curFirst = _firstNameController.text.trim();
    final curLast = _lastNameController.text.trim();
    final curPhone = _phoneController.text.trim();
    setState(() {
      _suggestedCustomers = [];
      _suggestionType = _SuggestionType.none;
      _suggestionMessage = null;
      _dismissedSuggestion = true;
      _dismissedQuery = '$curFirst|$curLast|$curPhone';
    });
  }

  @override
  void dispose() {
    _rfidScanChannel?.unsubscribe();
    _searchDebounce?.cancel();
    _firstNameController.removeListener(_checkForCustomerSuggestion);
    _lastNameController.removeListener(_checkForCustomerSuggestion);
    _phoneController.removeListener(_checkForCustomerSuggestion);
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _houseStreetController.dispose();
    _customBarangayController.dispose();
    _landmarkController.dispose();
    _instructionsController.dispose();
    _notesController.dispose();
    _loyaltyCardController.dispose();
    _scrollController.dispose();
    for (var load in _loads) {
      load.dispose();
    }
    super.dispose();
  }

  void _scrollToStep(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.endOfFrame.then((_) {
        final ctx = key.currentContext;
        if (!mounted || ctx == null) return;
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          alignment: 0.0, // align top of widget to top of viewport
        );
      });
    });
  }

  Future<void> _submitOrder({
    required bool isPaidImmediately,
    String? paymentMethod,
    File? gcashReceiptFile,
  }) async {
    // Prevent duplicate submissions
    if (_isSubmitting) return;

    // GCash Pay Now with a captured receipt: the order is created without an
    // inline payment row, then PaymentService uploads the receipt and records
    // the payment as 'pending' (for review on the admin website).
    final gcashWithReceipt = paymentMethod == 'GCash' && gcashReceiptFile != null;

    // Validation 1: Customer name (required)
    if (_customerFullName.trim().isEmpty || _customerFullName == 'Walk-in Customer') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter customer name (first and/or last name).'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validation 3: Address required for pickup or delivery orders
    final hasPickupOrDelivery = _selectedCollection == CollectionMethod.riderPickup ||
        _selectedReturn == ReturnMethod.delivery;
    final brgyValid = _selectedBarangay != null &&
        (_selectedBarangay != 'Other / Outside Sta. Cruz' ||
            _customBarangayController.text.trim().isNotEmpty);

    if (hasPickupOrDelivery &&
        (_houseStreetController.text.trim().isEmpty || !brgyValid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter house/street and select a barangay for pickup/delivery.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }

    // Validation 4: Different requirements for rider pickup vs drop-off
    if (_selectedCollection == CollectionMethod.riderPickup) {
      // Rider pickup: No loads required (will be added after pickup)
      // Address validation already done above
    } else {
      // Drop-off: Require at least one load with weight
      if (_loads.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please add at least one load.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      if (_loads.length > LaundryIntake.maxLoadsLimit) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
                SizedBox(width: 8),
                Text('Load Limit Exceeded', style: TextStyle(fontSize: 17)),
              ],
            ),
            content: Text(
              'Only 25 split loads limit. This order currently has ${_loads.length} loads.',
              style: const TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      // Validation 5: All loads must have valid weight
      // Captured before any await below so snackbar calls stay lint-clean.
      final messenger = ScaffoldMessenger.of(context);
      for (int i = 0; i < _loads.length; i++) {
        final weight = _getLoadWeight(i);
        if (weight <= 0) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Load ${i + 1} must have a weight greater than 0.'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }

        // Range check for kg loads (0.1–100 kg); 'pc' loads only need > 0.
        if (LaundryIntake.unitOf(_loads[i].category) == 'kg') {
          final weightError =
              Validators.weightKg(_loads[i].weightController.text);
          if (weightError != null) {
            messenger.showSnackBar(
              SnackBar(
                content: Text('Load ${i + 1}: $weightError'),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }
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
    }

    // Start loading
    setState(() {
      _isSubmitting = true;
    });

    try {
      // Step 1: Get or create customer
      print('🔄 Getting/creating customer...');

      final String customerId;
      
      if (_acceptedCustomerId != null) {
        // Reuse existing customer that staff accepted
        customerId = _acceptedCustomerId!;
        print('✅ Reusing existing customer: $customerId');
        
        // Optionally update customer info if changed (phone, address, etc.)
        final needsUpdate = _phoneController.text.trim().isNotEmpty ||
                          (_selectedReturn == ReturnMethod.delivery && _fullDeliveryAddress.isNotEmpty);
        
        if (needsUpdate) {
          print('🔄 Updating customer info...');
          
          String? normalizedPhone;
          if (_phoneController.text.trim().isNotEmpty) {
            normalizedPhone = _customerService.normalizePhone(_phoneController.text.trim());
          }
          
          await _customerService.updateCustomer(
            customerId: customerId,
            phone: normalizedPhone,
            address: _selectedReturn == ReturnMethod.delivery ? _fullDeliveryAddress : null,
            landmark: _selectedReturn == ReturnMethod.delivery ? _landmarkController.text.trim() : null,
            pinLatitude: _deliveryPinLocation?.latitude,
            pinLongitude: _deliveryPinLocation?.longitude,
          );
          print('✅ Customer info updated');
        }
      } else {
        // Create new customer
        print('🔄 Creating new customer...');
        
        // Split customer name into first and last name
        final nameParts = _customerFullName.trim().split(' ');
        final firstName = nameParts.first;
        final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : null;

        // Normalize phone number before saving to database
        String? normalizedPhone;
        if (_phoneController.text.trim().isNotEmpty) {
          normalizedPhone = _customerService.normalizePhone(_phoneController.text.trim());
        }

        customerId = await _customerService.createCustomer(
          firstName: firstName,
          lastName: lastName,
          phone: normalizedPhone,
          email: null, // Email not collected in walk-in flow
          address: _selectedReturn == ReturnMethod.delivery ? _fullDeliveryAddress : null,
          landmark: _selectedReturn == ReturnMethod.delivery ? _landmarkController.text.trim() : null,
          pinLatitude: _deliveryPinLocation?.latitude,
          pinLongitude: _deliveryPinLocation?.longitude,
        );

        print('✅ New customer created: $customerId');
      }

      // Step 2: Get service and pricing information
      print('🔄 Loading service catalog...');

      // Debug: Test connection first
      await _catalogService.testConnection();

      final service = await _catalogService.getFullService();
      final serviceId = service['id'] as String;
      final serviceName = service['service_name'] as String;
      final basePrice = (service['base_price'] as num).toDouble();

      // Step 3: Prepare add-ons array (if selected)
      final List<Map<String, dynamic>> addons = [];
      double addonsTotal = 0.0;

      if (_addExtraFabCon) {
        const addonPrice = 20.0; // Price per addon
        addons.add({
          'addon_code': 'extra-fabric-conditioner',
          'quantity': 1,
        });
        addonsTotal += addonPrice;
      }

      if (_addExtraDetergent) {
        const addonPrice = 20.0; // Price per addon
        addons.add({
          'addon_code': 'extra-detergent',
          'quantity': 1,
        });
        addonsTotal += addonPrice;
      }

      // Step 4: Create OrderLoad objects
      final List<OrderLoad> orderLoads = [];
      
      // Only create loads for drop-off orders; rider pickup orders have no loads yet
      if (_selectedCollection == CollectionMethod.dropOff) {
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
      }

      // Step 5: Calculate totals
      // For rider pickup, subtotal is 0 until laundry is weighed
      final subtotal = _selectedCollection == CollectionMethod.dropOff 
          ? (basePrice * _loads.length) + addonsTotal 
          : 0.0;
      final totalAmount = subtotal; // delivery_fee is always 0

      // Step 6: Build customer notes
      final String? customerNotes = _instructionsController.text.trim().isNotEmpty
          ? _instructionsController.text.trim()
          : null;

      // Step 7: Build staff notes with order details
      final String staffNotes = [
        // Different notes for rider pickup vs drop-off
        if (_selectedCollection == CollectionMethod.riderPickup) ...[
          'Awaiting rider pickup and intake',
          if (_fullDeliveryAddress.isNotEmpty)
            'Pickup Address: $_fullDeliveryAddress${_landmarkController.text.trim().isNotEmpty ? ' (Landmark: ${_landmarkController.text.trim()})' : ''}',
        ] else ...[
          // Drop-off: Include load details
          if (_loads.length > 1) '${_loads.length} loads: ${orderLoads.map((l) => '${l.weight}${l.unit} ${l.category}').join(', ')}',
          if (_loads.length == 1) 'Load: ${orderLoads[0].weight}${orderLoads[0].unit} ${orderLoads[0].category}',
        ],
        if (_loyaltyCardUid != null &&
            _loyaltyCardInfo?.isActive == true &&
            _loyaltyCardInfo?.hasOwner == true &&
            _acceptedCustomerId == _loyaltyCardInfo?.customerId)
          'Loyalty Card: $_loyaltyCardUid',
        if (_selectedReturn == ReturnMethod.delivery && _selectedCollection != CollectionMethod.riderPickup && _fullDeliveryAddress.isNotEmpty)
          'Delivery Address: $_fullDeliveryAddress${_landmarkController.text.trim().isNotEmpty ? ' (Landmark: ${_landmarkController.text.trim()})' : ''}',
        if (_selectedReturn == ReturnMethod.delivery && _selectedCollection == CollectionMethod.riderPickup)
          'Delivery to same address as pickup',
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

      if (_isEditing) {
        final editOrder = widget.orderToEdit!;
        print('🔄 Updating walk-in order in database: ${editOrder.id}');
        await _orderService.updateWalkInOrder(
          orderId: editOrder.id,
          customerId: customerId,
          customerName: _customerFullName,
          customerPhone: _phoneController.text.trim().isNotEmpty
              ? _customerService.normalizePhone(_phoneController.text.trim())
              : null,
          serviceId: serviceId,
          serviceName: serviceName,
          loads: orderLoads,
          subtotal: subtotal,
          totalAmount: totalAmount,
          addons: addons,
          customerNotes: customerNotes,
          staffNotes: staffNotes.isNotEmpty ? staffNotes : null,
          deliveryAddress: (_selectedCollection == CollectionMethod.riderPickup || _selectedReturn == ReturnMethod.delivery)
              ? _fullDeliveryAddress
              : null,
          deliveryLandmark: (_selectedCollection == CollectionMethod.riderPickup || _selectedReturn == ReturnMethod.delivery)
              ? _landmarkController.text.trim()
              : null,
          isPaid: isPaidImmediately,
          paymentMethod: paymentMethod,
          assignedStaffId: assignedStaffId,
        );

        setState(() {
          _isSubmitting = false;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order ${editOrder.displayNumber} updated successfully ✓'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context, true);
        return;
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
        pickupRequested: _selectedCollection == CollectionMethod.riderPickup,
        deliveryRequested: _selectedReturn == ReturnMethod.delivery,
        deliveryAddress: (_selectedCollection == CollectionMethod.riderPickup || _selectedReturn == ReturnMethod.delivery) 
            ? _fullDeliveryAddress 
            : null,
        deliveryLandmark: (_selectedCollection == CollectionMethod.riderPickup || _selectedReturn == ReturnMethod.delivery) 
            ? _landmarkController.text.trim() 
            : null,
        customerNotes: customerNotes,
        staffNotes: staffNotes.isNotEmpty ? staffNotes : null,
        rfidTag: null,
        addons: addons,
        isPaid: isPaidImmediately && !gcashWithReceipt,
        paymentMethod: gcashWithReceipt ? null : paymentMethod,
      );

      print('✅ Order created: $orderId');

      // GCash Pay Now: upload the receipt and record the payment as
      // 'pending' (for review on the admin website). The order is marked
      // paid immediately inside submitGcashPayment.
      if (gcashWithReceipt) {
        try {
          await PaymentService().submitGcashPayment(
            orderId: orderId,
            amount: totalAmount,
            receiptFile: gcashReceiptFile,
            assignedStaffId: assignedStaffId,
          );
        } catch (paymentError) {
          // The order exists — do NOT retry the whole submit (that would
          // duplicate the order). Staff can complete the payment from the
          // Payments tab instead.
          setState(() {
            _isSubmitting = false;
          });
          if (!mounted) return;
          print('❌ GCash payment recording failed: $paymentError');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Order $orderNumber was created, but saving the GCash payment failed. '
                'Please complete the payment from the Payments tab.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 6),
            ),
          );
          Navigator.pop(context, true);
          return;
        }
      }

      setState(() {
        _isSubmitting = false;
      });

      if (!mounted) return;

      // Show post-creation confirmation dialog with Edit option
      _showOrderCreatedDialog(
        orderNumber: orderNumber,
        orderId: orderId,
        totalAmount: totalAmount,
        isPaid: isPaidImmediately,
        paymentMethod: paymentMethod,
        isRiderPickup: _selectedCollection == CollectionMethod.riderPickup,
        gcashWithReceipt: gcashWithReceipt,
      );
    } catch (e) {
      setState(() {
        _isSubmitting = false;
      });

      if (!mounted) return;

      print('❌ Error creating order: $e');

      // mapErrorToMessage classifies network, permission, duplicate,
      // and configuration failures into friendly text.
      final String errorMessage = mapErrorToMessage(e);

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
              gcashReceiptFile: gcashReceiptFile,
            );
          },
          ),
        ),
      );
    }
  }

  void _showOrderCreatedDialog({
    required String orderNumber,
    required String orderId,
    required double totalAmount,
    required bool isPaid,
    required String? paymentMethod,
    required bool isRiderPickup,
    required bool gcashWithReceipt,
  }) {
    // Build the info summary
    final String paymentInfo;
    if (isRiderPickup) {
      paymentInfo = 'Rider pickup scheduled';
    } else if (isPaid) {
      paymentInfo = gcashWithReceipt
          ? '₱${totalAmount.toStringAsFixed(2)} via GCash (pending verification)'
          : '₱${totalAmount.toStringAsFixed(2)} via ${paymentMethod ?? 'Cash'}';
    } else {
      paymentInfo = '₱${totalAmount.toStringAsFixed(2)} — UNPAID';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: Colors.green, size: 40),
            ),
            const SizedBox(height: 14),
            Text(
              'Order Created!',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(orderNumber,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.accentBlue)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 16, color: AppTheme.textLight),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_customerFullName,
                        style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
                        overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.layers_outlined, size: 16, color: AppTheme.textLight),
                      const SizedBox(width: 6),
                      Text('${_loads.length} load(s) • ${_totalWeight.toStringAsFixed(1)}kg',
                        style: const TextStyle(fontSize: 13, color: AppTheme.textDark)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(isPaid ? Icons.check_circle_outline : Icons.schedule,
                        size: 16, color: isPaid ? Colors.green : AppTheme.textLight),
                      const SizedBox(width: 6),
                      Expanded(child: Text(paymentInfo,
                        style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
                        overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Made a mistake? You can edit this order now.',
              style: TextStyle(fontSize: 11, color: AppTheme.textLight),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx); // Close dialog
                    // Fetch the full order to pass to edit screen
                    final fullOrder = await _orderService.getOrderById(orderId);
                    if (fullOrder != null && mounted) {
                      final editResult = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CreateOrderFlow(orderToEdit: fullOrder),
                        ),
                      );
                      if (mounted) Navigator.pop(context, true);
                    } else {
                      if (mounted) Navigator.pop(context, true);
                    }
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(
                    'Edit Order',
                    style: GoogleFonts.lexend(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentBlue,
                    side: const BorderSide(color: AppTheme.accentBlue, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx); // Close dialog
                    Navigator.pop(context, true); // Return to orders
                  },
                  icon: const Icon(Icons.check, size: 18, color: Colors.white),
                  label: Text(
                    'Done',
                    style: GoogleFonts.lexend(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
                  onPressed: _isSubmitting ? null : () async {
                    if (method == 'GCash') {
                      // GCash: show the admin-uploaded QR, then capture/upload
                      // the receipt BEFORE creating the order + payment.
                      Navigator.pop(ctx);
                      final receipt = await Navigator.push<File>(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GcashQrPaymentScreen(
                            title: 'Pay Now with GCash',
                            orderLabel: 'New Walk-in Order',
                            amount: _finalTotal,
                            customerName: _customerFullName,
                          ),
                        ),
                      );
                      if (receipt == null || !mounted) return;
                      _submitOrder(
                        isPaidImmediately: true,
                        paymentMethod: 'GCash',
                        gcashReceiptFile: receipt,
                      );
                    } else {
                      Navigator.pop(ctx);
                      _submitOrder(isPaidImmediately: true, paymentMethod: method);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
                      : Text(
                    'Confirm Payment',
                    style: GoogleFonts.lexend(fontSize: 15, fontWeight: FontWeight.bold),
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Order ${widget.orderToEdit!.displayNumber}' : 'New Walk-in Order'),
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
              color: _lookingUpCard
                  ? Colors.orange.withValues(alpha: 0.1)
                  : _loyaltyCardInfo != null
                  ? Colors.green.withValues(alpha: 0.1)
                  : AppTheme.accentBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _loyaltyCardInfo != null
                      ? Icons.credit_card
                      : Icons.credit_card_outlined,
                  size: 14,
                  color: _lookingUpCard
                      ? Colors.orange
                      : _loyaltyCardInfo != null
                      ? Colors.green
                      : AppTheme.accentBlue,
                ),
                const SizedBox(width: 4),
                Text(
                  _lookingUpCard
                      ? 'Looking up...'
                      : _loyaltyCardInfo != null
                      ? '${_loyaltyCardInfo!.pointsBalance} pts'
                      : 'No Card Scanned',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _lookingUpCard
                        ? Colors.orange
                        : _loyaltyCardInfo != null
                        ? Colors.green
                        : AppTheme.accentBlue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildStickyBottomBar(),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Progress indicator
            _buildProgressIndicator(),
            const SizedBox(height: 20),

            // 1. Customer Section (Step 1)
            KeyedSubtree(
              key: _step1Key,
              child: _buildCustomerSection(),
            ),
            const SizedBox(height: 14),

            // 2. Laundry & Intake Section (Step 2)
            KeyedSubtree(
              key: _step2Key,
              child: _buildLaundryIntakeSection(),
            ),
            const SizedBox(height: 14),

            // 3. Add-ons & Notes Section (Step 3)
            KeyedSubtree(
              key: _step3Key,
              child: _buildAddOnsSection(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerSection() {
    final isExpanded = _expandedStep == 1;

    return Container(
      // FIX: clip children to the card's rounded border so nothing inside can
      // ever paint outside this card's bounds.
      clipBehavior: Clip.antiAlias,
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
            onTap: () {
              setState(() => _expandedStep = isExpanded ? null : 1);
              if (!isExpanded) _scrollToStep(_step1Key);
            },
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
                            _customerFullName +
                                (_phoneController.text.trim().isNotEmpty
                                    ? ' • ${_phoneController.text.trim()}'
                                    : '') +
                                (_loyaltyCardUid != null
                                    ? ' • Card: $_loyaltyCardUid'
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
                  // Loyalty Card Banner / Quick Scanner
                  _buildStep1LoyaltyCardWidget(),
                  const SizedBox(height: 12),

                  // Customer suggestion banner(s)
                  if (_suggestionType != _SuggestionType.none && !_dismissedSuggestion)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildCustomerSuggestionsUI(),
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
                          validator: (v) => Validators.nameField(v, 'First name'),
                          maxLength: Validators.nameMax,
                          textCapitalization: TextCapitalization.words,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: CustomTextField(
                          label: 'Last Name (Optional)',
                          hint: 'Dela Cruz',
                          prefixIcon: Icons.badge_outlined,
                          controller: _lastNameController,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? null
                              : Validators.nameField(v, 'Last name'),
                          maxLength: Validators.nameMax,
                          textCapitalization: TextCapitalization.words,
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
                    keyboardType: TextInputType.phone,
                    inputFormatters: InputFormatters.phone(),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? null
                        : Validators.phone(v),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build customer suggestion UI based on match type
  Widget _buildCustomerSuggestionsUI() {
    // Add key to stabilize widget identity across rebuilds
    return KeyedSubtree(
      key: ValueKey('suggestions_$_suggestionType'),
      child: _buildSuggestionContent(),
    );
  }
  
  Widget _buildSuggestionContent() {
    switch (_suggestionType) {
      case _SuggestionType.confident:
        // 1-3 matches - show all
        return _buildConfidentMatchesUI();
      case _SuggestionType.uncertain:
        // 4-10 matches - show with warning
        return _buildUncertainMatchesUI();
      case _SuggestionType.tooMany:
        // >10 matches - show prompt only
        return _buildTooManyMatchesPrompt();
      case _SuggestionType.none:
        return const SizedBox.shrink();
    }
  }

  /// UI for 1-3 confident matches
  Widget _buildConfidentMatchesUI() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // Changed from max to min
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible( // Changed Row to Flexible
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 15, color: Colors.green),
                    const SizedBox(width: 6),
                    Flexible( // Wrap Text with Flexible instead of no wrapper
                      child: Text(
                        _suggestionMessage ?? 'Customer found',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: _dismissCurrentSuggestions,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 16, color: AppTheme.textLight),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Show each match (confident UI)
          for (var i = 0; i < _suggestedCustomers.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            KeyedSubtree(
              key: ValueKey('conf_${_suggestedCustomers[i].customerId}_$i'),
              child: _buildCustomerMatchCard(_suggestedCustomers[i]),
            ),
          ],
          if (_suggestedCustomers.length > 1) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _dismissCurrentSuggestions,
              icon: const Icon(Icons.add_circle_outline, size: 16),
              label: const Text('None of These - Create New Customer'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.textDark,
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// UI for 4-10 uncertain matches
  Widget _buildUncertainMatchesUI() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // Changed from max to min
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded( // Wrap the inner Row with Expanded
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 15, color: Colors.orange),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _suggestionMessage ?? 'Multiple customers found',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: _dismissCurrentSuggestions,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 16, color: AppTheme.textLight),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Please select the correct customer:',
            style: TextStyle(fontSize: 11, color: AppTheme.textLight),
          ),
          const SizedBox(height: 12),
          // Show each match (uncertain UI)
          for (var i = 0; i < _suggestedCustomers.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            KeyedSubtree(
              key: ValueKey('unc_${_suggestedCustomers[i].customerId}_$i'),
              child: _buildCustomerMatchCard(_suggestedCustomers[i]),
            ),
          ],
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _dismissCurrentSuggestions,
            icon: const Icon(Icons.add_circle_outline, size: 16),
            label: const Text('None of These - Create New Customer'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textDark,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  /// UI for >10 matches - prompt for more info
  Widget _buildTooManyMatchesPrompt() {
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
                  const Icon(Icons.info_outline, size: 15, color: AppTheme.accentBlue),
                  const SizedBox(width: 6),
                  const Text(
                    'Need More Information',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accentBlue,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _dismissCurrentSuggestions,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 16, color: AppTheme.textLight),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _suggestionMessage ?? 'Too many matches found',
            style: const TextStyle(fontSize: 12, color: AppTheme.textDark),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.borderGray),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'To identify returning customers, please add:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.check_circle, size: 12, color: Colors.green),
                    const SizedBox(width: 6),
                    Text(
                      _lastNameController.text.trim().isEmpty ? 'Last name, OR' : 'Phone number',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textDark),
                    ),
                  ],
                ),
                if (_lastNameController.text.trim().isEmpty) ...[
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      Icon(Icons.check_circle, size: 12, color: Colors.green),
                      SizedBox(width: 6),
                      Text(
                        'Phone number',
                        style: TextStyle(fontSize: 11, color: AppTheme.textDark),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _dismissCurrentSuggestions,
            child: const Text(
              'Continue Without (creates new customer)',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  /// Build a single customer match card
  Widget _buildCustomerMatchCard(_CustomerProfile customer) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.fullName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                    ),
                    const SizedBox(height: 2),
                    if (customer.phone.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.phone_android, size: 11, color: AppTheme.textLight),
                          const SizedBox(width: 4),
                          Text(
                            customer.phone,
                            style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (customer.address != null && customer.address!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  customer.pinLatitude != null ? Icons.location_on : Icons.location_on_outlined,
                  size: 11,
                  color: customer.pinLatitude != null ? Colors.green.shade700 : AppTheme.textLight,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    customer.pinLatitude != null
                        ? '${customer.address!} (20m Pinned)'
                        : customer.address!,
                    style: TextStyle(
                      fontSize: 10,
                      color: customer.pinLatitude != null ? Colors.green.shade800 : AppTheme.textLight,
                      fontWeight: customer.pinLatitude != null ? FontWeight.w600 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (customer.lastOrderDate != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.history, size: 11, color: AppTheme.textLight),
                const SizedBox(width: 4),
                Text(
                  'Last order: ${_formatDate(customer.lastOrderDate!)}',
                  style: const TextStyle(fontSize: 10, color: AppTheme.textLight),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _applyCustomerSuggestion(customer),
              icon: const Icon(Icons.check_circle, size: 14),
              label: const Text('Use This Customer', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return months == 1 ? '1 month ago' : '$months months ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return years == 1 ? '1 year ago' : '$years years ago';
    }
  }

  Widget _buildLaundryIntakeSection() {
    final isExpanded = _expandedStep == 2;

    // Always accessible - no locked state
    return Container(
      // FIX: clip children to the card's rounded border.
      clipBehavior: Clip.antiAlias,
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
            onTap: () {
              setState(() => _expandedStep = isExpanded ? null : 2);
              if (!isExpanded) _scrollToStep(_step2Key);
            },
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
                            _selectedCollection == CollectionMethod.riderPickup
                                ? 'Rider pickup • Address provided'
                                : '${_loads.length} load(s) • ${_totalWeight.toStringAsFixed(1)}kg${_loyaltyCardUid != null ? " • Card: $_loyaltyCardUid" : ""}',
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
                  // Collection Method - MOVED TO TOP
                  const Text(
                    'Collection Method',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildReturnOption(
                          icon: Icons.store_outlined,
                          title: 'Walk-in Drop-off',
                          isSelected: _selectedCollection == CollectionMethod.dropOff,
                          onTap: () {
                            setState(() {
                              _selectedCollection = CollectionMethod.dropOff;
                              // Ensure at least one load exists for drop-off
                              if (_loads.isEmpty) {
                                _loads.add(LoadDraft(initialWeight: ''));
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildReturnOption(
                          icon: Icons.two_wheeler,
                          title: 'Rider Pickup',
                          isSelected: _selectedCollection == CollectionMethod.riderPickup,
                          onTap: () => setState(() => _selectedCollection = CollectionMethod.riderPickup),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedCollection == CollectionMethod.riderPickup)
                    _buildAddressFormSection(title: 'Pickup Location & Address'),

                  const Divider(height: 24),

                  // CONDITIONAL: Show loads only for drop-off, show placeholder for rider pickup
                  if (_selectedCollection == CollectionMethod.dropOff) ...[
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
                  ] else ...[
                    // Rider Pickup: Show placeholder message
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue.shade700, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Laundry Not Yet Received',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'The rider will pick up the laundry from the customer. Weight and intake will be done after the rider returns.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textDark.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 24),
                  ],

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
                    // Show address fields only if not already shown for pickup
                    if (_selectedCollection != CollectionMethod.riderPickup)
                      _buildAddressFormSection(title: 'Delivery Location & Address')
                    else ...[
                      const SizedBox(height: 12),
                      // If pickup is selected, show a note that the same address will be used
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 18, color: AppTheme.accentBlue.withValues(alpha: 0.8)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Delivery will use the same address as pickup',
                                style: TextStyle(fontSize: 12, color: AppTheme.accentBlue.withValues(alpha: 0.9)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep1LoyaltyCardWidget() {
    final card = _loyaltyCardInfo;
    final isCardLinkedToOrderCustomer = card != null &&
        card.isActive &&
        card.hasOwner &&
        _acceptedCustomerId == card.customerId;
    final cardStatus = card == null
        ? 'Not linked'
        : !card.isActive
            ? 'Inactive'
            : !card.hasOwner
                ? 'Unassigned'
                : isCardLinkedToOrderCustomer
                    ? 'Linked'
                    : 'Not linked';
    final cardStatusColor = isCardLinkedToOrderCustomer
        ? Colors.green
        : Colors.orange.shade800;

    if (_loyaltyCardUid != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.credit_card, size: 18, color: Colors.green),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Card: $_loyaltyCardUid',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cardStatusColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          cardStatus,
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    card != null
                        ? '${card.ownerName} • ${card.pointsBalance} pts'
                        : 'Card details unavailable',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppTheme.textLight),
              onPressed: _clearLoyaltyCard,
              tooltip: 'Unlink card',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.accentBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.nfc_outlined, size: 16, color: AppTheme.accentBlue),
              SizedBox(width: 6),
              Text(
                'RFID Loyalty Card (Tap or Enter UID)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _loyaltyCardController,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: InputFormatters.uppercaseCardUid,
                  decoration: const InputDecoration(
                    hintText: 'Enter Loyalty Card UID to auto-fill details',
                    hintStyle: TextStyle(fontSize: 12, color: AppTheme.textLight),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                      borderSide: BorderSide(color: AppTheme.borderGray),
                    ),
                  ),
                  onSubmitted: (val) {
                    if (val.trim().isNotEmpty) _lookupLoyaltyCard(val);
                  },
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _lookingUpCard
                    ? null
                    : () {
                  final uid = _loyaltyCardController.text.trim();
                  if (uid.isNotEmpty) _lookupLoyaltyCard(uid);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: const Size(60, 36),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _lookingUpCard
                    ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
                    : const Text('Lookup', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
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

          // Category Selection - 2-column wrap grid (natural height, no aspect ratio constraints)
          const Text('Category:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLight)),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - 6) / 2;
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  SizedBox(width: tileWidth, child: _buildCompactCategoryTile(categoriesList[0], load, index)),
                  SizedBox(width: tileWidth, child: _buildCompactCategoryTile(categoriesList[1], load, index)),
                  SizedBox(width: tileWidth, child: _buildCompactCategoryTile(categoriesList[2], load, index)),
                  SizedBox(width: tileWidth, child: _buildCompactCategoryTile(categoriesList[3], load, index)),
                ],
              );
            },
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
                  inputFormatters:
                      InputFormatters.decimal(maxDecimals: 2, maxLength: 6),
                  onChanged: (_) => setState(() {}),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: '0.0',
                    hintStyle: TextStyle(
                      color: AppTheme.textLight.withValues(alpha: 0.5),
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                    ),
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

  Widget _buildCompactCategoryTile(MapEntry<String, Map<String, dynamic>> entry, LoadDraft load, int loadIndex) {
    final isSelected = load.category == entry.key;
    final icon = entry.value['icon'] as IconData;

    return InkWell(
      onTap: () => setState(() => load.category = entry.key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentBlue.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.accentBlue : AppTheme.borderGray.withValues(alpha: 0.4),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? AppTheme.accentBlue : AppTheme.textLight),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                entry.key,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? AppTheme.accentBlue : AppTheme.textDark,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildAddressFormSection({required String title}) {
    final hasPin = _deliveryPinLocation != null;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.softGray.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, size: 18, color: AppTheme.accentBlue),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.lexend(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 20m Meetup Zone Pin Card
          InkWell(
            onTap: _openPinLocationPicker,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: hasPin ? Colors.green.shade50 : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hasPin ? Colors.green.shade300 : AppTheme.accentBlue.withValues(alpha: 0.4),
                  width: hasPin ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    hasPin ? Icons.check_circle : Icons.add_location_alt_outlined,
                    color: hasPin ? Colors.green.shade700 : AppTheme.accentBlue,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasPin ? '20m Meetup Zone Pinned' : 'Pin 20m Meetup Zone on Map',
                          style: GoogleFonts.lexend(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: hasPin ? Colors.green.shade900 : AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasPin
                              ? '${LocationHelper.getFormattedDistance(_deliveryPinLocation!)} from shop • (${_deliveryPinLocation!.latitude.toStringAsFixed(5)}, ${_deliveryPinLocation!.longitude.toStringAsFixed(5)})'
                              : 'Optional: Tap to set exact gate or meetup location for rider',
                          style: GoogleFonts.lexend(
                            fontSize: 11,
                            color: hasPin ? Colors.green.shade800 : AppTheme.textLight,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (hasPin)
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: AppTheme.textLight),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Clear Pin',
                      onPressed: () => setState(() => _deliveryPinLocation = null),
                    )
                  else
                    const Icon(Icons.chevron_right, size: 18, color: AppTheme.textLight),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 3-part address — uses shared widget
          AddressInputWidget(
            houseStreetController: _houseStreetController,
            customBarangayController: _customBarangayController,
            landmarkController: _landmarkController,
            selectedBarangay: _selectedBarangay,
            onBarangayChanged: (v) => setState(() => _selectedBarangay = v),
            landmarkHint: 'e.g. Near church, blue gate',
          ),
        ],
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
      // FIX: clip children to the card's rounded border.
      clipBehavior: Clip.antiAlias,
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
            onTap: () {
              setState(() => _expandedStep = isExpanded ? null : 3);
              if (!isExpanded) _scrollToStep(_step3Key);
            },
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
                        Material(
                          color: Colors.transparent,
                          child: CheckboxListTile(
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
                        ),

                        // Extra Detergent
                        Material(
                          color: Colors.transparent,
                          child: CheckboxListTile(
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
                      color: _selectedCollection == CollectionMethod.riderPickup 
                          ? Colors.blue.withValues(alpha: 0.05)
                          : Colors.green.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedCollection == CollectionMethod.riderPickup 
                            ? Colors.blue.withValues(alpha: 0.2)
                            : Colors.green.withValues(alpha: 0.2), 
                        width: 1
                      ),
                    ),
                    child: _selectedCollection == CollectionMethod.riderPickup
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Pricing to be Determined',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue.shade700),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Final price will be calculated after the rider picks up and delivers the laundry for weighing.',
                                style: TextStyle(fontSize: 13, color: AppTheme.textDark.withValues(alpha: 0.8)),
                              ),
                            ],
                          )
                        : Column(
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

  Widget _buildStickyBottomBar() {
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
            // Order summary - Different for rider pickup vs drop-off
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        _selectedCollection == CollectionMethod.riderPickup 
                            ? Icons.two_wheeler 
                            : Icons.credit_card, 
                        size: 12, 
                        color: _selectedCollection == CollectionMethod.riderPickup 
                            ? Colors.blue 
                            : Colors.green
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _selectedCollection == CollectionMethod.riderPickup
                            ? 'Rider pickup order${_loyaltyCardUid != null ? " • Card: $_loyaltyCardUid" : ""}'
                            : '${_loyaltyCardUid != null ? "Card: $_loyaltyCardUid • " : ""}${_loads.length} load(s) • ${_totalWeight.toStringAsFixed(1)}kg',
                        style: TextStyle(
                          fontSize: 11, 
                          fontWeight: FontWeight.bold, 
                          color: _selectedCollection == CollectionMethod.riderPickup 
                              ? Colors.blue 
                              : Colors.green
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _selectedCollection == CollectionMethod.riderPickup
                        ? 'TBD'
                        : '₱${_calculateTotalPrice().toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16, 
                      fontWeight: FontWeight.bold, 
                      color: _selectedCollection == CollectionMethod.riderPickup 
                          ? Colors.blue 
                          : Colors.green
                    ),
                  ),
                ],
              ),
            ),

            // Payment Buttons Row - Different for edit mode, rider pickup, and drop-off
            if (_isEditing) ...[
              if (widget.orderToEdit!.paymentStatus == PaymentStatus.paid)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSubmitting ? null : _showPaymentMethodModal,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.accentBlue,
                          side: const BorderSide(color: AppTheme.accentBlue, width: 1.5),
                          minimumSize: const Size.fromHeight(50),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'Payment Options',
                          style: GoogleFonts.lexend(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => _submitOrder(
                                  isPaidImmediately: true,
                                  paymentMethod: widget.orderToEdit!.paymentMethod ?? 'Cash',
                                ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentBlue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                          padding: const EdgeInsets.symmetric(vertical: 14),
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
                            : Text(
                                'Save Changes',
                                style: GoogleFonts.lexend(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => _submitOrder(isPaidImmediately: false, paymentMethod: null),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.accentBlue,
                          side: const BorderSide(color: AppTheme.accentBlue, width: 1.5),
                          minimumSize: const Size.fromHeight(50),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'Save as Unpaid',
                          style: GoogleFonts.lexend(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _showPaymentMethodModal,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentBlue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: Text(
                          'Pay Now & Save',
                          style: GoogleFonts.lexend(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
            ] else if (_selectedCollection == CollectionMethod.riderPickup)
              // Rider Pickup: Only one button to create order
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : () => _submitOrder(isPaidImmediately: false, paymentMethod: null),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
                      : Text(
                          'Create Rider Pickup Order',
                          style: GoogleFonts.lexend(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                ),
              )
            else
              // Drop-off: Show Pay Later and Pay Now options
              Row(
                children: [
                  // Pay Later Button
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting ? null : () => _submitOrder(isPaidImmediately: false, paymentMethod: null),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.accentBlue,
                        side: const BorderSide(color: AppTheme.accentBlue, width: 1.5),
                        minimumSize: const Size.fromHeight(50),
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
                          : Text(
                        'Pay Later',
                        style: GoogleFonts.lexend(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Pay Now Button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _showPaymentMethodModal,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(
                        'Pay Now',
                        style: GoogleFonts.lexend(fontSize: 15, fontWeight: FontWeight.bold),
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
