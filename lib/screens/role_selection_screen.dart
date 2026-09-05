import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/role_card.dart';
import 'team_member_selection_screen.dart';
import 'login_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              const SizedBox(height: 40),
              // Mascot Image
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.softGray,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(8),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/logo.jpg',
                    height: 180,
                    width: 180,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.wash,
                      size: 180,
                      color: AppTheme.accentBlue,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Text(
                'Welcome to\nInfinity Wash',
                textAlign: TextAlign.center,
                style: AppTheme.lightTheme.textTheme.displaySmall,
              ),
              const SizedBox(height: 16),
              Text(
                'Choose how you want to continue',
                style: AppTheme.lightTheme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              const Icon(Icons.auto_awesome, color: AppTheme.accentBlue, size: 24),
              const SizedBox(height: 40),
              RoleCard(
                title: 'Customer',
                subtitle: 'Book, manage, and track\nyour laundry.',
                icon: const Icon(Icons.shopping_bag_outlined, color: AppTheme.accentBlue, size: 30),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(role: 'Customer'),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              RoleCard(
                title: 'Team Member',
                subtitle: 'For Staff and Riders.',
                icon: const Icon(Icons.assignment_ind_outlined, color: AppTheme.teamMemberIconOrange, size: 30),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TeamMemberSelectionScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.headset_mic_outlined, color: AppTheme.errorRed, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Need help? ',
                    style: AppTheme.lightTheme.textTheme.bodyMedium,
                  ),
                  TextButton(
                    onPressed: () {},
                    child: Text(
                      'Contact support.',
                      style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
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
    );
  }
}
