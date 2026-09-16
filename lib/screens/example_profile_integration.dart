// THIS IS AN EXAMPLE FILE
// Shows how to integrate the SavedAccountsWidget into your profile/settings screens
// DO NOT USE THIS FILE DIRECTLY - Copy the relevant parts to your actual profile screen

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/saved_accounts_widget.dart';
import '../services/auth_service.dart';

class ExampleProfileScreen extends StatelessWidget {
  const ExampleProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Settings'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        children: [
          // User Info Section
          _buildUserInfoSection(context),
          
          const Divider(height: 1),
          
          // Account Management Section
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Account Management',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          // Saved Accounts Widget - Option 1: Card Style
          const SavedAccountsWidget(),
          
          // OR Option 2: List Tile Style (choose one)
          // const SavedAccountsListTile(),
          
          const Divider(height: 1),
          
          // Other Settings
          _buildOtherSettings(context),
        ],
      ),
    );
  }

  Widget _buildUserInfoSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: AppTheme.accentBlue,
            child: const Icon(
              Icons.person,
              size: 50,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'John Doe',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'john.doe@example.com',
            style: TextStyle(
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtherSettings(BuildContext context) {
    final authService = AuthService();
    
    return Column(
      children: [
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'General Settings',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('Notifications'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            // Navigate to notifications settings
          },
        ),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('Privacy & Security'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            // Navigate to privacy settings
          },
        ),
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: const Text('Help & Support'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            // Navigate to help
          },
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: const Text(
            'Sign Out',
            style: TextStyle(color: Colors.red),
          ),
          onTap: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Sign Out'),
                content: const Text(
                  'Are you sure you want to sign out?\n\nYour account will remain saved for quick login.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            );

            if (confirm == true) {
              await authService.signOut();
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                  (route) => false,
                );
              }
            }
          },
        ),
      ],
    );
  }
}
