import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../role_selection_screen.dart';
import 'options/account_details_screen.dart';
import 'options/change_password_screen.dart';
import 'options/notification_settings_screen.dart';
import 'options/help_support_screen.dart';

class StaffProfileScreen extends StatelessWidget {
  const StaffProfileScreen({super.key});

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
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppTheme.softGray,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.accentBlue, width: 2),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/logo.jpg',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, size: 60),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AppTheme.accentBlue, shape: BoxShape.circle),
                      child: const Icon(Icons.edit, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Staff Member', style: AppTheme.lightTheme.textTheme.headlineMedium),
            Text('staff@infinitywash.com', style: AppTheme.lightTheme.textTheme.bodyMedium),
            const SizedBox(height: 40),
            _buildProfileOption(
              context,
              Icons.person_outline,
              'Account Details',
              const AccountDetailsScreen(),
            ),
            _buildProfileOption(
              context,
              Icons.lock_outline,
              'Change Password',
              const ChangePasswordScreen(),
            ),
            _buildProfileOption(
              context,
              Icons.notifications_none,
              'Notification Settings',
              const NotificationSettingsScreen(),
            ),
            _buildProfileOption(
              context,
              Icons.auto_awesome,
              'Infinity AI Assistant',
              const HelpSupportScreen(),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.errorRed,
                side: const BorderSide(color: AppTheme.errorRed),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout),
                  SizedBox(width: 8),
                  Text('Logout'),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileOption(BuildContext context, IconData icon, String label, Widget destination) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => destination),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: AppStyles.cardDecoration,
        child: Row(
          children: [
            Icon(icon, color: AppTheme.textDark),
            const SizedBox(width: 16),
            Text(label, style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontSize: 16)),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.textLight),
          ],
        ),
      ),
    );
  }
}
