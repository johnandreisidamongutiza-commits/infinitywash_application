import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_text_field.dart';
import '../services/password_reset_service.dart';
import '../services/rate_limit_service.dart';

enum ForgotPasswordStep { identity, otp, reset, success }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  ForgotPasswordStep _currentStep = ForgotPasswordStep.identity;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(6, (index) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (index) => FocusNode());
  
  final _passwordResetService = PasswordResetService();
  bool _isLoading = false;
  String? _tokenId;
  String? _userEmail;
  int _resendCountdown = 60;
  bool _canResend = false;
  int _resendAttemptsLeft = 3;

  @override
  void dispose() {
    _emailController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _otpFocusNodes) {
      node.dispose();
    }
    super.dispose();
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
        CustomTextField(
          label: 'Email Address',
          hint: 'Enter your email',
          prefixIcon: Icons.email_outlined,
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleSendCode,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Send Verification Code'),
          ),
        ),
      ],
    );
  }
  
  Future<void> _handleSendCode() async {
    if (_emailController.text.isEmpty) {
      _showError('Please enter your email address');
      return;
    }
    
    // Basic email validation
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(_emailController.text.trim())) {
      _showError('Please enter a valid email address');
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      final result = await _passwordResetService.requestPasswordReset(
        _emailController.text.trim(),
      );
      
      _tokenId = result['token_id'];
      _userEmail = result['email'];
      
      // Get rate limit status
      await _updateRateLimitStatus();
      
      if (mounted) {
        setState(() {
          _currentStep = ForgotPasswordStep.otp;
          _isLoading = false;
        });
        _startResendCountdown();
        _showSuccess('Verification code sent to your email');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(e.toString().replaceAll('Exception: ', ''));
      }
    }
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
  
  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) => _buildOtpBox(index)),
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleVerifyCode,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Verify Code'),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Column(
            children: [
              TextButton(
                onPressed: _canResend ? _handleResendCode : null,
                child: Text(
                  _canResend 
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
                    '⚠️ You have $_resendAttemptsLeft resend${_resendAttemptsLeft == 1 ? '' : 's'} remaining',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                    ),
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
    String code = _otpControllers.map((c) => c.text).join();
    
    if (code.length != 6) {
      _showError('Please enter the complete 6-character code');
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      final tokenId = await _passwordResetService.verifyResetCode(
        _userEmail!,
        code,
      );
      
      if (tokenId != null) {
        _tokenId = tokenId;
        if (mounted) {
          setState(() {
            _currentStep = ForgotPasswordStep.reset;
            _isLoading = false;
          });
          _showSuccess('Code verified successfully!');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(e.toString().replaceAll('Exception: ', ''));
      }
    }
  }
  
  Future<void> _handleResendCode() async {
    // Check rate limit first
    final rateLimitCheck = await RateLimitService.canSendOtp(_userEmail!);
    if (!rateLimitCheck.canSend) {
      _showError(rateLimitCheck.message ?? 'Too many attempts');
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      await _passwordResetService.resendResetCode(_userEmail!);
      
      if (mounted) {
        // Clear OTP fields
        for (var controller in _otpControllers) {
          controller.clear();
        }
        _otpFocusNodes[0].requestFocus();
        
        // Update rate limit status
        await _updateRateLimitStatus();
        
        setState(() => _isLoading = false);
        _showSuccess('A new code has been sent to your email! ($_resendAttemptsLeft resends left)');
        _startResendCountdown();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(e.toString().replaceAll('Exception: ', ''));
      }
    }
  }
  
  Future<void> _updateRateLimitStatus() async {
    if (_userEmail != null) {
      final status = await _passwordResetService.getRateLimitStatus(_userEmail!);
      if (mounted) {
        setState(() {
          _resendAttemptsLeft = status['attemptsLeft'] ?? 3;
        });
      }
    }
  }

  Widget _buildOtpBox(int index) {
    return SizedBox(
      width: 45,
      height: 55,
      child: TextFormField(
        controller: _otpControllers[index],
        focusNode: _otpFocusNodes[index],
        keyboardType: TextInputType.text, // Changed from number to text for letters+numbers
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.characters,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        inputFormatters: [
          LengthLimitingTextInputFormatter(1),
          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')), // Allow letters and numbers
        ],
        decoration: InputDecoration(
          filled: true,
          fillColor: AppTheme.softGray,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.accentBlue, width: 2),
          ),
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            _otpFocusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _otpFocusNodes[index - 1].requestFocus();
          }
        },
      ),
    );
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
        ),
        const SizedBox(height: 20),
        CustomTextField(
          label: 'Confirm Password',
          hint: '••••••••',
          prefixIcon: Icons.lock_reset_outlined,
          isPassword: true,
          controller: _confirmPasswordController,
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleResetPassword,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Reset Password'),
          ),
        ),
      ],
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
    
    if (newPassword.length < 8) {
      _showError('Password must be at least 8 characters long');
      return;
    }
    
    if (newPassword != confirmPassword) {
      _showError('Passwords do not match');
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      await _passwordResetService.resetPassword(_tokenId!, newPassword);
      
      if (mounted) {
        setState(() {
          _currentStep = ForgotPasswordStep.success;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(e.toString().replaceAll('Exception: ', ''));
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
            child: const Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
          ),
          const SizedBox(height: 32),
          Text(
            'Success!',
            style: AppTheme.lightTheme.textTheme.headlineMedium,
          ),
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
