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
import '../../../../widgets/editable_profile_avatar.dart';
import '../../../../widgets/location_picker_widget.dart';

class CustomerAccountDetailsScreen extends StatefulWidget {
  const CustomerAccountDetailsScreen({super.key});

  @override
  State<CustomerAccountDetailsScreen> createState() =>
      _CustomerAccountDetailsScreenState();
}

class _CustomerAccountDetailsScreenState
    extends State<CustomerAccountDetailsScreen> {
  final _personalFormKey = GlobalKey<FormState>();
  final _addressFormKey = GlobalKey<FormState>();
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
  String? _avatarUrl;
  bool _hasChanges = false;
  bool _isLoading = true;

  // Edit and saving states per card
  bool _isEditingPersonal = false;
  bool _isSavingPersonal = false;
  bool _isEditingAddress = false;
  bool _isSavingAddress = false;

  // Baseline values
  String _initialFirstName = '';
  String _initialLastName = '';
  String _initialPhone = '';
  String _initialEmail = '';
  String _initialHouseStreet = '';
  String? _initialBarangay;
  String _initialCustomBarangay = '';
  String _initialLandmark = '';
  LatLng? _initialPinLocation;

  bool get _hasPersonalChanges {
    return _firstNameController.text.trim() != _initialFirstName ||
        _lastNameController.text.trim() != _initialLastName ||
        _phoneController.text.trim() != _initialPhone ||
        _emailController.text.trim().toLowerCase() !=
            _initialEmail.toLowerCase();
  }

  bool get _hasAddressChanges {
    final currentCustom = _selectedBarangay == 'Other'
        ? _customBarangayController.text.trim()
        : '';
    final initialCustom =
        _initialBarangay == 'Other' ? _initialCustomBarangay : '';

    return _houseStreetController.text.trim() != _initialHouseStreet ||
        _selectedBarangay != _initialBarangay ||
        currentCustom != initialCustom ||
        _landmarkController.text.trim() != _initialLandmark ||
        _pinLocation != _initialPinLocation;
  }

  bool get _hasUnsavedChanges =>
      (_isEditingPersonal && _hasPersonalChanges) ||
      (_isEditingAddress && _hasAddressChanges);

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _firstNameController.addListener(_onFieldChanged);
    _lastNameController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
    _emailController.addListener(_onFieldChanged);
    _houseStreetController.addListener(_onFieldChanged);
    _customBarangayController.addListener(_onFieldChanged);
    _landmarkController.addListener(_onFieldChanged);
    _loadProfile();
  }

  @override
  void dispose() {
    _firstNameController.removeListener(_onFieldChanged);
    _lastNameController.removeListener(_onFieldChanged);
    _phoneController.removeListener(_onFieldChanged);
    _emailController.removeListener(_onFieldChanged);
    _houseStreetController.removeListener(_onFieldChanged);
    _customBarangayController.removeListener(_onFieldChanged);
    _landmarkController.removeListener(_onFieldChanged);
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
      _avatarUrl = profile['avatar_url'] as String?;

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

      _initialFirstName = _firstNameController.text.trim();
      _initialLastName = _lastNameController.text.trim();
      _initialPhone = _phoneController.text.trim();
      _initialEmail = _emailController.text.trim();
      _initialHouseStreet = _houseStreetController.text.trim();
      _initialBarangay = _selectedBarangay;
      _initialCustomBarangay = _customBarangayController.text.trim();
      _initialLandmark = _landmarkController.text.trim();
      _initialPinLocation = _pinLocation;
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

  // ─────────────────────────────────────────────────────────────────────────
  // CARD ACTIONS: PERSONAL INFO
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _savePersonalInfo() async {
    if (!_hasPersonalChanges) {
      setState(() => _isEditingPersonal = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No changes made to personal information.',
                  style: GoogleFonts.lexend(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.primaryBlue,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    if (_personalFormKey.currentState?.validate() != true) return;

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

    setState(() => _isSavingPersonal = true);

    try {
      final currentAddress = AddressInputWidget.buildFullAddress(
        houseStreet: _initialHouseStreet,
        selectedBarangay: _initialBarangay,
        customBarangay: _initialCustomBarangay,
      );

      await _profileService.updateProfile(
        firstName: firstName,
        lastName: lastName,
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim().toLowerCase(),
        address: currentAddress.isNotEmpty ? currentAddress : null,
        landmark: _initialLandmark.isNotEmpty ? _initialLandmark : null,
        pinLatitude: _pinLocation?.latitude,
        pinLongitude: _pinLocation?.longitude,
      );

      _initialFirstName = firstName;
      _initialLastName = lastName;
      _initialPhone = _phoneController.text.trim();
      _initialEmail = _emailController.text.trim().toLowerCase();
      _hasChanges = true;

      if (!mounted) return;
      setState(() => _isEditingPersonal = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Personal information updated successfully!',
                  style: GoogleFonts.lexend(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
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
        setState(() => _isSavingPersonal = false);
      }
    }
  }

  void _cancelPersonalEdit() {
    _personalFormKey.currentState?.reset();
    _firstNameController.text = _initialFirstName;
    _lastNameController.text = _initialLastName;
    _phoneController.text = _initialPhone;
    _emailController.text = _initialEmail;
    setState(() => _isEditingPersonal = false);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CARD ACTIONS: ADDRESS & PIN LOCATION
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _saveAddress() async {
    if (!_hasAddressChanges) {
      setState(() => _isEditingAddress = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No changes made to address or meetup pin.',
                  style: GoogleFonts.lexend(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.primaryBlue,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    if (_addressFormKey.currentState?.validate() != true) return;

    final houseStreet = _houseStreetController.text.trim();
    final barangay = _selectedBarangay == 'Other'
        ? _customBarangayController.text.trim()
        : _selectedBarangay ?? '';

    if (houseStreet.isEmpty || barangay.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please complete your street and barangay',
            style: GoogleFonts.lexend(color: Colors.white),
          ),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }

    setState(() => _isSavingAddress = true);

    try {
      final fullAddress = AddressInputWidget.buildFullAddress(
        houseStreet: houseStreet,
        selectedBarangay: _selectedBarangay,
        customBarangay: _customBarangayController.text.trim(),
      );

      final landmark = _landmarkController.text.trim();

      await _profileService.updateProfile(
        firstName: _initialFirstName,
        lastName: _initialLastName,
        phone: _initialPhone,
        email: _initialEmail.isNotEmpty ? _initialEmail : null,
        address: fullAddress,
        landmark: landmark.isNotEmpty ? landmark : null,
        pinLatitude: _pinLocation?.latitude,
        pinLongitude: _pinLocation?.longitude,
        removePin: _pinLocation == null,
      );

      _initialHouseStreet = houseStreet;
      _initialBarangay = _selectedBarangay;
      _initialCustomBarangay = _customBarangayController.text.trim();
      _initialLandmark = landmark;
      _initialPinLocation = _pinLocation;
      _hasChanges = true;

      if (!mounted) return;
      setState(() => _isEditingAddress = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Address and meetup pin updated successfully!',
                  style: GoogleFonts.lexend(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
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
        setState(() => _isSavingAddress = false);
      }
    }
  }

  void _cancelAddressEdit() {
    _addressFormKey.currentState?.reset();
    _houseStreetController.text = _initialHouseStreet;
    _selectedBarangay = _initialBarangay;
    _customBarangayController.text = _initialCustomBarangay;
    _landmarkController.text = _initialLandmark;
    setState(() {
      _pinLocation = _initialPinLocation;
      _isEditingAddress = false;
    });
  }

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
        if (_houseStreetController.text.trim().isEmpty &&
            result.address != null &&
            result.address!.isNotEmpty) {
          AddressInputWidget.parseAndPopulate(
            address: result.address!,
            houseStreetController: _houseStreetController,
            setBarangay: (v) => _selectedBarangay = v,
            customBarangayController: _customBarangayController,
          );
        }
      });
    }
  }

  void _removePinLocation() {
    setState(() {
      _pinLocation = null;
    });
  }

  Future<bool> _showDiscardChangesDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Discard Changes?',
          style: GoogleFonts.lexend(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Text(
          'You have unsaved changes in one of your sections. Are you sure you want to discard them and exit?',
          style: GoogleFonts.lexend(fontSize: 14, color: AppTheme.textDark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Keep Editing',
              style: GoogleFonts.lexend(
                fontWeight: FontWeight.w600,
                color: AppTheme.accentBlue,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorRed),
            child: Text(
              'Discard',
              style: GoogleFonts.lexend(
                fontWeight: FontWeight.bold,
                color: AppTheme.errorRed,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _showDiscardChangesDialog();
        if (shouldPop && context.mounted) {
          Navigator.pop(context, _hasChanges);
        }
      },
      child: Scaffold(
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
            onPressed: () async {
              if (_hasUnsavedChanges) {
                final shouldPop = await _showDiscardChangesDialog();
                if (shouldPop && context.mounted) {
                  Navigator.pop(context, _hasChanges);
                }
              } else {
                Navigator.pop(context, _hasChanges);
              }
            },
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderCard(),
                    const SizedBox(height: 20),
                    _buildSectionHeader(
                      icon: Icons.person_outline_rounded,
                      title: 'Personal Information',
                      action: _isEditingPersonal
                          ? null
                          : _buildEditButton(
                              onPressed: () =>
                                  setState(() => _isEditingPersonal = true),
                            ),
                    ),
                    const SizedBox(height: 8),
                    _buildPersonalInfoCard(),
                    const SizedBox(height: 24),
                    _buildSectionHeader(
                      icon: Icons.home_outlined,
                      title: 'Default Delivery & Pickup Address',
                      action: _isEditingAddress
                          ? null
                          : _buildEditButton(
                              onPressed: () =>
                                  setState(() => _isEditingAddress = true),
                            ),
                    ),
                    const SizedBox(height: 8),
                    _buildAddressCard(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI HELPERS & COMPONENTS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEditButton({required VoidCallback onPressed}) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.edit_outlined, size: 15, color: AppTheme.accentBlue),
      label: Text(
        'Edit',
        style: GoogleFonts.lexend(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.accentBlue,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: AppTheme.accentBlue.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    String placeholder = 'Not set',
  }) {
    final hasValue = value.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.accentBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppTheme.accentBlue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.lexend(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textLight,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hasValue ? value : placeholder,
                style: GoogleFonts.lexend(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: hasValue
                      ? AppTheme.textDark
                      : AppTheme.textLight.withValues(alpha: 0.7),
                  fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCardActionButtons({
    required VoidCallback onCancel,
    required VoidCallback onSave,
    required bool isSaving,
    bool canSave = true,
    String saveLabel = 'Save',
  }) {
    const buttonHeight = 46.0;
    final borderRadius = BorderRadius.circular(12);

    return SizedBox(
      height: buttonHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: isSaving ? null : onCancel,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.softGray,
                foregroundColor: AppTheme.textDark,
                elevation: 0,
                shadowColor: Colors.transparent,
                side: BorderSide(
                  color: AppTheme.borderGray.withValues(alpha: 0.8),
                  width: 1,
                ),
                shape: RoundedRectangleBorder(borderRadius: borderRadius),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppTheme.textDark,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Cancel',
                    style: GoogleFonts.lexend(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: (isSaving || !canSave) ? null : onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentBlue,
                disabledBackgroundColor: Colors.grey.shade300,
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.grey.shade600,
                elevation: 0,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: borderRadius),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: canSave ? Colors.white : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          saveLabel,
                          style: GoogleFonts.lexend(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color:
                                canSave ? Colors.white : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

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
          EditableProfileAvatar(
            avatarUrl: _avatarUrl,
            name: fullName,
            role: 'Customer',
            radius: 30,
            onAvatarChanged: (newUrl) {
              setState(() {
                _avatarUrl = newUrl;
                _hasChanges = true;
              });
            },
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
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.accentBlue),
          const SizedBox(width: 8),
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
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _buildPersonalInfoCard() {
    if (!_isEditingPersonal) {
      final fullName =
          '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
              .trim();

      return Container(
        width: double.infinity,
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(
              icon: Icons.person_outline_rounded,
              label: 'Full Name',
              value: fullName,
              placeholder: 'No name set',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(
                height: 1,
                color: AppTheme.borderGray.withValues(alpha: 0.4),
              ),
            ),
            _buildInfoRow(
              icon: Icons.phone_android_outlined,
              label: 'Mobile Number',
              value: _phoneController.text.trim(),
              placeholder: 'No phone number set',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(
                height: 1,
                color: AppTheme.borderGray.withValues(alpha: 0.4),
              ),
            ),
            _buildInfoRow(
              icon: Icons.email_outlined,
              label: 'Email Address',
              value: _emailController.text.trim(),
              placeholder: 'No email address set',
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.accentBlue.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentBlue.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: _personalFormKey,
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
              inputFormatters: InputFormatters.email(),
              validator: Validators.emailField,
            ),
            const SizedBox(height: 16),
            _buildCardActionButtons(
              onCancel: _cancelPersonalEdit,
              onSave: _savePersonalInfo,
              isSaving: _isSavingPersonal,
              canSave: _hasPersonalChanges,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressCard() {
    if (!_isEditingAddress) {
      final fullAddress = AddressInputWidget.buildFullAddress(
        houseStreet: _initialHouseStreet,
        selectedBarangay: _initialBarangay,
        customBarangay: _initialCustomBarangay,
      );
      final hasAddress = fullAddress.trim().isNotEmpty;
      final hasLandmark = _initialLandmark.trim().isNotEmpty;
      final hasPin = _initialPinLocation != null;
      final distanceText = hasPin
          ? LocationHelper.getFormattedDistance(_initialPinLocation!)
          : null;

      return Container(
        width: double.infinity,
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(
              icon: Icons.home_outlined,
              label: 'Delivery & Pickup Address',
              value: hasAddress ? fullAddress : '',
              placeholder: 'No delivery address specified yet',
            ),
            if (hasLandmark) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(
                  height: 1,
                  color: AppTheme.borderGray.withValues(alpha: 0.4),
                ),
              ),
              _buildInfoRow(
                icon: Icons.near_me_outlined,
                label: 'Landmark / Meetup Note',
                value: _initialLandmark,
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(
                height: 1,
                color: AppTheme.borderGray.withValues(alpha: 0.4),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: hasPin
                        ? AppTheme.accentBlue.withValues(alpha: 0.08)
                        : AppTheme.softGray,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    hasPin
                        ? Icons.location_on_rounded
                        : Icons.location_off_outlined,
                    size: 18,
                    color: hasPin ? AppTheme.accentBlue : AppTheme.textLight,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Pinned Meetup Zone (20m Radius)',
                              style: GoogleFonts.lexend(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textLight,
                              ),
                              overflow: TextOverflow.ellipsis,
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
                            ? '${_initialPinLocation!.latitude.toStringAsFixed(5)}, ${_initialPinLocation!.longitude.toStringAsFixed(5)} • $distanceText from shop'
                            : 'No map pin set',
                        style: GoogleFonts.lexend(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: hasPin
                              ? AppTheme.textDark
                              : AppTheme.textLight.withValues(alpha: 0.7),
                          fontStyle:
                              hasPin ? FontStyle.normal : FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Riders use this to find your exact 20m meetup zone',
                        style: GoogleFonts.lexend(
                          fontSize: 11,
                          color: AppTheme.textLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final hasPin = _pinLocation != null;
    final distanceText =
        hasPin ? LocationHelper.getFormattedDistance(_pinLocation!) : null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.accentBlue.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentBlue.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: _addressFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AddressInputWidget(
              houseStreetController: _houseStreetController,
              customBarangayController: _customBarangayController,
              landmarkController: _landmarkController,
              selectedBarangay: _selectedBarangay,
              onBarangayChanged: (v) => setState(() => _selectedBarangay = v),
              fillColor: const Color(0xFFF8FAFC),
              borderRadius: 14,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasPin
                      ? AppTheme.accentBlue.withValues(alpha: 0.4)
                      : AppTheme.borderGray.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: hasPin
                              ? AppTheme.accentBlue.withValues(alpha: 0.1)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          hasPin
                              ? Icons.location_on_rounded
                              : Icons.location_off_outlined,
                          color:
                              hasPin ? AppTheme.accentBlue : AppTheme.textLight,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Pinned Meetup Zone',
                                  style: GoogleFonts.lexend(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                                if (hasPin) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: Colors.green.shade200,
                                          width: 0.5),
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
                            Text(
                              hasPin
                                  ? '${_pinLocation!.latitude.toStringAsFixed(5)}, ${_pinLocation!.longitude.toStringAsFixed(5)} • $distanceText from shop'
                                  : 'Riders use this to find your exact 20m meetup zone',
                              style: GoogleFonts.lexend(
                                fontSize: 11,
                                color: hasPin
                                    ? AppTheme.textDark
                                    : AppTheme.textLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
                            backgroundColor: Colors.white,
                            side: const BorderSide(
                                color: AppTheme.accentBlue, width: 1.2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      if (hasPin) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Remove Pin',
                          onPressed: _removePinLocation,
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: AppTheme.errorRed, size: 20),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                AppTheme.errorRed.withValues(alpha: 0.08),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.all(10),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _buildCardActionButtons(
              onCancel: _cancelAddressEdit,
              onSave: _saveAddress,
              isSaving: _isSavingAddress,
              canSave: _hasAddressChanges,
            ),
          ],
        ),
      ),
    );
  }
}
