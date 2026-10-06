import 'package:flutter/material.dart';
import '../../../../widgets/custom_text_field.dart';
import '../../../../services/auth_service.dart';
import '../../../../theme/app_theme.dart';
import '../../../../utils/app_error.dart';
import '../../../../utils/validators.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
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

    final passwordError = Validators.newPassword(_newPasswordController.text);
    if (passwordError != null) {
      _showMessage(passwordError, isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _authService.getCurrentUser();
      if (user == null || user.email == null) {
        throw const AppError(
          'You are signed out. Please log in and try again.',
          type: AppErrorType.auth,
        );
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
      _showMessage(mapErrorToMessage(error), isError: true);
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
                validator: Validators.passwordRequired,
              ),
              const SizedBox(height: 20),
              CustomTextField(
                label: 'New Password',
                hint: '••••••••',
                prefixIcon: Icons.lock_outline,
                isPassword: true,
                controller: _newPasswordController,
                validator: Validators.passwordField,
                maxLength: Validators.passwordMax,
              ),
              const SizedBox(height: 20),
              CustomTextField(
                label: 'Confirm New Password',
                hint: '••••••••',
                prefixIcon: Icons.lock_reset_outlined,
                isPassword: true,
                controller: _confirmPasswordController,
                validator: (v) => Validators.confirmPassword(
                  v,
                  _newPasswordController.text,
                ),
                maxLength: Validators.passwordMax,
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
