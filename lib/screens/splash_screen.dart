import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import 'role_selection_screen.dart';
import 'staff/staff_main_screen.dart';
import 'customer/customer_main_screen.dart';
import 'rider/rider_main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  String _statusMessage = 'Initializing...';

  @override
  void initState() {
    super.initState();
    
    // Setup animation
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    
    _animationController.forward();
    
    // Start auto-login check
    _checkAutoLogin();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkAutoLogin() async {
    try {
      // Add a small delay for better UX
      await Future.delayed(const Duration(milliseconds: 800));
      
      setState(() {
        _statusMessage = 'Checking saved accounts...';
      });

      // Try to auto-login with the last saved account
      final authResponse = await _authService.tryAutoLogin();
      
      if (authResponse != null && authResponse.user != null) {
        setState(() {
          _statusMessage = 'Logging in...';
        });
        
        // Get the user's role from saved accounts
        final savedAccounts = await _authService.getSavedAccounts();
        final savedAccount = savedAccounts.firstWhere(
          (account) => account.id == authResponse.user!.id,
          orElse: () => savedAccounts.first,
        );
        
        final role = savedAccount.role;
        
        // Verify the role is still active
        final hasRole = role == 'Customer'
            ? await _authService.hasActiveRole(role)
            : await _authService.hasActiveEmployeeRole(role);
        
        if (!hasRole) {
          // Role no longer active, remove saved data and go to role selection
          await _authService.removeSavedAccount(authResponse.user!.id);
          await _authService.signOut();
          _navigateToRoleSelection();
          return;
        }
        
        // Navigate to appropriate screen based on role
        if (mounted) {
          final destination = switch (role) {
            'Staff' => const StaffMainScreen(),
            'Customer' => const CustomerMainScreen(),
            'Rider' => const RiderMainScreen(),
            _ => null,
          };
          
          if (destination != null) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => destination),
            );
            return;
          }
        }
      }
      
      // No auto-login or failed, go to role selection
      _navigateToRoleSelection();
      
    } catch (e) {
      print('Auto-login error: $e');
      _navigateToRoleSelection();
    }
  }

  void _navigateToRoleSelection() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.softGray,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accentBlue.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/logo.jpg',
                    height: 120,
                    width: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.wash,
                      size: 120,
                      color: AppTheme.accentBlue,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              
              // App Name
              Text(
                'Infinity Wash',
                style: AppTheme.lightTheme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accentBlue,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Professional Laundry Service',
                style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 60),
              
              // Loading Indicator
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentBlue),
                ),
              ),
              const SizedBox(height: 20),
              
              // Status Message
              Text(
                _statusMessage,
                style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
