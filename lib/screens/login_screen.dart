import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_text_field.dart';
import 'staff/staff_main_screen.dart';
import 'customer/customer_main_screen.dart';
import 'rider/rider_main_screen.dart';
import 'customer/customer_registration_screen.dart';

class LoginScreen extends StatefulWidget {
  final String role;

  const LoginScreen({super.key, required this.role});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool rememberMe = false;

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
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
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
              '${widget.role} Login',
              style: AppTheme.lightTheme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to continue to your ${widget.role} account.',
              style: AppTheme.lightTheme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.borderGray),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, color: AppTheme.accentBlue),
                  const SizedBox(width: 12),
                  Text(
                    widget.role,
                    style: AppTheme.lightTheme.textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Change',
                      style: TextStyle(color: AppTheme.accentBlue),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            CustomTextField(
              label: 'Work Email',
              hint: 'Enter your work email',
              prefixIcon: Icons.email_outlined,
            ),
            const SizedBox(height: 20),
            CustomTextField(
              label: 'Password',
              hint: 'Enter your password',
              prefixIcon: Icons.lock_outline,
              isPassword: true,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: rememberMe,
                  onChanged: (value) => setState(() => rememberMe = value!),
                  activeColor: AppTheme.accentBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                const Text('Remember me'),
                const Spacer(),
                TextButton(
                  onPressed: () {},
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(color: AppTheme.accentBlue),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                print('Sign In clicked for ${widget.role}');
                if (widget.role == 'Staff') {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const StaffMainScreen()),
                    (route) => false,
                  );
                } else if (widget.role == 'Customer') {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const CustomerMainScreen()),
                    (route) => false,
                  );
                } else if (widget.role == 'Rider') {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const RiderMainScreen()),
                    (route) => false,
                  );
                }
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.login),
                  const SizedBox(width: 8),
                  const Text('Sign In'),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.role == 'Customer' ? "Don't have an account? " : 'Need help? ',
                  style: AppTheme.lightTheme.textTheme.bodyMedium,
                ),
                TextButton(
                  onPressed: () {
                    if (widget.role == 'Customer') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const CustomerRegistrationScreen()),
                      );
                    }
                  },
                  child: Text(
                    widget.role == 'Customer' ? 'Register' : 'Contact administrator.',
                    style: const TextStyle(color: AppTheme.accentBlue, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
