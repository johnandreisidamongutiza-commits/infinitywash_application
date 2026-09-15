import 'package:flutter/material.dart';
import '../../../../widgets/custom_text_field.dart';
import '../../../../services/auth_service.dart';
import '../../../../theme/app_theme.dart';

class RiderChangePasswordScreen extends StatefulWidget {
  const RiderChangePasswordScreen({super.key});

  @override
  State<RiderChangePasswordScreen> createState() => _RiderChangePasswordScreenState();
}

class _RiderChangePasswordScreenState extends State<RiderChangePasswordScreen> {
  final _authService = AuthService();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showMessage('New passwords do not match', isError: true);
      return;
    }

    if (_newPasswordController.text.length < 6) {
      _showMessage('Password must be at least 6 characters', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _authService.getCurrentUser();
      if (user == null || user.email == null) {
        throw Exception('No user logged in');
      }

      // Re-authenticate with current password to verify it
      await _authService.signIn(
        email: user.email!,
        password: _currentPasswordController.text,
      );

      // Update to new password
      await _authService.updatePassword(_newPasswordController.text);

      if (!mounted) return;
      _showMessage('Password changed successfully!', isError: false);
      
      // Clear form
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      
      // Go back after a short delay
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) Navigator.pop(context);
      });
    } catch (error) {
      if (!mounted) return;
      String errorMessage = 'Failed to change password';
      if (error.toString().contains('Invalid login credentials')) {
        errorMessage = 'Current password is incorrect';
      }
      _showMessage(errorMessage, isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message, {required bool isError}) {
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
        title: const Text('Change Password'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              CustomTextField(
                label: 'Current Password',
                hint: '••••••••',
                prefixIcon: Icons.lock_outline,
                isPassword: true,
                controller: _currentPasswordController,
              ),
              const SizedBox(height: 20),
              CustomTextField(
                label: 'New Password',
                hint: '••••••••',
                prefixIcon: Icons.lock_outline,
                isPassword: true,
                controller: _newPasswordController,
              ),
              const SizedBox(height: 20),
              CustomTextField(
                label: 'Confirm New Password',
                hint: '••••••••',
                prefixIcon: Icons.lock_reset_outlined,
                isPassword: true,
                controller: _confirmPasswordController,
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _changePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Update Password',
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
