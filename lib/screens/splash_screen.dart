import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'saved_accounts_screen.dart';

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

      setState(() => _statusMessage = 'Checking saved accounts...');
      final accounts = await _authService.getSavedAccounts();
      if (!mounted) return;
      if (accounts.isNotEmpty) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const SavedAccountsScreen()),
        );
        return;
      }

      // No opt-in account is saved on this device, so start at the regular
      // sign-in screen instead of silently restoring a leftover SDK session.
      await _authService.signOut();
      _navigateToLogin();

    } catch (e) {
      print('Auto-login error: $e');
      // A saved-session failure (offline, expired token) must never crash the
      // splash — fall through to the login screen where the user gets a
      // clear, mapped message when they try to sign in.
      _navigateToLogin();
    }
  }

  void _navigateToLogin() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
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
                      color: AppTheme.accentBlue.withValues(alpha: 0.2),
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
