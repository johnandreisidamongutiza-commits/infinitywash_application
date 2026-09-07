import 'package:flutter/material.dart';
import '../../../../widgets/custom_text_field.dart';

class AccountDetailsScreen extends StatelessWidget {
  const AccountDetailsScreen({super.key});

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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const CustomTextField(
              label: 'Full Name',
              hint: 'Staff Member',
              prefixIcon: Icons.person_outline,
            ),
            const SizedBox(height: 20),
            const CustomTextField(
              label: 'Email Address',
              hint: 'staff@infinitywash.com',
              prefixIcon: Icons.email_outlined,
            ),
            const SizedBox(height: 20),
            const CustomTextField(
              label: 'Phone Number',
              hint: '0912-345-6789',
              prefixIcon: Icons.phone_android_outlined,
            ),
            const SizedBox(height: 20),
            const CustomTextField(
              label: 'Staff ID',
              hint: 'IW-STAFF-001',
              prefixIcon: Icons.badge_outlined,
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profile updated successfully!')),
                );
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}
