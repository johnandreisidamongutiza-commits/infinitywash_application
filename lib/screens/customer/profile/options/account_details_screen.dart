import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../../services/profile_service.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/address_input_widget.dart';
import '../../../../widgets/custom_text_field.dart';
import '../../../../widgets/location_picker_widget.dart';

class CustomerAccountDetailsScreen extends StatefulWidget {
  const CustomerAccountDetailsScreen({super.key});

  @override
  State<CustomerAccountDetailsScreen> createState() => _CustomerAccountDetailsScreenState();
}

class _CustomerAccountDetailsScreenState extends State<CustomerAccountDetailsScreen> {
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
        SnackBar(content: Text('Could not load account details: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);

    try {
      final fullAddress = AddressInputWidget.buildFullAddress(
        houseStreet: _houseStreetController.text.trim(),
        selectedBarangay: _selectedBarangay,
        customBarangay: _customBarangayController.text.trim(),
      );

      await _profileService.updateProfile(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
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
        const SnackBar(content: Text('Account details updated successfully!')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update account details: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Opens the shared map picker so the customer can move their pin.
  /// Cancelling keeps the current pin; removing clears it (applied on Save).
  Future<void> _pickPinLocation() async {
    final result = await LocationPickerDialog.show(
      context,
      initialPosition: _pinLocation,
      // The picker only warns when the pin is outside the delivery
      // radius; it never blocks the customer from saving it.
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

  Widget _buildPinLocationCard() {
    final hasPin = _pinLocation != null;
    return InkWell(
      onTap: _pickPinLocation,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.softGray,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasPin ? AppTheme.accentBlue : AppTheme.borderGray,
            width: hasPin ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              color: hasPin ? AppTheme.accentBlue : AppTheme.textLight,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pin Location (20m Meetup Zone)',
                    style: AppTheme.lightTheme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasPin
                        ? '20m Meetup Zone • ${_pinLocation!.latitude.toStringAsFixed(6)}, '
                            '${_pinLocation!.longitude.toStringAsFixed(6)}'
                        : 'Not set - tap to drop a pin on the map',
                    style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
                      color: hasPin ? AppTheme.textDark : AppTheme.textLight,
                    ),
                  ),
                ],
              ),
            ),
            if (hasPin) ...[
              IconButton(
                tooltip: 'Change pin',
                icon: const Icon(Icons.edit_location_alt_outlined,
                    color: AppTheme.accentBlue),
                onPressed: _pickPinLocation,
              ),
              IconButton(
                tooltip: 'Remove pin',
                icon: const Icon(Icons.highlight_off_outlined,
                    color: AppTheme.errorRed),
                onPressed: () => setState(() {
                  _pinLocation = null;
                  _pinChanged = true;
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Account Details'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  CustomTextField(
                    label: 'First Name',
                    hint: 'First name',
                    prefixIcon: Icons.person_outline,
                    controller: _firstNameController,
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    label: 'Last Name',
                    hint: 'Last name',
                    prefixIcon: Icons.person_outline,
                    controller: _lastNameController,
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    label: 'Phone Number',
                    hint: 'Phone number',
                    prefixIcon: Icons.phone,
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    label: 'Email Address',
                    hint: 'Email address',
                    prefixIcon: Icons.email_outlined,
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  AddressInputWidget(
                    houseStreetController: _houseStreetController,
                    customBarangayController: _customBarangayController,
                    landmarkController: _landmarkController,
                    selectedBarangay: _selectedBarangay,
                    onBarangayChanged: (v) =>
                        setState(() => _selectedBarangay = v),
                    fillColor: Colors.white,
                    borderRadius: 16,
                  ),
                  const SizedBox(height: 16),
                  _buildPinLocationCard(),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentBlue,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Save Information',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
