import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/custom_text_field.dart';
import '../../role_selection_screen.dart';

class RiderProfileScreen extends StatefulWidget {
  const RiderProfileScreen({super.key});

  @override
  State<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends State<RiderProfileScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildProfileHeader(),
            const SizedBox(height: 40),
            const CustomTextField(label: 'Full Name', hint: 'John Rider', prefixIcon: Icons.person_outline),
            const SizedBox(height: 20),
            const CustomTextField(label: 'Phone Number', hint: '0912-345-6789', prefixIcon: Icons.phone_android),
            const SizedBox(height: 20),
            const CustomTextField(label: 'Vehicle Plate', hint: 'ABC-1234', prefixIcon: Icons.moped_outlined),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Information Updated'), backgroundColor: Colors.green),
                );
              },
              child: const Text('Confirm New Information'),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
                  (route) => false,
                );
              },
              child: const Text('Logout', style: TextStyle(color: AppTheme.errorRed, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(color: AppTheme.softGray, shape: BoxShape.circle, border: Border.all(color: AppTheme.accentBlue, width: 2)),
          child: const Icon(Icons.person, size: 60, color: AppTheme.accentBlue),
        ),
        const SizedBox(height: 16),
        const Text('John Rider', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        const Text('Infinity Rider since 2026', style: TextStyle(color: AppTheme.textLight, fontSize: 12)),
      ],
    );
  }
}
