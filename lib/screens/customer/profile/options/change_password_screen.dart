import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../widgets/custom_text_field.dart';
import '../../../../services/auth_service.dart';
import '../../../../theme/app_theme.dart';
import '../../../../utils/app_error.dart';
import '../../../../utils/validators.dart';

class CustomerChangePasswordScreen extends StatefulWidget {
  const CustomerChangePasswordScreen({super.key});

  @override
  State<CustomerChangePasswordScreen> createState() =>
      _CustomerChangePasswordScreenState();
}

class _CustomerChangePasswordScreenState
    extends State<CustomerChangePasswordScreen> {
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

  // ── Password Requirement Helpers ─────────────────────────────────────────
  bool get _hasMinLength => _newPasswordController.text.length >= 6;
  bool get _hasLettersAndNumbers =>
      _newPasswordController.text.contains(RegExp(r'[A-Za-z]')) &&
      _newPasswordController.text.contains(RegExp(r'[0-9]'));
  bool get _passwordsMatch =>
      _confirmPasswordController.text.isNotEmpty &&
      _newPasswordController.text == _confirmPasswordController.text;
  bool get _isDifferentFromCurrent =>
      _currentPasswordController.text.isEmpty ||
      _newPasswordController.text.isEmpty ||
      _newPasswordController.text != _currentPasswordController.text;

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    if (_currentPasswordController.text.trim() ==
        _newPasswordController.text.trim()) {
      _showMessage('New password must be different from current password',
          isError: true);
      return;
    }

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

      // Go back after a brief delay
      Future.delayed(const Duration(milliseconds: 1200), () {
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
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.lexend(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? AppTheme.errorRed : const Color(0xFF43A047),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.softGray,
      appBar: AppBar(
        title: Text(
          'Change Password',
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppTheme.textDark,
          ),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.textDark,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Security Info Header Card ──
              _buildSecurityHeaderCard(),
              const SizedBox(height: 20),

              // ── Password Inputs Card ──
              _buildPasswordFormCard(),
              const SizedBox(height: 20),

              // ── Password Requirements Checklist ──
              _buildRequirementsCard(),
              const SizedBox(height: 32),

              // ── Submit Button ──
              _buildSubmitButton(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI COMPONENTS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSecurityHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AppStyles.cardDecoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.lightBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: AppTheme.accentBlue,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Protect Your Account',
                  style: GoogleFonts.lexend(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose a strong password to keep your laundry orders and account details safe.',
                  style: GoogleFonts.lexend(
                    fontSize: 13,
                    color: AppTheme.textLight,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordFormCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomTextField(
            label: 'Current Password',
            hint: '••••••••',
            prefixIcon: Icons.lock_outline_rounded,
            isPassword: true,
            controller: _currentPasswordController,
            validator: Validators.passwordRequired,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          CustomTextField(
            label: 'New Password',
            hint: '••••••••',
            prefixIcon: Icons.lock_rounded,
            isPassword: true,
            controller: _newPasswordController,
            validator: Validators.passwordField,
            maxLength: Validators.passwordMax,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          CustomTextField(
            label: 'Confirm New Password',
            hint: '••••••••',
            prefixIcon: Icons.lock_reset_rounded,
            isPassword: true,
            controller: _confirmPasswordController,
            validator: (v) => Validators.confirmPassword(
              v,
              _newPasswordController.text,
            ),
            maxLength: Validators.passwordMax,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Password Requirements',
            style: GoogleFonts.lexend(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 12),
          _buildRequirementItem(
            label: 'At least 6 characters (up to 72)',
            isMet: _hasMinLength,
          ),
          const SizedBox(height: 8),
          _buildRequirementItem(
            label: 'Contains both letters and numbers',
            isMet: _hasLettersAndNumbers,
          ),
          const SizedBox(height: 8),
          _buildRequirementItem(
            label: 'New passwords match',
            isMet: _passwordsMatch,
          ),
          const SizedBox(height: 8),
          _buildRequirementItem(
            label: 'Different from current password',
            isMet: _isDifferentFromCurrent,
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementItem({
    required String label,
    required bool isMet,
  }) {
    final color = isMet ? const Color(0xFF43A047) : AppTheme.textLight;

    return Row(
      children: [
        Icon(
          isMet
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          size: 16,
          color: isMet ? const Color(0xFF43A047) : AppTheme.borderGray,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.lexend(
              fontSize: 12,
              fontWeight: isMet ? FontWeight.w500 : FontWeight.w400,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _changePassword,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accentBlue,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: AppTheme.accentBlue.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : Text(
                'Update Password',
                style: GoogleFonts.lexend(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
