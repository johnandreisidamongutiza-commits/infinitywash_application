import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_text_field.dart';

class CustomerRegistrationScreen extends StatefulWidget {
  const CustomerRegistrationScreen({super.key});

  @override
  State<CustomerRegistrationScreen> createState() => _CustomerRegistrationScreenState();
}

class _CustomerRegistrationScreenState extends State<CustomerRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  'Create Account',
                  style: AppTheme.lightTheme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Join Infinity Wash and experience the best laundry service.',
                  style: AppTheme.lightTheme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                    const Expanded(
                      child: CustomTextField(
                        label: 'First Name',
                        hint: 'John',
                        prefixIcon: Icons.person_outline,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: CustomTextField(
                        label: 'Last Name',
                        hint: 'Doe',
                        prefixIcon: Icons.person_outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const CustomTextField(
                  label: 'Mobile Number',
                  hint: '09XX-XXX-XXXX',
                  prefixIcon: Icons.phone_android_outlined,
                ),
                const SizedBox(height: 20),
                const CustomTextField(
                  label: 'Email Address',
                  hint: 'Enter your email',
                  prefixIcon: Icons.email_outlined,
                ),
                const SizedBox(height: 20),
                const CustomTextField(
                  label: 'Address',
                  hint: 'Enter your primary address',
                  prefixIcon: Icons.location_on_outlined,
                ),
                const SizedBox(height: 20),
                const CustomTextField(
                  label: 'Landmark (Optional)',
                  hint: 'Near Parkmall / Blue Building',
                  prefixIcon: Icons.assistant_navigation,
                ),
                const SizedBox(height: 20),
                const CustomTextField(
                  label: 'Password',
                  hint: 'Create a password',
                  prefixIcon: Icons.lock_outline,
                  isPassword: true,
                ),
                const SizedBox(height: 20),
                const CustomTextField(
                  label: 'Confirm Password',
                  hint: 'Repeat your password',
                  prefixIcon: Icons.lock_reset_outlined,
                  isPassword: true,
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Registration successful! Please sign in.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    Navigator.pop(context);
                  },
                  child: const Text('Register'),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Already have an account? '),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          color: AppTheme.accentBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
