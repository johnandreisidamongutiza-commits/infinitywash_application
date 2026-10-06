import 'package:flutter/material.dart';
import '../../../../services/profile_service.dart';
import '../../../../theme/app_theme.dart';
import '../../../../utils/app_error.dart';
import '../../../../utils/input_formatters.dart';
import '../../../../utils/validators.dart';
import '../../../../widgets/custom_text_field.dart';

class AccountDetailsScreen extends StatefulWidget {
  const AccountDetailsScreen({super.key});

  @override
  State<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _profileService = ProfileService();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _employeeCodeController = TextEditingController();
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
    _employeeCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profileService.getProfile();
      final employee = await _profileService.getEmployee(profile['id']);

      if (!mounted) return;

      _firstNameController.text = profile['first_name'] ?? '';
      _lastNameController.text = profile['last_name'] ?? '';
      _phoneController.text = profile['phone'] ?? employee['phone'] ?? '';
      _emailController.text = profile['email'] ?? employee['email'] ?? '';
      _nameController.text = employee['name'] ?? '';
      _employeeCodeController.text = employee['employee_code'] ?? '';
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load account details. ${mapErrorToMessage(error)}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_formKey.currentState?.validate() != true) return;

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
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account details updated successfully!')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mapErrorToMessage(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
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
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                  CustomTextField(
                    label: 'First Name',
                    hint: 'First name',
                    prefixIcon: Icons.person_outline,
                    controller: _firstNameController,
                    validator: (v) => Validators.nameField(v, 'First name'),
                    maxLength: Validators.nameMax,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    label: 'Last Name',
                    hint: 'Last name',
                    prefixIcon: Icons.person_outline,
                    controller: _lastNameController,
                    validator: (v) => Validators.nameField(v, 'Last name'),
                    maxLength: Validators.nameMax,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    label: 'Employee Name',
                    hint: 'Full name',
                    prefixIcon: Icons.badge_outlined,
                    controller: _nameController,
                    validator: (v) => Validators.nameField(v, 'Employee name'),
                    maxLength: Validators.nameMax,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    label: 'Employee Code',
                    hint: 'Employee code',
                    prefixIcon: Icons.numbers,
                    controller: _employeeCodeController,
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    label: 'Phone Number',
                    hint: 'Phone number',
                    prefixIcon: Icons.phone,
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
            ),
    );
  }
}
