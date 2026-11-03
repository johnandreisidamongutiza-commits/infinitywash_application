import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_error.dart';
import '../../../utils/input_formatters.dart';
import '../../../services/loyalty_service.dart';
import '../../../services/customer_service.dart';

class RfidCheckerScreen extends StatefulWidget {
  final String? initialTag;
  const RfidCheckerScreen({super.key, this.initialTag});

  @override
  State<RfidCheckerScreen> createState() => _RfidCheckerScreenState();
}

class _RfidCheckerScreenState extends State<RfidCheckerScreen> {
  final TextEditingController _manualTagController = TextEditingController();
  final LoyaltyService _loyaltyService = LoyaltyService();
  final CustomerService _customerService = CustomerService();
  RealtimeChannel? _scanChannel;

  String? _scannedUid;
  LoyaltyCardInfo? _cardInfo;
  bool _isSearching = false;
  String? _error;

  // Registration flow state
  bool _showingRegisterFlow = false;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearchingCustomers = false;

  @override
  void initState() {
    super.initState();
    _subscribeToLiveRfidScans();
    if (widget.initialTag != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scanCard(widget.initialTag!);
      });
    }
  }

  void _subscribeToLiveRfidScans() {
    try {
      _scanChannel = Supabase.instance.client
          .channel('public:scanned_rfid_events')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'scanned_rfid_events',
            callback: (payload) {
              final newRecord = payload.newRecord;
              final uid = newRecord['uid'] as String?;
              if (uid != null && uid.trim().isNotEmpty && mounted) {
                _scanCard(uid);
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Error subscribing to RFID live scans: $e');
    }
  }

  @override
  void dispose() {
    _scanChannel?.unsubscribe();
    _manualTagController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ─── Scanner Logic ───────────────────────────────────────────────────────────

  void _scanCard(String uid) async {
    final cleanUid = uid.trim().toUpperCase();
    if (cleanUid.isEmpty) return;

    setState(() {
      _isSearching = true;
      _scannedUid = cleanUid;
      _cardInfo = null;
      _error = null;
      _showingRegisterFlow = false;
    });
    _manualTagController.clear();

    try {
      final card = await _loyaltyService.lookupCardByUid(cleanUid);
      if (!mounted) return;
      setState(() {
        _cardInfo = card;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _error = mapErrorToMessage(e);
      });
    }
  }

  void _resetScanner() {
    setState(() {
      _scannedUid = null;
      _cardInfo = null;
      _isSearching = false;
      _error = null;
      _showingRegisterFlow = false;
      _searchResults = [];
      _manualTagController.clear();
      _searchController.clear();
    });
  }

  // ─── Registration Flow ───────────────────────────────────────────────────────

  void _searchCustomers(String query) async {
    if (query.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearchingCustomers = true);
    final results = await _loyaltyService.searchCustomers(query);
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _isSearchingCustomers = false;
    });
  }


  // ─── Quick Registration Bottom Sheet ─────────────────────────────────────────

  void _openQuickRegisterCustomerModal({String? initialName}) {
    final firstNameController = TextEditingController(text: initialName ?? '');
    final lastNameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header drag handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.accentBlue.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person_add, color: AppTheme.accentBlue, size: 22),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Register New Customer',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                Text(
                                  'Create customer profile and link loyalty card',
                                  style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: AppTheme.textLight),
                            onPressed: () => Navigator.pop(sheetContext),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Card UID pill
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.credit_card, size: 16, color: AppTheme.accentBlue),
                            const SizedBox(width: 8),
                            Text(
                              'Assigning Card UID: ${_scannedUid ?? ""}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppTheme.accentBlue,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // First Name
                      TextFormField(
                        controller: firstNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'First Name *',
                          hintText: 'e.g. Maria',
                          prefixIcon: Icon(Icons.person_outline, size: 20),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'First name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Last Name
                      TextFormField(
                        controller: lastNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Last Name',
                          hintText: 'e.g. Santos',
                          prefixIcon: Icon(Icons.badge_outlined, size: 20),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Phone
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Mobile Phone *',
                          hintText: '09xxxxxxxxx',
                          prefixIcon: Icon(Icons.phone_outlined, size: 20),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Phone number is required';
                          }
                          final digits = val.replaceAll(RegExp(r'[^0-9]'), '');
                          if (digits.length < 10) {
                            return 'Please enter a valid phone number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Address / Landmark (optional)
                      TextFormField(
                        controller: addressController,
                        decoration: const InputDecoration(
                          labelText: 'Address / Barangay (Optional)',
                          hintText: 'e.g. Brgy. San Jose',
                          prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Submit button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) return;
                                  if (_scannedUid == null) return;

                                  setSheetState(() => isSubmitting = true);

                                  try {
                                    final fName = firstNameController.text.trim();
                                    final lName = lastNameController.text.trim();
                                    final fullName = '$fName $lName'.trim();

                                    // 1. Create walk-in customer in customers table
                                    final newCustomerId = await _customerService.createCustomer(
                                      firstName: fName,
                                      lastName: lName.isNotEmpty ? lName : null,
                                      phone: phoneController.text.trim(),
                                      address: addressController.text.trim().isNotEmpty
                                          ? addressController.text.trim()
                                          : null,
                                      customerType: 'walk_in',
                                    );

                                    // 2. Link card to newly created customer
                                    await _loyaltyService.registerCard(
                                      uid: _scannedUid!,
                                      customerId: newCustomerId,
                                    );

                                    if (!mounted) return;
                                    Navigator.pop(sheetContext);

                                    // 3. Celebrate with green snackbar & auto-refresh
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Row(
                                          children: [
                                            const Icon(Icons.check_circle, color: Colors.white),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text('Loyalty Card linked to $fullName!'),
                                            ),
                                          ],
                                        ),
                                        backgroundColor: Colors.green,
                                        duration: const Duration(seconds: 4),
                                      ),
                                    );

                                    // 4. Instantly auto-scan to show active loyalty dashboard
                                    _scanCard(_scannedUid!);
                                  } catch (e) {
                                    setSheetState(() => isSubmitting = false);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Failed to register: ${mapErrorToMessage(e)}'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00897B),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: isSubmitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Text(
                                  'Register & Activate Loyalty Card',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _registerCardToCustomer(Map<String, dynamic> customer) async {
    final customerId = customer['id'] as String;
    final firstName = customer['first_name'] as String? ?? '';
    final lastName = customer['last_name'] as String? ?? '';
    final name = '$firstName $lastName'.trim();

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.credit_card, color: AppTheme.accentBlue),
            SizedBox(width: 8),
            Text('Register Card', style: TextStyle(fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Assign card UID:'),
            const SizedBox(height: 4),
            Text(
              _scannedUid ?? '',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppTheme.accentBlue,
              ),
            ),
            const SizedBox(height: 12),
            Text('To customer:'),
            const SizedBox(height: 4),
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            if ((customer['phone'] as String?) != null) ...[
              const SizedBox(height: 2),
              Text(
                customer['phone'] as String,
                style: const TextStyle(color: AppTheme.textLight, fontSize: 13),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentBlue,
              minimumSize: const Size(80, 36),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      // Register the card to the customer
      await _loyaltyService.registerCard(
        uid: _scannedUid!,
        customerId: customerId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Loyalty Card linked to $name!'),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );

      // Re-scan to show fresh card info
      _scanCard(_scannedUid!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration failed. ${mapErrorToMessage(e)}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Loyalty Card Scanner'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildScannerHero(),
              const SizedBox(height: 20),

              // Result area
              if (_isSearching)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Reading loyalty card...',
                            style: TextStyle(color: AppTheme.textLight)),
                      ],
                    ),
                  ),
                )
              else if (_error != null)
                _buildErrorCard()
              else if (_scannedUid != null) ...[
                if (_cardInfo != null)
                  _buildCardFoundResult()
                else
                  _buildCardNotFoundResult(),
              ] else
                _buildIdleGuide(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Scanner Hero Panel ───────────────────────────────────────────────────────

  Widget _buildScannerHero() {
    final isActive = _scannedUid != null && !_isSearching;
    final borderColor = _isSearching
        ? Colors.orange
        : isActive
            ? (_cardInfo != null ? Colors.green : AppTheme.errorRed)
            : AppTheme.accentBlue.withValues(alpha: 0.3);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accentBlue.withValues(alpha: 0.06),
            AppTheme.lightBlue.withValues(alpha: 0.22),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor,
          width: _isSearching || isActive ? 2.0 : 1.0,
        ),
      ),
      child: Column(
        children: [
          // Status LED
          _buildStatusLed(),
          const SizedBox(height: 16),

          // NFC Icon
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isSearching
                      ? Colors.orange.withValues(alpha: 0.15)
                      : AppTheme.accentBlue.withValues(alpha: 0.10),
                ),
              ),
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _isSearching
                          ? Colors.orange.withValues(alpha: 0.3)
                          : AppTheme.accentBlue.withValues(alpha: 0.2),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.credit_card_outlined,
                  size: 34,
                  color:
                      _isSearching ? Colors.orange : AppTheme.accentBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Text(
            _isSearching
                ? 'Scanning Card: $_scannedUid'
                : _scannedUid != null
                    ? 'Card UID: $_scannedUid'
                    : 'Waiting for RFID Loyalty Card',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            _isSearching
                ? 'Looking up customer loyalty data...'
                : _cardInfo != null
                    ? 'Card linked to ${_cardInfo!.ownerName}'
                    : 'Tap card to reader, or enter UID manually below',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
          ),
          // Manual input row (only shown when waiting for a card)
          if (_cardInfo == null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.borderGray),
                    ),
                    child: TextField(
                      controller: _manualTagController,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: InputFormatters.uppercaseCardUid,
                      decoration: const InputDecoration(
                        hintText: 'Enter Card UID (e.g. A3F9C2)...',
                        hintStyle:
                            TextStyle(fontSize: 12, color: AppTheme.textLight),
                        prefixIcon: Icon(Icons.qr_code_scanner,
                            size: 18, color: AppTheme.textLight),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                      ),
                      onSubmitted: _scanCard,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _scanCard(_manualTagController.text),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.accentBlue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'Scan',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusLed() {
    Color ledColor;
    String ledText;

    if (_isSearching) {
      ledColor = Colors.orange;
      ledText = 'READING CARD...';
    } else if (_scannedUid != null) {
      if (_cardInfo != null) {
        ledColor = Colors.green;
        ledText = 'CARD FOUND • LOYALTY DATA LOADED';
      } else {
        ledColor = AppTheme.errorRed;
        ledText = 'CARD NOT REGISTERED';
      }
    } else {
      ledColor = Colors.green;
      ledText = 'READER ACTIVE • WAITING FOR CARD';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: ledColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ledColor.withValues(alpha: 0.5), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: ledColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              ledText,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: ledColor,
                letterSpacing: 0.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Idle Guide ───────────────────────────────────────────────────────────────

  Widget _buildIdleGuide() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How to use',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark),
        ),
        const SizedBox(height: 12),
        _buildGuideItem(Icons.credit_card_outlined, 'Tap loyalty card to reader',
            'Hold the customer\'s RFID card near the counter reader'),
        const SizedBox(height: 8),
        _buildGuideItem(Icons.search, 'Check loyalty balance',
            'See points, total orders, and free load eligibility'),
        const SizedBox(height: 8),
        _buildGuideItem(Icons.person_add_outlined, 'Register new cards',
            'Link an unregistered card to a customer account'),
      ],
    );
  }

  Widget _buildGuideItem(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.softGray,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.accentBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppTheme.accentBlue, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppTheme.textDark)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textLight)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Card Found Result ────────────────────────────────────────────────────────

  Widget _buildCardFoundResult() {
    final card = _cardInfo!;
    final hasFreeLoas = card.freeLoadsAvailable > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card header
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primaryBlue,
                AppTheme.accentBlue,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentBlue.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.credit_card,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.ownerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (card.ownerPhone != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            card.ownerPhone!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: card.isActive
                          ? Colors.green.withValues(alpha: 0.25)
                          : Colors.red.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      card.isActive ? 'ACTIVE' : 'INACTIVE',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Points balance big display
              Row(
                children: [
                  Icon(Icons.stars_rounded, color: Colors.amber, size: 28),
                  const SizedBox(width: 8),
                  Text(
                    '${card.pointsBalance}',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'loyalty points',
                        style:
                            TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                      if (hasFreeLoas)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${card.freeLoadsAvailable} FREE LOAD${card.freeLoadsAvailable > 1 ? 'S' : ''} AVAILABLE',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 4),
              Text(
                hasFreeLoas
                    ? 'Can redeem ${card.freeLoadsAvailable} free load${card.freeLoadsAvailable > 1 ? 's' : ''} now!'
                    : '${card.pointsToNextRedemption} more pts for a free load',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),

              const SizedBox(height: 4),
              Text(
                'UID: ${card.uid}',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.5),
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Stats row
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.receipt_long_outlined,
                value: '${card.totalOrders}',
                label: 'Orders',
                color: AppTheme.accentBlue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildStatCard(
                icon: Icons.local_laundry_service_outlined,
                value: '${card.totalLoads}',
                label: 'Loads',
                color: Colors.purple,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildStatCard(
                icon: Icons.card_giftcard_outlined,
                value: '${card.freeLoadsAvailable}',
                label: 'Free Loads',
                color: Colors.amber.shade700,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Progress bar to next free load
        _buildPointsProgressBar(card),

        const SizedBox(height: 16),

        // Action buttons
        if (hasFreeLoas) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showRedeemDialog(card),
              icon: const Icon(Icons.card_giftcard, color: Colors.white),
              label: Text(
                'Redeem ${card.freeLoadsAvailable} Free Load${card.freeLoadsAvailable > 1 ? 's' : ''}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _resetScanner,
            icon: const Icon(Icons.nfc_outlined, size: 18),
            label: const Text('Scan Another Card'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              side: const BorderSide(color: AppTheme.borderGray),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppTheme.textLight),
          ),
        ],
      ),
    );
  }

  Widget _buildPointsProgressBar(LoyaltyCardInfo card) {
    final int progress = card.pointsBalance % 10;
    final double fraction = progress / 10.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.softGray,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Progress to Next Free Load',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark),
              ),
              Text(
                '$progress / 10 pts',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accentBlue),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 10,
              backgroundColor: AppTheme.borderGray,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppTheme.accentBlue),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            fraction >= 1.0 || progress == 0 && card.pointsBalance > 0
                ? 'Ready to redeem a free load!'
                : '${10 - progress} more load${10 - progress > 1 ? 's' : ''} to earn a free load',
            style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
          ),
        ],
      ),
    );
  }

  void _showRedeemDialog(LoyaltyCardInfo card) {
    int loadsToRedeem = 1;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.card_giftcard, color: Colors.amber),
              SizedBox(width: 8),
              Text('Redeem Free Loads', style: TextStyle(fontSize: 17)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Available: ${card.freeLoadsAvailable} free load${card.freeLoadsAvailable > 1 ? 's' : ''}',
                style: const TextStyle(color: AppTheme.textLight),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: loadsToRedeem > 1
                        ? () => setDialogState(() => loadsToRedeem--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.accentBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$loadsToRedeem',
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentBlue),
                    ),
                  ),
                  IconButton(
                    onPressed: loadsToRedeem < card.freeLoadsAvailable
                        ? () => setDialogState(() => loadsToRedeem++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Cost: ${loadsToRedeem * 10} pts  •  Save ₱${(loadsToRedeem * 170).toStringAsFixed(0)}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('Cancel', style: TextStyle(color: AppTheme.textLight)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  final discount = await _loyaltyService.redeemPoints(
                    cardId: card.cardId,
                    customerId: card.customerId,
                    freeLoadsToRedeem: loadsToRedeem,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Successfully redeemed $loadsToRedeem free load(s) for ${card.ownerName}! ₱${discount.toStringAsFixed(0)} saved.'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                    _scanCard(card.uid);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Redemption failed: $e'),
                        backgroundColor: AppTheme.errorRed,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                minimumSize: const Size(90, 36),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Confirm Redemption',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Card Not Found / Register ────────────────────────────────────────────────

  Widget _buildCardNotFoundResult() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.errorRed.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: AppTheme.errorRed.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.errorRed.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.credit_card_off_outlined,
                    color: AppTheme.errorRed, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Card Not Registered',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'UID: $_scannedUid',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textLight,
                          fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'This card is not linked to any customer.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textLight),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Register button
        if (!_showingRegisterFlow) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _showingRegisterFlow = true),
              icon: const Icon(Icons.person_add_outlined, color: Colors.white),
              label: const Text(
                'Register This Card to a Customer',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentBlue,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _resetScanner,
              icon: const Icon(Icons.nfc_outlined, size: 18),
              label: const Text('Scan Another Card'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                side: const BorderSide(color: AppTheme.borderGray),
              ),
            ),
          ),
        ] else
          _buildRegisterFlow(),
      ],
    );
  }

  Widget _buildRegisterFlow() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentBlue.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.person_search_outlined,
                  color: AppTheme.accentBlue, size: 18),
              SizedBox(width: 8),
              Text(
                'Search Customer',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppTheme.textDark),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Search by name, phone, or email to link this card.',
            style: TextStyle(fontSize: 11, color: AppTheme.textLight),
          ),
          const SizedBox(height: 12),

          // Action button to register brand new walk-in customer
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              onPressed: () => _openQuickRegisterCustomerModal(
                initialName: _searchController.text.trim().isNotEmpty
                    ? _searchController.text.trim()
                    : null,
              ),
              icon: const Icon(Icons.person_add_alt_1, size: 18, color: Colors.white),
              label: const Text(
                '+ Register New Walk-in Customer',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 12),

          const Row(
            children: [
              Expanded(child: Divider(color: AppTheme.borderGray)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('OR SEARCH EXISTING', style: TextStyle(fontSize: 10, color: AppTheme.textLight, fontWeight: FontWeight.bold)),
              ),
              Expanded(child: Divider(color: AppTheme.borderGray)),
            ],
          ),
          const SizedBox(height: 12),

          // Search field
          Container(
            decoration: BoxDecoration(
              color: AppTheme.softGray,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.borderGray),
            ),
            child: TextField(
              controller: _searchController,
              inputFormatters: InputFormatters.text(maxLength: 50),
              decoration: InputDecoration(
                hintText: 'Search Name, Phone, or Code (CUST-xxx)...',
                hintStyle:
                    const TextStyle(fontSize: 12, color: AppTheme.textLight),
                prefixIcon:
                    const Icon(Icons.search, size: 18, color: AppTheme.textLight),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchResults = []);
                        },
                      )
                    : null,
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              ),
              onChanged: _searchCustomers,
            ),
          ),

          const SizedBox(height: 10),

          // Results
          if (_isSearchingCustomers)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_searchResults.isEmpty &&
              _searchController.text.trim().length >= 2)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    'No existing customer found matching "${_searchController.text.trim()}".',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textDark),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _openQuickRegisterCustomerModal(
                      initialName: _searchController.text.trim(),
                    ),
                    icon: const Icon(Icons.add, size: 16, color: Colors.white),
                    label: Text(
                      'Create "${_searchController.text.trim()}" Now',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentBlue,
                      minimumSize: const Size(double.infinity, 36),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            )
          else
            ...(_searchResults.map((c) => _buildCustomerSearchResult(c))),

          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () =>
                setState(() => _showingRegisterFlow = false),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Cancel'),
            style: TextButton.styleFrom(
                foregroundColor: AppTheme.textLight),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerSearchResult(Map<String, dynamic> customer) {
    final firstName = customer['first_name'] as String? ?? '';
    final lastName = customer['last_name'] as String? ?? '';
    final name = '$firstName $lastName'.trim();
    final phone = customer['phone'] as String?;
    final email = customer['email'] as String?;
    final customerCode = customer['customer_code'] as String? ?? '';
    final isWalkIn = (customer['customer_type'] as String? ?? '') == 'walk_in';

    return GestureDetector(
      onTap: () => _registerCardToCustomer(customer),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.softGray,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.accentBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person,
                  color: AppTheme.accentBlue, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name.isNotEmpty ? name : 'Unknown Name',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppTheme.textDark),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isWalkIn
                              ? const Color(0xFF00897B).withValues(alpha: 0.12)
                              : AppTheme.accentBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isWalkIn ? 'Walk-in' : 'Mobile App',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isWalkIn ? const Color(0xFF00897B) : AppTheme.accentBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (customerCode.isNotEmpty) ...[
                        Text(
                          customerCode,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.accentBlue,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (phone != null)
                        Text(phone,
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.textLight)),
                      if (email != null && phone == null)
                        Text(email,
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.textLight)),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppTheme.textLight, size: 20),
          ],
        ),
      ),
    );
  }

  // ─── Error Card ───────────────────────────────────────────────────────────────

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.errorRed.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.errorRed),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Error Reading Card',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.errorRed)),
                const SizedBox(height: 4),
                Text(_error!,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textLight)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.accentBlue),
            onPressed: () => _scanCard(_scannedUid!),
          ),
        ],
      ),
    );
  }
}
