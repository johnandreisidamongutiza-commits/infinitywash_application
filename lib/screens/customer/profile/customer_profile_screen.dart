import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/custom_text_field.dart';
import '../../../services/profile_service.dart';
import '../../../services/auth_service.dart';
import '../../role_selection_screen.dart';

class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({super.key});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  final _profileService = ProfileService();
  final _authService = AuthService();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _landmarkController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  String _displayName = 'Customer';

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
    _addressController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profileService.getProfile();
      _firstNameController.text = profile['first_name'] ?? '';
      _lastNameController.text = profile['last_name'] ?? '';
      _phoneController.text = profile['phone'] ?? '';
      _emailController.text = profile['email'] ?? '';
      _addressController.text = profile['address'] ?? '';
      _landmarkController.text = profile['landmark'] ?? '';
      _displayName = '${_firstNameController.text} ${_lastNameController.text}'.trim();
    } catch (error) {
      _showMessage('Could not load profile: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      await _profileService.updateProfile(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        address: _addressController.text.trim(),
        landmark: _landmarkController.text.trim(),
      );
      setState(() {
        _displayName = '${_firstNameController.text} ${_lastNameController.text}'.trim();
      });
      _showMessage('Information updated.', isError: false);
    } catch (error) {
      _showMessage('Could not update profile: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Profile'),
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
            _buildProfileHeader(),
            const SizedBox(height: 40),
            Row(
              children: [
                Expanded(child: CustomTextField(
                    label: 'First Name',
                    hint: 'John',
                    prefixIcon: Icons.person_outline,
                    controller: _firstNameController,
                  )),
                SizedBox(width: 16),
                Expanded(child: CustomTextField(
                    label: 'Last Name',
                    hint: 'Customer',
                    prefixIcon: Icons.person_outline,
                    controller: _lastNameController,
                  )),
              ],
            ),
            const SizedBox(height: 20),
            CustomTextField(
              label: 'Phone Number',
              hint: '0912-345-6789',
              prefixIcon: Icons.phone_android,
              controller: _phoneController,
            ),
            const SizedBox(height: 20),
            CustomTextField(
              label: 'Email Address',
              hint: 'john.customer@email.com',
              prefixIcon: Icons.email_outlined,
              controller: _emailController,
            ),
            const SizedBox(height: 20),
            CustomTextField(
              label: 'Default Address',
              hint: '123 Laundry St, Clean City',
              prefixIcon: Icons.location_on_outlined,
              controller: _addressController,
            ),
            const SizedBox(height: 20),
            CustomTextField(
              label: 'Landmark (Optional)',
              hint: 'Near the blue gate',
              prefixIcon: Icons.assistant_navigation,
              controller: _landmarkController,
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _isSaving ? null : _saveProfile,
              child: _isSaving ? const CircularProgressIndicator() : const Text('Confirm New Information'),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                _authService.signOut();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
                  (route) => false,
                );
              },
              child: const Text('Logout', style: TextStyle(color: AppTheme.errorRed, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(color: AppTheme.softGray, shape: BoxShape.circle, border: Border.all(color: AppTheme.accentBlue, width: 2)),
          child: const Icon(Icons.person, size: 60, color: AppTheme.accentBlue),
        ),
        const SizedBox(height: 16),
        Text(_displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        const Text('Member since 2026', style: TextStyle(color: AppTheme.textLight, fontSize: 12)),
      ],
    );
  }
}
