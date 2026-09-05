import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/role_card.dart';
import 'login_screen.dart';

class TeamMemberSelectionScreen extends StatefulWidget {
  const TeamMemberSelectionScreen({super.key});

  @override
  State<TeamMemberSelectionScreen> createState() => _TeamMemberSelectionScreenState();
}

class _TeamMemberSelectionScreenState extends State<TeamMemberSelectionScreen> {
  String? selectedRole;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.softGray,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppTheme.textDark),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.softGray,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(4),
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
                'Team Member Login',
                style: AppTheme.lightTheme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Select your role to continue',
                style: AppTheme.lightTheme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 40),
              Row(
                children: [
                  Expanded(
                    child: RoleCard(
                      title: 'Staff',
                      subtitle: 'Process laundry\norders',
                      layout: RoleCardLayout.vertical,
                      isSelected: selectedRole == 'Staff',
                      icon: const Icon(Icons.shopping_bag_outlined, color: AppTheme.accentBlue, size: 40),
                      onTap: () => setState(() => selectedRole = 'Staff'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: RoleCard(
                      title: 'Rider',
                      subtitle: 'Manage pickups\nand deliveries',
                      layout: RoleCardLayout.vertical,
                      isSelected: selectedRole == 'Rider',
                      icon: const Icon(Icons.moped_outlined, color: AppTheme.errorRed, size: 40),
                      onTap: () => setState(() => selectedRole = 'Rider'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: selectedRole == null
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LoginScreen(role: selectedRole!),
                          ),
                        );
                      },
                child: const Text('Continue'),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Back to account types',
                      style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.accentBlue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.accentBlue),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
