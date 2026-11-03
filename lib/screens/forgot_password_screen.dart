import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../utils/app_error.dart';
import '../utils/validators.dart';
import '../widgets/custom_text_field.dart';
import '../services/password_reset_service.dart';
import '../widgets/turnstile_captcha.dart';

enum ForgotPasswordStep { identity, otp, reset, success }
enum _CaptchaAction { none, send, resend }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  ForgotPasswordStep _currentStep = ForgotPasswordStep.identity;
  final _identityFormKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  final _passwordResetService = PasswordResetService();
  bool _isLoading = false;
  String? _userEmail;
  int _resendCountdown = 60;
  bool _canResend = false;
  int _resendAttemptsLeft = 3;
  final _captchaKey = GlobalKey<TurnstileCaptchaState>();
  bool _showCaptcha = false;
  _CaptchaAction _captchaAction = _CaptchaAction.none;

  @override
  void dispose() {
    _emailController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _onEmailChanged(String _) {
    setState(() {
      _captchaAction = _CaptchaAction.none;
      _showCaptcha = false;
    });
  }

  Future<void> _beginCaptcha(_CaptchaAction action) async {
    if (_captchaAction != _CaptchaAction.none || _isLoading) return;
    setState(() {
      _captchaAction = action;
      _showCaptcha = false;
    });

    // Keep the challenge hidden until the user has explicitly requested a code.
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted || _captchaAction != action) return;
    setState(() => _showCaptcha = true);
  }

  Future<void> _onCaptchaToken(String token) async {
    final action = _captchaAction;
    if (token.isEmpty || action == _CaptchaAction.none || _isLoading) return;

    // Turnstile tokens are single-use. Consume this result once; a new token is
    // requested only when the user asks to send or resend another code.
    setState(() {
      _captchaAction = _CaptchaAction.none;
      _showCaptcha = false;
      _isLoading = true;
    });

    try {
      final email = action == _CaptchaAction.send
          ? _emailController.text.trim()
          : _userEmail!;
      final result = action == _CaptchaAction.send
          ? await _passwordResetService.requestPasswordReset(
              email,
              captchaToken: token,
            )
          : await _passwordResetService.resendResetCode(
              email,
              captchaToken: token,
            );

      if (!mounted) return;
      setState(() {
        _resendAttemptsLeft = result.attemptsLeft;
        _isLoading = false;
      });

      if (action == _CaptchaAction.send) {
        _userEmail = result.email;
        setState(() => _currentStep = ForgotPasswordStep.otp);
        _startResendCountdown();
        _showSuccess('Verification code sent. Check your inbox and spam folder.');
      } else {
        _otpController.clear();
        _startResendCountdown();
        _showSuccess('A new code was sent. Check your inbox and spam folder.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(mapErrorToMessage(error));
      }
    }
  }

  void _startResendCountdown() {
    _canResend = false;
    _resendCountdown = 60;

    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() {
          _resendCountdown--;
          if (_resendCountdown <= 0) {
            _canResend = true;
          }
        });
        return _resendCountdown > 0;
      }
      return false;
    });
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
          onPressed: () {
            if (_currentStep == ForgotPasswordStep.identity) {
              Navigator.pop(context);
            } else if (_currentStep == ForgotPasswordStep.otp) {
              setState(() => _currentStep = ForgotPasswordStep.identity);
            } else if (_currentStep == ForgotPasswordStep.reset) {
              setState(() => _currentStep = ForgotPasswordStep.otp);
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_currentStep) {
      case ForgotPasswordStep.identity:
        return _buildIdentityView();
      case ForgotPasswordStep.otp:
        return _buildOtpView();
      case ForgotPasswordStep.reset:
        return _buildResetView();
      case ForgotPasswordStep.success:
        return _buildSuccessView();
    }
  }

  Widget _buildIdentityView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          'Forgot Password?',
          style: AppTheme.lightTheme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Enter your registered email address to receive a verification code.',
          style: AppTheme.lightTheme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 40),
        Form(
          key: _identityFormKey,
          child: CustomTextField(
            label: 'Email Address',
            hint: 'Enter your email',
            prefixIcon: Icons.email_outlined,
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            validator: Validators.emailField,
            onChanged: _onEmailChanged,
          ),
        ),
        if (_showCaptcha && _captchaAction == _CaptchaAction.send) ...[
          const SizedBox(height: 20),
          TurnstileCaptcha(
            key: _captchaKey,
            onToken: _onCaptchaToken,
          ),
        ],
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading || _captchaAction != _CaptchaAction.none
                ? null
                : _handleSendCode,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _captchaAction == _CaptchaAction.send
                        ? (_showCaptcha
                            ? 'Complete Security Check'
                            : 'Preparing Security Check...')
                        : 'Send Verification Code',
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleSendCode() async {
    if (_identityFormKey.currentState?.validate() != true) return;

    if (_emailController.text.isEmpty) {
      _showError('Please enter your email address');
      return;
    }

    // Basic email validation
    final emailError = Validators.email(_emailController.text.trim());
    if (emailError != null) {
      _showError(emailError);
      return;
    }

    await _beginCaptcha(_CaptchaAction.send);
  }

  void _showError(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 7),
          backgroundColor: const Color(0xFFB3261E),
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Widget _buildOtpView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          'Verify Identity',
          style: AppTheme.lightTheme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'A 6-character security code has been sent to your registered email.',
          style: AppTheme.lightTheme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 40),
        TextFormField(
          controller: _otpController,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 10,
            color: AppTheme.textDark,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
            LengthLimitingTextInputFormatter(6),
          ],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '______',
            hintStyle: const TextStyle(
              letterSpacing: 8,
              color: AppTheme.textLight,
            ),
            prefixIcon: const Icon(Icons.verified_user_outlined),
            suffixIcon: _otpController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear code',
                    onPressed: () {
                      _otpController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.clear),
                  ),
            filled: true,
            fillColor: AppTheme.softGray,
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppTheme.borderGray),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppTheme.borderGray),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppTheme.accentBlue,
                width: 2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tap to edit any character, or paste the full code.',
          style: TextStyle(fontSize: 13, color: AppTheme.textLight),
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading || _otpController.text.length != 6
                ? null
                : _handleVerifyCode,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Verify Code'),
          ),
        ),
        if (_showCaptcha && _captchaAction == _CaptchaAction.resend) ...[
          const SizedBox(height: 20),
          TurnstileCaptcha(
            key: _captchaKey,
            onToken: _onCaptchaToken,
          ),
        ],
        const SizedBox(height: 20),
        Center(
          child: Column(
            children: [
              TextButton(
                onPressed: _canResend &&
                        _captchaAction == _CaptchaAction.none &&
                        !_isLoading
                    ? _handleResendCode
                    : null,
                child: Text(
                  _captchaAction == _CaptchaAction.resend
                      ? (_showCaptcha
                          ? 'Complete Security Check'
                          : 'Preparing Security Check...')
                      : _canResend
                      ? 'Resend Code ($_resendAttemptsLeft left)'
                      : 'Resend Code in 00:${_resendCountdown.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: _canResend ? AppTheme.accentBlue : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (_resendAttemptsLeft < 3)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'You have $_resendAttemptsLeft resend${_resendAttemptsLeft == 1 ? '' : 's'} remaining',
                    style: const TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleVerifyCode() async {
    // Collect the code from all 6 fields
    final code = _otpController.text.trim();

    // Full charset + length check (boxes already filter input per character).
    final otpError = Validators.otpCode(code);
    if (otpError != null) {
      _showError(otpError);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _passwordResetService.verifyResetCode(_userEmail!, code);

      if (mounted) {
        setState(() {
          _currentStep = ForgotPasswordStep.reset;
          _isLoading = false;
        });
        _showSuccess('Code verified successfully!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(mapErrorToMessage(e));
      }
    }
  }

  Future<void> _handleResendCode() async {
    await _beginCaptcha(_CaptchaAction.resend);
  }

  Widget _buildResetView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          'New Password',
          style: AppTheme.lightTheme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Create a strong, secure password for your account.',
          style: AppTheme.lightTheme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 40),
        CustomTextField(
          label: 'New Password',
          hint: '••••••••',
          prefixIcon: Icons.lock_outline,
          isPassword: true,
          controller: _newPasswordController,
          maxLength: 72,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _buildPasswordRequirement('At least 8 characters',
            _newPasswordController.text.length >= 8),
        _buildPasswordRequirement('One uppercase letter',
            RegExp(r'[A-Z]').hasMatch(_newPasswordController.text)),
        _buildPasswordRequirement('One lowercase letter',
            RegExp(r'[a-z]').hasMatch(_newPasswordController.text)),
        _buildPasswordRequirement('One number',
            RegExp(r'[0-9]').hasMatch(_newPasswordController.text)),
        _buildPasswordRequirement('One symbol (for example, ! or @)',
            RegExp(r'[^A-Za-z0-9]').hasMatch(_newPasswordController.text)),
        const SizedBox(height: 20),
        CustomTextField(
          label: 'Confirm Password',
          hint: '••••••••',
          prefixIcon: Icons.lock_reset_outlined,
          isPassword: true,
          controller: _confirmPasswordController,
          maxLength: 72,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
        ),
        if (_confirmPasswordController.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                _passwordsMatch ? Icons.check_circle : Icons.error_outline,
                size: 18,
                color: _passwordsMatch ? Colors.green : AppTheme.errorRed,
              ),
              const SizedBox(width: 8),
              Text(
                _passwordsMatch ? 'Passwords match' : 'Passwords do not match',
                style: TextStyle(
                  color: _passwordsMatch ? Colors.green : AppTheme.errorRed,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading || !_canResetPassword
                ? null
                : _handleResetPassword,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Reset Password'),
          ),
        ),
      ],
    );
  }

  bool get _passwordsMatch =>
      _confirmPasswordController.text.isNotEmpty &&
      _newPasswordController.text == _confirmPasswordController.text;

  bool get _canResetPassword =>
      _hasStrongPassword(_newPasswordController.text) && _passwordsMatch;

  bool _hasStrongPassword(String password) =>
      password.length >= 8 &&
      password.length <= 72 &&
      RegExp(r'[A-Z]').hasMatch(password) &&
      RegExp(r'[a-z]').hasMatch(password) &&
      RegExp(r'[0-9]').hasMatch(password) &&
      RegExp(r'[^A-Za-z0-9]').hasMatch(password);

  Widget _buildPasswordRequirement(String label, bool isSatisfied) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isSatisfied ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 17,
            color: isSatisfied ? Colors.green : AppTheme.textLight,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isSatisfied ? Colors.green : AppTheme.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleResetPassword() async {
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    // Validation
    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }

    if (!_hasStrongPassword(newPassword)) {
      _showError(
        'Use at least 8 characters with uppercase, lowercase, a number, and a symbol.',
      );
      return;
    }

    if (newPassword != confirmPassword) {
      _showError('Passwords do not match');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _passwordResetService.resetPassword(
        _userEmail!,
        _otpController.text,
        newPassword,
      );

      if (mounted) {
        setState(() {
          _currentStep = ForgotPasswordStep.success;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(mapErrorToMessage(e));
      }
    }
  }

  Widget _buildSuccessView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 60),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              size: 80,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 32),
          Text('Success!', style: AppTheme.lightTheme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          const Text(
            'Your password has been reset successfully. You can now sign in with your new credentials.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textLight),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to Login'),
          ),
        ],
      ),
    );
  }
}
