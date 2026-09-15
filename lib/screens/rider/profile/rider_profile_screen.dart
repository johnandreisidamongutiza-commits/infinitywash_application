import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/custom_text_field.dart';
import '../../../services/profile_service.dart';
import '../../../services/auth_service.dart';
import '../../role_selection_screen.dart';

class RiderProfileScreen extends StatefulWidget {
  const RiderProfileScreen({super.key});

  @override
  State<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends State<RiderProfileScreen> {
  final _profileService = ProfileService();
  final _authService = AuthService();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _vehicleController = TextEditingController();
  final _zonesController = TextEditingController();
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
    _nameController.dispose();
    _vehicleController.dispose();
    _zonesController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profileService.getProfile();
      final employee = await _profileService.getEmployee(profile['id']);
      _firstNameController.text = profile['first_name'] ?? '';
      _lastNameController.text = profile['last_name'] ?? '';
      _phoneController.text = profile['phone'] ?? employee['phone'] ?? '';
      _emailController.text = profile['email'] ?? employee['email'] ?? '';
      _nameController.text = employee['name'] ?? '';
      _vehicleController.text = employee['vehicle_details'] ?? '';
      _zonesController.text = employee['delivery_zones'] ?? '';
    } catch (error) {
      _showMessage('Could not load profile: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      final profile = await _profileService.getProfile();
      await _profileService.updateProfile(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
      );
      await _profileService.updateEmployee(
        profileId: profile['id'],
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        vehicleDetails: _vehicleController.text.trim(),
        deliveryZones: _zonesController.text.trim(),
      );
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
            CustomTextField(label: 'First Name', hint: 'First name', prefixIcon: Icons.person_outline, controller: _firstNameController),
            const SizedBox(height: 20),
            CustomTextField(label: 'Last Name', hint: 'Last name', prefixIcon: Icons.person_outline, controller: _lastNameController),
            const SizedBox(height: 20),
            CustomTextField(label: 'Full Name', hint: 'John Rider', prefixIcon: Icons.person_outline, controller: _nameController),
            const SizedBox(height: 20),
            CustomTextField(label: 'Phone Number', hint: '0912-345-6789', prefixIcon: Icons.phone_android, controller: _phoneController),
            const SizedBox(height: 20),
            CustomTextField(label: 'Email Address', hint: 'Email address', prefixIcon: Icons.email_outlined, controller: _emailController),
            const SizedBox(height: 20),
            CustomTextField(label: 'Vehicle Details', hint: 'Vehicle plate or details', prefixIcon: Icons.moped_outlined, controller: _vehicleController),
            const SizedBox(height: 20),
            CustomTextField(label: 'Delivery Zones', hint: 'Assigned delivery zones', prefixIcon: Icons.map_outlined, controller: _zonesController),
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
        Text(_nameController.text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        const Text('Infinity Rider since 2026', style: TextStyle(color: AppTheme.textLight, fontSize: 12)),
      ],
    );
  }
}
