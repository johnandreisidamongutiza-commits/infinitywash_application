import 'package:flutter/material.dart';
import '../../../../widgets/custom_text_field.dart';

class ChangePasswordScreen extends StatelessWidget {
  const ChangePasswordScreen({super.key});

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
        child: Column(
          children: [
            const CustomTextField(
              label: 'Current Password',
              hint: '••••••••',
              prefixIcon: Icons.lock_outline,
              isPassword: true,
            ),
            const SizedBox(height: 20),
            const CustomTextField(
              label: 'New Password',
              hint: '••••••••',
              prefixIcon: Icons.lock_outline,
              isPassword: true,
            ),
            const SizedBox(height: 20),
            const CustomTextField(
              label: 'Confirm New Password',
              hint: '••••••••',
              prefixIcon: Icons.lock_reset_outlined,
              isPassword: true,
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password changed successfully!')),
                );
              },
              child: const Text('Update Password'),
            ),
          ],
        ),
      ),
    );
  }
}
