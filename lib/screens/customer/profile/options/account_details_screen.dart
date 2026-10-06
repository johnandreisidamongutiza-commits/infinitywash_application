import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../../../config/location_constants.dart';
import '../../../../services/profile_service.dart';
import '../../../../theme/app_theme.dart';
import '../../../../utils/app_error.dart';
import '../../../../utils/input_formatters.dart';
import '../../../../utils/validators.dart';
import '../../../../widgets/address_input_widget.dart';
import '../../../../widgets/custom_text_field.dart';
import '../../../../widgets/location_picker_widget.dart';

class CustomerAccountDetailsScreen extends StatefulWidget {
  const CustomerAccountDetailsScreen({super.key});

  @override
  State<CustomerAccountDetailsScreen> createState() =>
      _CustomerAccountDetailsScreenState();
}

class _CustomerAccountDetailsScreenState
    extends State<CustomerAccountDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _profileService = ProfileService();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _houseStreetController = TextEditingController();
  String? _selectedBarangay;
  final _customBarangayController = TextEditingController();
  final _landmarkController = TextEditingController();

  LatLng? _pinLocation;
  bool _pinChanged = false;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _houseStreetController.dispose();
    _customBarangayController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profileService.getProfile();

      if (!mounted) return;

      _firstNameController.text = profile['first_name'] ?? '';
      _lastNameController.text = profile['last_name'] ?? '';
      _phoneController.text = profile['phone'] ?? '';
      _emailController.text = profile['email'] ?? '';
      _landmarkController.text = profile['landmark'] ?? '';

      final savedAddress = (profile['address'] as String?) ?? '';
      if (savedAddress.isNotEmpty) {
        AddressInputWidget.parseAndPopulate(
          address: savedAddress,
          houseStreetController: _houseStreetController,
          setBarangay: (b) => _selectedBarangay = b,
          customBarangayController: _customBarangayController,
        );
      }

      final pinLat = (profile['pin_latitude'] as num?)?.toDouble();
      final pinLng = (profile['pin_longitude'] as num?)?.toDouble();
      if (pinLat != null && pinLng != null) {
        _pinLocation = LatLng(pinLat, pinLng);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not load account details. ${mapErrorToMessage(error)}',
            style: GoogleFonts.lexend(color: Colors.white),
          ),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    if (firstName.isEmpty || lastName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter both your first and last name',
            style: GoogleFonts.lexend(color: Colors.white),
          ),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final fullAddress = AddressInputWidget.buildFullAddress(
        houseStreet: _houseStreetController.text.trim(),
        selectedBarangay: _selectedBarangay,
        customBarangay: _customBarangayController.text.trim(),
      );

      await _profileService.updateProfile(
        firstName: firstName,
        lastName: lastName,
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        address: fullAddress,
        landmark: _landmarkController.text.trim(),
        pinLatitude: _pinChanged ? _pinLocation?.latitude : null,
        pinLongitude: _pinChanged ? _pinLocation?.longitude : null,
        removePin: _pinChanged && _pinLocation == null,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                'Account details updated successfully!',
                style: GoogleFonts.lexend(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapErrorToMessage(error),
            style: GoogleFonts.lexend(color: Colors.white),
          ),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Opens the shared map picker so the customer can move their pin.
  Future<void> _pickPinLocation() async {
    final result = await LocationPickerDialog.show(
      context,
      initialPosition: _pinLocation,
      enforceDeliveryRadius: true,
      title: 'Pin Your Location',
    );
    if (result != null && mounted) {
      setState(() {
        _pinLocation = result.coordinates;
        _pinChanged = true;
        if (_houseStreetController.text.trim().isEmpty &&
            result.address != null &&
            result.address!.isNotEmpty) {
          AddressInputWidget.parseAndPopulate(
            address: result.address!,
            houseStreetController: _houseStreetController,
            setBarangay: (v) => _selectedBarangay = v,
            customBarangayController: _customBarangayController,
          );
          if (!_houseStreetController.text.startsWith('Blk')) {
            _houseStreetController.text =
                'Blk _ Lot _, ${_houseStreetController.text}';
            _houseStreetController.selection =
                const TextSelection(baseOffset: 4, extentOffset: 5);
          }
        }
      });
    }
  }

  String _getInitials() {
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();
    if (first.isEmpty && last.isEmpty) return 'U';
    final f = first.isNotEmpty ? first[0].toUpperCase() : '';
    final l = last.isNotEmpty ? last[0].toUpperCase() : '';
    return '$f$l';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Account Details',
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppTheme.textDark,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textDark, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppTheme.accentBlue,
                strokeWidth: 2.5,
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderCard(),
                    const SizedBox(height: 20),
                    _buildSectionHeader(
                      icon: Icons.person_outline_rounded,
                      title: 'Personal Information',
                    ),
                    const SizedBox(height: 8),
                    _buildPersonalInfoCard(),
                    const SizedBox(height: 24),
                    _buildSectionHeader(
                      icon: Icons.home_outlined,
                      title: 'Default Delivery & Pickup Address',
                    ),
                    const SizedBox(height: 8),
                    _buildAddressCard(),
                    const SizedBox(height: 24),
                    _buildSectionHeader(
                      icon: Icons.pin_drop_outlined,
                      title: 'Pinned Meetup Zone (20m Radius)',
                    ),
                    const SizedBox(height: 8),
                    _buildPinLocationCard(),
                    const SizedBox(height: 32),
                    _buildSaveButton(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SECTION COMPONENTS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeaderCard() {
    final fullName =
        '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
            .trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryBlue,
                  AppTheme.accentBlue,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accentBlue.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              _getInitials(),
              style: GoogleFonts.lexend(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName.isEmpty ? 'Customer Account' : fullName,
                  style: GoogleFonts.lexend(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_user_rounded,
                          size: 13, color: AppTheme.accentBlue),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Verified Customer',
                          style: GoogleFonts.lexend(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.accentBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.accentBlue),
          const SizedBox(width: 8),
          // Expanded so a long section title wraps instead of overflowing.
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.lexend(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: CustomTextField(
                  label: 'First Name',
                  hint: 'First name',
                  prefixIcon: Icons.badge_outlined,
                  controller: _firstNameController,
                  validator: (v) => Validators.nameField(v, 'First name'),
                  maxLength: Validators.nameMax,
                  textCapitalization: TextCapitalization.words,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: CustomTextField(
                  label: 'Last Name',
                  hint: 'Last name',
                  prefixIcon: Icons.badge_outlined,
                  controller: _lastNameController,
                  validator: (v) => Validators.nameField(v, 'Last name'),
                  maxLength: Validators.nameMax,
                  textCapitalization: TextCapitalization.words,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          CustomTextField(
            label: 'Mobile Number',
            hint: '09XX-XXX-XXXX',
            prefixIcon: Icons.phone_android_outlined,
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: InputFormatters.phone(),
            validator: Validators.phone,
          ),
          const SizedBox(height: 16),
          CustomTextField(
            label: 'Email Address',
            hint: 'Email address',
            prefixIcon: Icons.email_outlined,
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            validator: Validators.optionalEmail,
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: AddressInputWidget(
        houseStreetController: _houseStreetController,
        customBarangayController: _customBarangayController,
        landmarkController: _landmarkController,
        selectedBarangay: _selectedBarangay,
        onBarangayChanged: (v) => setState(() => _selectedBarangay = v),
        fillColor: const Color(0xFFF8FAFC),
        borderRadius: 14,
      ),
    );
  }

  Widget _buildPinLocationCard() {
    final hasPin = _pinLocation != null;
    final distanceText =
        hasPin ? LocationHelper.getFormattedDistance(_pinLocation!) : null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasPin
              ? AppTheme.accentBlue.withValues(alpha: 0.6)
              : AppTheme.borderGray.withValues(alpha: 0.6),
          width: hasPin ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: hasPin
                ? AppTheme.accentBlue.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                  color: hasPin
                      ? AppTheme.accentBlue.withValues(alpha: 0.1)
                      : AppTheme.softGray,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hasPin
                      ? Icons.location_on_rounded
                      : Icons.location_off_outlined,
                  color: hasPin ? AppTheme.accentBlue : AppTheme.textLight,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          hasPin ? 'Location Pinned' : 'No Pin Set',
                          style: GoogleFonts.lexend(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: hasPin
                                ? AppTheme.textDark
                                : AppTheme.textLight,
                          ),
                        ),
                        if (hasPin) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: Colors.green.shade200, width: 0.5),
                            ),
                            child: Text(
                              'Active',
                              style: GoogleFonts.lexend(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasPin
                          ? '${_pinLocation!.latitude.toStringAsFixed(5)}, ${_pinLocation!.longitude.toStringAsFixed(5)} • $distanceText from shop'
                          : 'Riders use this to find your exact 20m meetup zone',
                      style: GoogleFonts.lexend(
                        fontSize: 12,
                        color: hasPin ? AppTheme.textDark : AppTheme.textLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickPinLocation,
                  icon: Icon(
                    hasPin
                        ? Icons.edit_location_alt_rounded
                        : Icons.add_location_alt_rounded,
                    size: 16,
                    color: AppTheme.accentBlue,
                  ),
                  label: Text(
                    hasPin ? 'Change Map Pin' : 'Set Map Pin Location',
                    style: GoogleFonts.lexend(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accentBlue,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.accentBlue, width: 1.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (hasPin) ...[
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Remove Pin',
                  onPressed: () {
                    setState(() {
                      _pinLocation = null;
                      _pinChanged = true;
                    });
                  },
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppTheme.errorRed),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.errorRed.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accentBlue,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: AppTheme.accentBlue.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            // scaleDown keeps the label intact (and on one line) inside the
            // button when the system font is enlarged.
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Save Information',
                      style: GoogleFonts.lexend(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
