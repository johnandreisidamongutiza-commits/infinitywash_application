import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/custom_text_field.dart';
import '../../../models/order.dart';
import '../../../services/mock_data_service.dart';

class RequestServiceFlow extends StatefulWidget {
  const RequestServiceFlow({super.key});

  @override
  State<RequestServiceFlow> createState() => _RequestServiceFlowState();
}

class _RequestServiceFlowState extends State<RequestServiceFlow> {
  int _currentStep = 1;
  final CollectionMethod _selectedCollection = CollectionMethod.riderPickup;
  ReturnMethod _selectedReturn = ReturnMethod.delivery;
  String _selectedPaymentPreference = 'GCash';

  // Profile default data
  static const String _defaultName = 'John Customer';
  static const String _defaultPhone = '0912-345-6789';
  static const String _defaultAddress = '123 Laundry St, Clean City';
  static const String _defaultLandmark = 'Near the blue gate';

  // Active details for this order
  String _customerName = _defaultName;
  String _phoneNumber = _defaultPhone;
  String _pickupAddress = _defaultAddress;
  String _landmark = _defaultLandmark;
  bool _isUsingCustomDetails = false;

  final TextEditingController _instructionsController = TextEditingController();

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  void _resetToProfileAddress() {
    setState(() {
      _customerName = _defaultName;
      _phoneNumber = _defaultPhone;
      _pickupAddress = _defaultAddress;
      _landmark = _defaultLandmark;
      _isUsingCustomDetails = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reset to saved profile address.')),
    );
  }

  void _showEditAddressModal() {
    final nameCtrl = TextEditingController(text: _customerName);
    final phoneCtrl = TextEditingController(text: _phoneNumber);
    final addressCtrl = TextEditingController(text: _pickupAddress);
    final landmarkCtrl = TextEditingController(text: _landmark);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.borderGray,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Change Pick-up Details',
                      style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontSize: 18),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Update your contact or pickup address for this request only.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textLight),
                ),
                const SizedBox(height: 20),
                CustomTextField(
                  label: 'Contact Name',
                  hint: 'Enter contact name',
                  prefixIcon: Icons.person_outline,
                  controller: nameCtrl,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Phone Number',
                  hint: '09XX-XXX-XXXX',
                  prefixIcon: Icons.phone_android,
                  controller: phoneCtrl,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Pick-up Address',
                  hint: 'Enter pickup address',
                  prefixIcon: Icons.location_on_outlined,
                  controller: addressCtrl,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Landmark / Note (Optional)',
                  hint: 'e.g. Near blue gate, 2nd floor apt',
                  prefixIcon: Icons.assistant_navigation,
                  controller: landmarkCtrl,
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _customerName = nameCtrl.text.trim().isEmpty ? _defaultName : nameCtrl.text.trim();
                      _phoneNumber = phoneCtrl.text.trim().isEmpty ? _defaultPhone : phoneCtrl.text.trim();
                      _pickupAddress = addressCtrl.text.trim().isEmpty ? _defaultAddress : addressCtrl.text.trim();
                      _landmark = landmarkCtrl.text.trim();
                      _isUsingCustomDetails = true;
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save for This Order'),
                ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _resetToProfileAddress();
                    },
                    child: const Text(
                      'Use Saved Profile Address',
                      style: TextStyle(color: AppTheme.textLight, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
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
        title: Text(_currentStep == 3 ? 'Request Status' : 'Request Service'),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(_currentStep == 2 ? Icons.arrow_back : Icons.close, color: AppTheme.textDark),
          onPressed: () {
            if (_currentStep == 2) {
              setState(() => _currentStep = 1);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: _buildStepContent(),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 1:
        return _buildServiceSelection();
      case 2:
        return _buildDetailsForm();
      case 3:
        return _buildWaitingApproval();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildServiceSelection() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Collection Method',
              style: AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              'A rider will be dispatched to your address for laundry collection.',
              style: AppTheme.lightTheme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _buildSelectableCard(
              'Rider Pick-up',
              'Door-to-door laundry collection from your address',
              Icons.delivery_dining,
              true,
              () {},
            ),
            const SizedBox(height: 30),
            Text(
              'Return Method',
              style: AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose how you would like to receive your cleaned laundry.',
              style: AppTheme.lightTheme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _buildSelectableCard(
              'Rider Delivery',
              'We will deliver it back to your address',
              Icons.local_shipping_outlined,
              _selectedReturn == ReturnMethod.delivery,
              () => setState(() => _selectedReturn = ReturnMethod.delivery),
            ),
            const SizedBox(height: 16),
            _buildSelectableCard(
              'Shop Pickup',
              'Pick it up at our shop when ready',
              Icons.storefront_outlined,
              _selectedReturn == ReturnMethod.shopPickup,
              () => setState(() => _selectedReturn = ReturnMethod.shopPickup),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => setState(() => _currentStep = 2),
              child: const Text('Continue'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectableCard(
    String title,
    String subtitle,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: isSelected ? AppStyles.selectedCardDecoration : AppStyles.cardDecoration,
        child: Row(
          children: [
            Icon(icon, color: isSelected ? AppTheme.accentBlue : AppTheme.textLight, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text(subtitle, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            if (isSelected) const Icon(Icons.check_circle, color: AppTheme.accentBlue),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsForm() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pick-up & Contact Details',
              style: AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 6),
            Text(
              'Confirm where our rider should collect your laundry.',
              style: AppTheme.lightTheme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),

            // Saved Profile Location Card
            _buildSavedLocationCard(),

            const SizedBox(height: 20),

            // Service Summary Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.6)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_shipping_outlined, color: AppTheme.accentBlue, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Selected Service',
                          style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                        ),
                        Text(
                          'Rider Pick-up  •  ${_selectedReturn == ReturnMethod.delivery ? 'Rider Delivery' : 'Shop Pickup'}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _currentStep = 1),
                    child: const Text(
                      'Change',
                      style: TextStyle(color: AppTheme.accentBlue, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Special Instructions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Special Instructions', style: AppTheme.lightTheme.textTheme.titleMedium),
                const Text('Optional', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _instructionsController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'e.g. Separate whites, delicate garments, ring doorbell twice...',
                hintStyle: TextStyle(color: AppTheme.textLight.withValues(alpha: 0.5)),
                filled: true,
                fillColor: AppTheme.softGray,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),

            const SizedBox(height: 24),

            // Payment Method Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Payment Method',
                    style: AppTheme.lightTheme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Pay After Weighing',
                    style: TextStyle(
                      color: AppTheme.accentBlue,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Select your preferred way to pay once our staff verifies your laundry weight.',
              style: TextStyle(fontSize: 12, color: AppTheme.textLight),
            ),
            const SizedBox(height: 12),

            // GCash Option
            GestureDetector(
              onTap: () => setState(() => _selectedPaymentPreference = 'GCash'),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _selectedPaymentPreference == 'GCash' ? AppTheme.accentBlue : AppTheme.borderGray,
                    width: _selectedPaymentPreference == 'GCash' ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _selectedPaymentPreference == 'GCash' ? AppTheme.accentBlue.withValues(alpha: 0.1) : AppTheme.softGray,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.account_balance_wallet_outlined, color: AppTheme.accentBlue, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('GCash / E-Wallet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          SizedBox(height: 2),
                          Text('Pay via QR or number once weighed', style: TextStyle(fontSize: 11, color: AppTheme.textLight)),
                        ],
                      ),
                    ),
                    Icon(
                      _selectedPaymentPreference == 'GCash' ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: _selectedPaymentPreference == 'GCash' ? AppTheme.accentBlue : AppTheme.textLight,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Cash on Delivery Option
            GestureDetector(
              onTap: () => setState(() => _selectedPaymentPreference = 'Cash on Delivery'),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _selectedPaymentPreference == 'Cash on Delivery' ? AppTheme.accentBlue : AppTheme.borderGray,
                    width: _selectedPaymentPreference == 'Cash on Delivery' ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _selectedPaymentPreference == 'Cash on Delivery' ? AppTheme.accentBlue.withValues(alpha: 0.1) : AppTheme.softGray,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.payments_outlined, color: Colors.green, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cash on Delivery / Pickup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          SizedBox(height: 2),
                          Text('Pay cash to rider upon delivery', style: TextStyle(fontSize: 11, color: AppTheme.textLight)),
                        ],
                      ),
                    ),
                    Icon(
                      _selectedPaymentPreference == 'Cash on Delivery' ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: _selectedPaymentPreference == 'Cash on Delivery' ? AppTheme.accentBlue : AppTheme.textLight,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Official Pricing Card (₱170 Full Service)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderGray),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.local_laundry_service_outlined, color: AppTheme.accentBlue, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'FULL SERVICE: Wash, Dry & Fold',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '₱170.00',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '✓ Detergent + Fab Con included with every full service load.',
                    style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Load limits: Regular 8kg • Heavy 6kg • Beddings 5kg • Comforter 1pc',
                    style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Submit Button
            ElevatedButton(
              onPressed: () {
                final String fullNote = [
                  if (_landmark.isNotEmpty) 'Landmark: $_landmark',
                  if (_instructionsController.text.trim().isNotEmpty) _instructionsController.text.trim(),
                  'Payment: $_selectedPaymentPreference',
                ].join(' | ');

                final newRequest = LaundryOrder(
                  id: 'IW-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
                  customerName: _customerName,
                  channel: OrderChannel.online,
                  collectionMethod: _selectedCollection,
                  returnMethod: _selectedReturn,
                  status: OrderStatus.pending_approval,
                  paymentStatus: PaymentStatus.unpaid,
                  loads: [
                    OrderLoad(
                      loadNumber: 1,
                      category: 'Regular Clothing',
                      weight: 0, // Staff will input weight when inspecting
                      categoryLimit: 8.0,
                      unit: 'kg',
                      description: 'T-shirts, shorts, sleeveless, socks, underwear',
                      isOverLimit: false,
                      loadStatus: LoadStatus.queued,
                    ),
                  ],
                  instructions: 'Pickup Address: $_pickupAddress${fullNote.isNotEmpty ? ' ($fullNote)' : ''}',
                  createdAt: DateTime.now(),
                );

                MockDataService().addRequest(newRequest);

                setState(() => _currentStep = 3);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('Submit Request'),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedLocationCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _isUsingCustomDetails
                      ? AppTheme.teamMemberIconOrange.withValues(alpha: 0.12)
                      : AppTheme.accentBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isUsingCustomDetails ? Icons.edit_location_alt : Icons.home_outlined,
                      size: 14,
                      color: _isUsingCustomDetails ? AppTheme.teamMemberIconOrange : AppTheme.accentBlue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isUsingCustomDetails ? 'Custom Address (This Order)' : 'Saved Profile Address',
                      style: TextStyle(
                        color: _isUsingCustomDetails ? AppTheme.teamMemberIconOrange : AppTheme.accentBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _showEditAddressModal,
                icon: const Icon(Icons.edit_outlined, size: 16, color: AppTheme.accentBlue),
                label: const Text(
                  'Change',
                  style: TextStyle(color: AppTheme.accentBlue, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Customer Name & Phone
          Row(
            children: [
              const Icon(Icons.person_outline, size: 18, color: AppTheme.textLight),
              const SizedBox(width: 10),
              Text(
                _customerName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
              ),
              const SizedBox(width: 8),
              const Text('•', style: TextStyle(color: AppTheme.textLight)),
              const SizedBox(width: 8),
              Text(
                _phoneNumber,
                style: const TextStyle(fontSize: 14, color: AppTheme.textLight),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Address
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_outlined, size: 18, color: AppTheme.errorRed),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pickupAddress,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textDark),
                    ),
                    if (_landmark.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Landmark: $_landmark',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (_isUsingCustomDetails) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: _resetToProfileAddress,
                child: const Text(
                  'Reset to default profile address',
                  style: TextStyle(fontSize: 11, color: AppTheme.accentBlue, decoration: TextDecoration.underline),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWaitingApproval() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, size: 48, color: Colors.green),
            ),
            const SizedBox(height: 16),
            Text('Request Placed!', style: AppTheme.lightTheme.textTheme.headlineMedium),
            const SizedBox(height: 6),
            const Text(
              'Your laundry pickup request has been dispatched to InfinityWash.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textLight, fontSize: 13),
            ),
            const SizedBox(height: 24),

            // Order Timeline Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.borderGray),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Order Progress',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _selectedPaymentPreference,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // Step 1: Request Confirmed
                  _buildTimelineItem(
                    icon: Icons.check_circle,
                    iconColor: Colors.green,
                    title: '1. Request Received',
                    subtitle: 'Our branch is coordinating rider pickup for $_pickupAddress.',
                    isDone: true,
                  ),
                  const SizedBox(height: 16),

                  // Step 2: Pickup & Store Weighing
                  _buildTimelineItem(
                    icon: Icons.scale_outlined,
                    iconColor: AppTheme.accentBlue,
                    title: '2. Pickup & Store Inspection',
                    subtitle: 'Laundry will be verified on our store scale (Full Service: ₱170.00 / load).',
                    isActive: true,
                  ),
                  const SizedBox(height: 16),

                  // Step 3: Verified Bill & Payment
                  _buildTimelineItem(
                    icon: Icons.receipt_long_outlined,
                    iconColor: AppTheme.textLight,
                    title: '3. Verified Bill & Payment',
                    subtitle: _selectedPaymentPreference == 'GCash'
                        ? 'You will receive an alert to review verified weight and pay via GCash.'
                        : 'Exact cash total will be confirmed for payment upon delivery.',
                    isPending: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('View in Active Orders'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                'Back to Home',
                style: TextStyle(color: AppTheme.textLight, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    bool isDone = false,
    bool isActive = false,
    bool isPending = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: isPending ? 0.08 : 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isPending ? AppTheme.textLight : AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: isPending ? AppTheme.textLight.withValues(alpha: 0.7) : AppTheme.textLight,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
