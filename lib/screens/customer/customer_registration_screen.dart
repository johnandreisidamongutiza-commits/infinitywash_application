import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/location_picker_widget.dart';
import '../../services/auth_service.dart';

class CustomerRegistrationScreen extends StatefulWidget {
  const CustomerRegistrationScreen({super.key});

  @override
  State<CustomerRegistrationScreen> createState() => _CustomerRegistrationScreenState();
}

class _CustomerRegistrationScreenState extends State<CustomerRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  LatLng? _selectedLocation;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _landmarkController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    if (_firstNameController.text.trim().isEmpty ||
        _lastNameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _addressController.text.trim().isEmpty ||
        _passwordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      _showMessage('Complete all required fields.');
      return;
    }

    if (!_emailController.text.trim().contains('@')) {
      _showMessage('Enter a valid email address.');
      return;
    }

    if (_passwordController.text.length < 6) {
      _showMessage('Password must be at least 6 characters.');
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _showMessage('Passwords do not match.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await _authService.registerCustomer(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        landmark: _landmarkController.text.trim(),
        latitude: _selectedLocation?.latitude,
        longitude: _selectedLocation?.longitude,
      );

      if (!mounted) return;
      final message = response.session == null
          ? 'Account created. Check your email, confirm your address, then sign in.'
          : 'Account created. You can now sign in.';
      _showMessage(message, isError: false);
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        _showMessage('Registration failed: ${error.toString()}');
      }
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
      // Registration never blocks on the delivery radius; the picker
      // only shows a warning banner when the pin is out of range.
      enforceDeliveryRadius: true,
      title: 'Pin Your Location',
    );
    if (result != null && mounted) {
      setState(() => _selectedLocation = result);
    }
  }

  Widget _buildPinLocationCard() {
    final hasPin = _selectedLocation != null;
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
                    'Pin Location (Optional)',
                    style: AppTheme.lightTheme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasPin
                        ? '${_selectedLocation!.latitude.toStringAsFixed(6)}, '
                            '${_selectedLocation!.longitude.toStringAsFixed(6)}'
                        : 'Tap to drop a pin on the map',
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
                onPressed: () => setState(() => _selectedLocation = null),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
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
                Center(
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
                  'Create Account',
                  style: AppTheme.lightTheme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Join Infinity Wash and experience the best laundry service.',
                  style: AppTheme.lightTheme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        label: 'First Name',
                        hint: 'John',
                        prefixIcon: Icons.person_outline,
                        controller: _firstNameController,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: CustomTextField(
                        label: 'Last Name',
                        hint: 'Doe',
                        prefixIcon: Icons.person_outline,
                        controller: _lastNameController,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                CustomTextField(
                  label: 'Mobile Number',
                  hint: '09XX-XXX-XXXX',
                  prefixIcon: Icons.phone_android_outlined,
                  controller: _phoneController,
                ),
                const SizedBox(height: 20),
                CustomTextField(
                  label: 'Email Address',
                  hint: 'Enter your email',
                  prefixIcon: Icons.email_outlined,
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 20),
                CustomTextField(
                  label: 'Address',
                  hint: 'Enter your primary address',
                  prefixIcon: Icons.location_on_outlined,
                  controller: _addressController,
                ),
                const SizedBox(height: 20),
                CustomTextField(
                  label: 'Landmark (Optional)',
                  hint: 'Near Parkmall / Blue Building',
                  prefixIcon: Icons.assistant_navigation,
                  controller: _landmarkController,
                ),
                const SizedBox(height: 20),
                _buildPinLocationCard(),
                const SizedBox(height: 20),
                CustomTextField(
                  label: 'Password',
                  hint: 'Create a password',
                  prefixIcon: Icons.lock_outline,
                  isPassword: true,
                  controller: _passwordController,
                ),
                const SizedBox(height: 20),
                CustomTextField(
                  label: 'Confirm Password',
                  hint: 'Repeat your password',
                  prefixIcon: Icons.lock_reset_outlined,
                  isPassword: true,
                  controller: _confirmPasswordController,
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Register'),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
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
