import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/legal_documents.dart';
import '../../theme/app_theme.dart';
import '../../utils/input_formatters.dart';
import '../../utils/validators.dart';
import '../../services/connectivity_service.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/location_picker_widget.dart';
import '../../widgets/address_input_widget.dart';
import '../../config/location_constants.dart';
import '../../services/legal_service.dart';
import '../../services/customer_registration_service.dart';
import '../../services/auth_service.dart';
import '../../services/google_sign_in_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/save_account_prompt.dart';
import '../../widgets/legal_consent_checkbox.dart';
import 'customer_main_screen.dart';

class CustomerRegistrationScreen extends StatefulWidget {
  const CustomerRegistrationScreen({super.key});

  /// Lets the underlying login route leave Google OAuth callbacks to this
  /// registration route while it is open above the login screen.
  static bool googleSignupInProgress = false;

  @override
  State<CustomerRegistrationScreen> createState() => _CustomerRegistrationScreenState();
}

class _CustomerRegistrationScreenState extends State<CustomerRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  // 3-part address
  final _houseStreetController = TextEditingController();
  String? _selectedBarangay;
  final _customBarangayController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpController = TextEditingController();
  final _registrationService = CustomerRegistrationService();
  final _authService = AuthService();
  final _legalService = LegalService();
  StreamSubscription<AuthState>? _authSubscription;
  bool _isLoading = false;
  bool _handlingGoogleCallback = false;
  bool _isGoogleRegistration = false;
  bool _isPendingResume = false;
  int _step = 0;

  /// Terms of Service / Privacy Policy consent. Server-enforced: the
  /// registration trigger refuses the sign-up without it.
  bool _agreedToLegal = false;
  bool _saveAccount = true;
  LatLng? _selectedLocation;
  String? _selectedAddress;

  @override
  void initState() {
    super.initState();
    _authSubscription = SupabaseService.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn &&
          (CustomerRegistrationScreen.googleSignupInProgress ||
              state.session?.user.appMetadata['provider'] == 'google')) {
        _finishGoogleRegistration();
      }
    });
  }

  @override
  void dispose() {
    CustomerRegistrationScreen.googleSignupInProgress = false;
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _houseStreetController.dispose();
    _customBarangayController.dispose();
    _landmarkController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _continueWithGoogle() async {
    if (!await ConnectivityService.instance.checkNow()) {
      _showMessage('No internet connection. Please check your connection and try again.');
      return;
    }
    CustomerRegistrationScreen.googleSignupInProgress = true;
    setState(() => _isLoading = true);
    try {
      await GoogleSignInService.signIn();
      await _finishGoogleRegistration();
    } catch (error) {
      CustomerRegistrationScreen.googleSignupInProgress = false;
      if (mounted && !GoogleSignInService.isCancelled(error)) {
        _showMessage(GoogleSignInService.errorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _finishGoogleRegistration() async {
    if (_handlingGoogleCallback) return;
    _handlingGoogleCallback = true;
    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) return;
      final profile = await SupabaseService.client
          .from('profiles')
          .select('role, status, first_name, last_name, phone, address, landmark')
          .eq('supabase_user_id', user.id)
          .maybeSingle();
      if (!mounted) return;
      if (profile != null && profile['role'] != 'customer') {
        await _authService.signOut();
        if (mounted) _showMessage('This Google account is already registered. Please sign in instead.');
        return;
      }
      if (profile != null && await _authService.isCustomerProfileComplete()) {
        if (!mounted) return;
        if (_saveAccount) {
          await _authService.rememberCurrentSession();
        }
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const CustomerMainScreen()),
          (_) => false,
        );
        return;
      }
      if (profile != null && profile['status'] != 'active') {
        await _authService.signOut();
        if (mounted) _showMessage('This account cannot be registered right now. Please contact support.');
        return;
      }
      final metadata = user.userMetadata ?? <String, dynamic>{};
      final fullName = (metadata['full_name'] ?? metadata['name'] ?? '').toString().trim();
      final nameParts = fullName.isEmpty ? <String>[] : fullName.split(RegExp(r'\s+'));
      setState(() {
        _isGoogleRegistration = true;
        _firstNameController.text = (profile?['first_name'] ?? metadata['given_name'] ?? metadata['first_name'] ?? (nameParts.isNotEmpty ? nameParts.first : '')).toString();
        _lastNameController.text = (profile?['last_name'] ?? metadata['family_name'] ?? metadata['last_name'] ?? (nameParts.length > 1 ? nameParts.skip(1).join(' ') : '')).toString();
        _emailController.text = (user.email ?? '').trim();
        if (profile != null) {
          _phoneController.text = (profile['phone'] ?? '').toString();
          _houseStreetController.text = (profile['address'] ?? '').toString();
          _landmarkController.text = (profile['landmark'] ?? '').toString();
        }
        _step = 1;
      });
      _showMessage('${user.email ?? 'Your email'} is connected successfully. Continue to complete your profile.', isError: false);
    } catch (error) {
      if (mounted) _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      CustomerRegistrationScreen.googleSignupInProgress = false;
      _handlingGoogleCallback = false;
    }
  }

  Future<Map<String, dynamic>> _registrationData() async {
    final address = AddressInputWidget.buildFullAddress(
      houseStreet: _houseStreetController.text.trim(),
      selectedBarangay: _selectedBarangay,
      customBarangay: _customBarangayController.text.trim(),
    );
    return {
      'first_name': Validators.cleanName(_firstNameController.text),
      'last_name': Validators.cleanName(_lastNameController.text),
      'phone': Validators.normalizePhone(_phoneController.text.trim()),
      'address': address,
      'landmark': _landmarkController.text.trim(),
      'role': 'customer',
      if (_selectedLocation != null) 'latitude': _selectedLocation!.latitude,
      if (_selectedLocation != null) 'longitude': _selectedLocation!.longitude,
      'legal_acceptances': await _legalService.registrationAcceptances(),
      'app_version': await _legalService.appVersion(),
    };
  }

  Future<void> _checkEmailAndContinue() async {
    if (_formKey.currentState?.validate() != true) return;
    if (!await ConnectivityService.instance.checkNow()) {
      _showMessage('No internet connection. Please check your connection and try again.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final result = await _registrationService.checkEmail(_emailController.text.trim());
      if (!mounted) return;
      switch (result['status']) {
        case 'registered':
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Account already exists'),
              content: const Text('This email is already connected to an account. Please sign in instead.'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    Navigator.pop(context);
                  },
                  child: const Text('Go to sign in'),
                ),
              ],
            ),
          );
          break;
        case 'pending':
          _isPendingResume = true;
          _step = 6;
          _showMessage('Your registration is pending. Enter the code sent to your email to continue.', isError: false);
          break;
        default:
          _isPendingResume = false;
          _step = 1;
      }
      setState(() {});
    } catch (error) {
      if (mounted) _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _nextStep() async {
    if (_step == 0) {
      await _checkEmailAndContinue();
      return;
    }
    if (_step == 0 || _step == 1 || _step == 2 || _step == 3) {
      if (_formKey.currentState?.validate() != true) return;
      if (_step == 3) {
        if (_houseStreetController.text.trim().isEmpty) {
          _showMessage('Please enter your house and street address.');
          return;
        }
        if (_selectedBarangay == null) {
          _showMessage('Please select your barangay.');
          return;
        }
      }
      setState(() => _step = _isGoogleRegistration && _step == 3 ? 5 : _step + 1);
      return;
    }
    if (_step == 4) {
      if (_formKey.currentState?.validate() != true) return;
      setState(() => _step = 5);
      return;
    }
    if (_step != 5) return;
    if (!_agreedToLegal) {
      _showMessage('Please read and accept the Terms of Service and Privacy Policy.');
      return;
    }
    if (_isGoogleRegistration) {
      if (!await ConnectivityService.instance.checkNow()) {
        _showMessage('No internet connection. Please check your connection and try again.');
        return;
      }
      setState(() => _isLoading = true);
      try {
        final address = AddressInputWidget.buildFullAddress(
          houseStreet: _houseStreetController.text.trim(),
          selectedBarangay: _selectedBarangay,
          customBarangay: _customBarangayController.text.trim(),
        );
        await _authService.completeCustomerProfile(
          firstName: Validators.cleanName(_firstNameController.text),
          lastName: Validators.cleanName(_lastNameController.text),
          phone: Validators.normalizePhone(_phoneController.text.trim()),
          address: address,
          landmark: _landmarkController.text.trim(),
        );
        for (final document in requiredLegalDocuments()) {
          await _legalService.accept(document, source: 'registration');
        }
        if (_saveAccount) {
          await _authService.rememberCurrentSession();
        }
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const CustomerMainScreen()),
          (_) => false,
        );
      } catch (error) {
        if (mounted) _showMessage(error.toString().replaceFirst('Exception: ', ''));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
      return;
    }
    if (!await ConnectivityService.instance.checkNow()) {
      _showMessage('No internet connection. Please check your connection and try again.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _registrationService.requestCode(
        email: _emailController.text.trim(),
        registrationData: await _registrationData(),
      );
      if (mounted) setState(() => _step = 6);
    } catch (error) {
      if (mounted) {
        final message = error.toString().replaceFirst('Exception: ', '');
        if (message.toLowerCase().contains('already registered') ||
            message.toLowerCase().contains('already in use')) {
          _showMessage('This email already has an account. Please sign in instead.');
        } else {
          _showMessage(message);
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() => _isLoading = true);
    try {
      await _registrationService.requestCode(
        email: _emailController.text.trim(),
        resend: true,
      );
      if (mounted) _showMessage('A new code has been sent.', isError: false);
    } catch (error) {
      if (mounted) _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_isPendingResume && _formKey.currentState?.validate() != true) return;
    if (_otpController.text.trim().length != 6 ||
        int.tryParse(_otpController.text.trim()) == null) {
      _showMessage('Enter the 6-digit code from your email.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _registrationService.verifyAndCreate(
        email: _emailController.text.trim(),
        code: _otpController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      _showMessage('Email verified. Your account has been created. Please sign in.', isError: false);
      Navigator.pop(context);
    } catch (error) {
      if (mounted) _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Opens the shared map picker so the customer can drop a pin.
  /// Entirely optional - cancelling keeps the previous pin (if any).
  Future<void> _pickPinLocation() async {
    final result = await LocationPickerDialog.show(
      context,
      initialPosition: _selectedLocation,
      enforceDeliveryRadius: true,
      title: 'Pin Your Location',
    );
    if (result != null && mounted) {
      setState(() {
        _selectedLocation = result.coordinates;
        _selectedAddress = result.address;
        // Auto-fill house/street from the pin address if still empty
        if (_houseStreetController.text.trim().isEmpty &&
            result.address != null &&
            result.address!.isNotEmpty) {
          AddressInputWidget.parseAndPopulate(
            address: result.address!,
            houseStreetController: _houseStreetController,
            setBarangay: (v) => _selectedBarangay = v,
            customBarangayController: _customBarangayController,
          );
          // Prepend Blk/Lot placeholder if not already there
          if (_houseStreetController.text.trim().isEmpty) {
            _houseStreetController.text = 'Blk _ Lot _';
            _houseStreetController.selection =
                const TextSelection(baseOffset: 4, extentOffset: 5);
          } else if (!_houseStreetController.text.startsWith('Blk')) {
            _houseStreetController.text =
                'Blk _ Lot _, ${_houseStreetController.text}';
            _houseStreetController.selection =
                const TextSelection(baseOffset: 4, extentOffset: 5);
          }
        }
      });
      if (result.address != null && result.address!.isNotEmpty) {
        _showMessage(
            'Location pinned! Please verify your House / Block & Lot number.',
            isError: false);
      }
    }
  }

  Widget _buildPinLocationCard() {
    final hasPin = _selectedLocation != null;
    return InkWell(
      onTap: _pickPinLocation,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasPin ? AppTheme.accentBlue : AppTheme.borderGray,
            width: hasPin ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              color: hasPin
                  ? AppTheme.accentBlue
                  : AppTheme.textDark.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pin Location (20m Meetup Zone)',
                    style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasPin
                        ? '${_selectedAddress != null && _selectedAddress!.isNotEmpty ? "$_selectedAddress\n" : ""}'
                            '20m Meetup Zone • ${_selectedLocation!.latitude.toStringAsFixed(5)}, ${_selectedLocation!.longitude.toStringAsFixed(5)} '
                            '(${LocationHelper.getFormattedDistance(_selectedLocation!)})'
                        : 'Tap to drop a pin on the map (defines pickup/delivery meeting area)',
                    style: GoogleFonts.lexend(
                      fontSize: 12,
                      color: hasPin
                          ? AppTheme.textDark
                          : AppTheme.textLight.withValues(alpha: 0.6),
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
                  _selectedLocation = null;
                  _selectedAddress = null;
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showMessage(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Widget _buildPasswordChecklist() {
    final password = _passwordController.text;
    final confirmation = _confirmPasswordController.text;
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    final requirements = <(String, bool)>[
      ('At least 6 characters', password.length >= 6),
      ('No more than ${Validators.passwordMax} characters', password.length <= Validators.passwordMax),
      ('Contains a letter', hasLetter),
      ('Contains a number', hasNumber),
      ('Passwords match', confirmation.isNotEmpty && confirmation == password),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: requirements.map((requirement) {
          final (label, isSatisfied) = requirement;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  isSatisfied ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 17,
                  color: isSatisfied ? Colors.green : AppTheme.textLight,
                ),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Sign up', 'Your name', 'Contact details', 'Your address', 'Set a password', 'Review and consent', 'Verify your email'];
    final stepCount = _isGoogleRegistration ? 4 : 6;
    final displayedStep = _isGoogleRegistration
        ? (_step == 5 ? 4 : _step)
        : (_step == 0 ? 1 : (_step == 6 ? 6 : _step));
    final progress = _step == 6 ? 1.0 : displayedStep / stepCount;
    final pageFields = <Widget>[
      Column(children: [
        CustomTextField(label: 'Email Address', hint: 'Enter your email', prefixIcon: Icons.email_outlined, controller: _emailController, keyboardType: TextInputType.emailAddress, validator: Validators.emailField),
      ]),
      Column(children: [
        CustomTextField(label: 'First Name', hint: 'Juan', prefixIcon: Icons.person_outline, controller: _firstNameController, inputFormatters: InputFormatters.name(), validator: (v) => Validators.nameField(v, 'First name'), maxLength: Validators.nameMax, textCapitalization: TextCapitalization.words),
        const SizedBox(height: 18),
        CustomTextField(label: 'Last Name', hint: 'Dela Cruz', prefixIcon: Icons.person_outline, controller: _lastNameController, inputFormatters: InputFormatters.name(), validator: (v) => Validators.nameField(v, 'Last name'), maxLength: Validators.nameMax, textCapitalization: TextCapitalization.words),
      ]),
      Column(children: [
        CustomTextField(label: 'Mobile Number', hint: '09XX-XXX-XXXX', prefixIcon: Icons.phone_android_outlined, controller: _phoneController, keyboardType: TextInputType.phone, inputFormatters: InputFormatters.phone(), validator: Validators.phone),
        if (_isGoogleRegistration) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [const Icon(Icons.verified, size: 18, color: Colors.green), const SizedBox(width: 6), Expanded(child: Text('${_emailController.text} is verified by Google. OTP is not needed.'))])),
      ]),
      Column(children: [
        AddressInputWidget(houseStreetController: _houseStreetController, customBarangayController: _customBarangayController, landmarkController: _landmarkController, selectedBarangay: _selectedBarangay, onBarangayChanged: (v) => setState(() => _selectedBarangay = v), helperText: 'Santa Cruz, Laguna only. Select "Other" if outside.', landmarkHint: 'e.g. Near church, blue gate'),
        const SizedBox(height: 16), _buildPinLocationCard(),
      ]),
      Column(children: [
        CustomTextField(label: 'Password', hint: 'Create a password', prefixIcon: Icons.lock_outline, isPassword: true, controller: _passwordController, onChanged: (_) => setState(() {}), validator: Validators.passwordField, maxLength: Validators.passwordMax),
        const SizedBox(height: 18),
        CustomTextField(label: 'Confirm Password', hint: 'Repeat your password', prefixIcon: Icons.lock_reset_outlined, isPassword: true, controller: _confirmPasswordController, onChanged: (_) => setState(() {}), validator: (v) => Validators.confirmPassword(v, _passwordController.text), maxLength: Validators.passwordMax),
        _buildPasswordChecklist(),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_firstNameController.text} ${_lastNameController.text}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8), Text(_emailController.text), Text(_phoneController.text),
        if (_isGoogleRegistration) ...[
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.verified, color: Colors.green), const SizedBox(width: 8), Expanded(child: Text('${_emailController.text} is connected successfully. No email OTP is needed.'))])),
        ],
        const SizedBox(height: 8), Text(AddressInputWidget.buildFullAddress(houseStreet: _houseStreetController.text.trim(), selectedBarangay: _selectedBarangay, customBarangay: _customBarangayController.text.trim())),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.softGray,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LegalConsentCheckbox(
                value: _agreedToLegal,
                onChanged: (v) => setState(() => _agreedToLegal = v),
              ),
              const SizedBox(height: 12),
              Divider(
                height: 1,
                color: AppTheme.borderGray.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(() => _saveAccount = !_saveAccount),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        height: 20,
                        width: 20,
                        child: Checkbox(
                          value: _saveAccount,
                          onChanged: (v) =>
                              setState(() => _saveAccount = v ?? false),
                          activeColor: AppTheme.accentBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Save account on this device for quick sign-in',
                          style: GoogleFonts.lexend(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('We sent a 6-digit code to ${_emailController.text.trim()}. Enter it below to activate your account.'),
        if (_isPendingResume) ...[
          const SizedBox(height: 18),
          const Text('Create a password to finish setting up your account.'),
          const SizedBox(height: 12),
          CustomTextField(label: 'Password', hint: 'Create a password', prefixIcon: Icons.lock_outline, isPassword: true, controller: _passwordController, onChanged: (_) => setState(() {}), validator: Validators.passwordField, maxLength: Validators.passwordMax),
          const SizedBox(height: 18),
          CustomTextField(label: 'Confirm Password', hint: 'Repeat your password', prefixIcon: Icons.lock_reset_outlined, isPassword: true, controller: _confirmPasswordController, onChanged: (_) => setState(() {}), validator: (v) => Validators.confirmPassword(v, _passwordController.text), maxLength: Validators.passwordMax),
          _buildPasswordChecklist(),
        ],
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _isLoading ? null : () => setState(() { _otpController.clear(); _isPendingResume = false; _step = 0; }), child: const Text('Change email'))),
        const SizedBox(height: 22),
        TextFormField(controller: _otpController, keyboardType: TextInputType.number, maxLength: 6, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold), decoration: const InputDecoration(labelText: 'Email verification code', counterText: ''),),
        TextButton(onPressed: _isLoading ? null : _resendCode, child: const Text('Resend code')),
      ]),
    ];
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
          onPressed: _step == 0
              ? () => Navigator.pop(context)
              : () => setState(() => _step = _step == 6
                  ? (_isPendingResume ? 0 : 5)
                  : (_step == 5 ? 4 : _step - 1)),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_step == 0) Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.softGray,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/logo.jpg',
                        height: 100,
                        width: 100,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.wash,
                          size: 100,
                          color: AppTheme.accentBlue,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  titles[_step],
                  style: AppTheme.lightTheme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
          _step == 6
                      ? 'Your account becomes active after email verification.'
                      : 'Step $displayedStep of $stepCount · Complete each section to continue.',
                  style: AppTheme.lightTheme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 30),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 24),
                pageFields[_step],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : (_step == 6 ? _verifyCode : _nextStep),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_step == 0
                          ? 'Continue'
                          : (_step == 6
                              ? 'Continue'
                              : (_step == 5
                                  ? (_isGoogleRegistration ? 'Complete registration' : 'Send verification code')
                                  : 'Next'))),
                ),
                if (_step == 0) ...[
                  const SizedBox(height: 12),
                  const Center(child: Text('Or sign up with')),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _continueWithGoogle,
                      icon: const Icon(Icons.g_mobiledata, size: 28),
                      label: Text(_isLoading ? 'Connecting...' : 'Continue with Google'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                // Wrap so the prompt and its action stack instead of
                // overflowing when the text gets wider than the row.
                if (_step == 0) Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Already have an account? '),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          color: AppTheme.accentBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
