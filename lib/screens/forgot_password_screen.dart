import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_text_field.dart';

enum ForgotPasswordStep { identity, otp, reset, success }

class ForgotPasswordScreen extends StatefulWidget {
  final String role;
  const ForgotPasswordScreen({super.key, required this.role});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  ForgotPasswordStep _currentStep = ForgotPasswordStep.identity;
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(6, (index) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (index) => FocusNode());

  @override
  void dispose() {
    _idController.dispose();
    _contactController.dispose();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _otpFocusNodes) {
      node.dispose();
    }
    super.dispose();
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
    bool isInternal = widget.role != 'Customer';
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
          isInternal
              ? 'Validate your ${widget.role} credentials to receive a verification code.'
              : 'Enter your registered email or mobile number below.',
          style: AppTheme.lightTheme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 40),
        if (isInternal) ...[
          CustomTextField(
            label: '${widget.role} ID',
            hint: 'Enter your IW-${widget.role.toUpperCase()}-XXX',
            prefixIcon: Icons.badge_outlined,
            controller: _idController,
          ),
          const SizedBox(height: 20),
        ],
        CustomTextField(
          label: 'Email or Mobile',
          hint: 'Enter registered contact',
          prefixIcon: Icons.contact_mail_outlined,
          controller: _contactController,
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: () {
            if (_contactController.text.isNotEmpty && (!isInternal || _idController.text.isNotEmpty)) {
              setState(() => _currentStep = ForgotPasswordStep.otp);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please fill in all required fields')),
              );
            }
          },
          child: const Text('Send Verification Code'),
        ),
      ],
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
          'A 6-digit security code has been sent to your registered device.',
          style: AppTheme.lightTheme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 40),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) => _buildOtpBox(index)),
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: () {
            // Mock verification
            setState(() => _currentStep = ForgotPasswordStep.reset);
          },
          child: const Text('Verify Code'),
        ),
        const SizedBox(height: 20),
        Center(
          child: TextButton(
            onPressed: () {},
            child: const Text(
              'Resend Code in 00:59',
              style: TextStyle(color: AppTheme.accentBlue, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpBox(int index) {
    return SizedBox(
      width: 45,
      height: 55,
      child: TextFormField(
        controller: _otpControllers[index],
        focusNode: _otpFocusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        inputFormatters: [
          LengthLimitingTextInputFormatter(1),
          FilteringTextInputFormatter.digitsOnly,
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
        const CustomTextField(
          label: 'New Password',
          hint: '••••••••',
          prefixIcon: Icons.lock_outline,
          isPassword: true,
        ),
        const SizedBox(height: 20),
        const CustomTextField(
          label: 'Confirm Password',
          hint: '••••••••',
          prefixIcon: Icons.lock_reset_outlined,
          isPassword: true,
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: () {
            setState(() => _currentStep = ForgotPasswordStep.success);
          },
          child: const Text('Reset Password'),
        ),
      ],
    );
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
              color: Colors.green.withOpacity(0.1),
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
