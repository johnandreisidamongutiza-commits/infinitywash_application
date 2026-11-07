import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/role_entry_transition.dart';
import 'customer/customer_main_screen.dart';
import 'customer/google_profile_completion_screen.dart';
import 'login_screen.dart';
import 'rider/rider_main_screen.dart';
import 'saved_accounts_screen.dart';
import 'staff/staff_main_screen.dart';

/// A lightweight routing gate while local account data and any saved session
/// are restored. It has no progress message or minimum display duration.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    var accountListLoaded = false;
    var hasSavedAccounts = false;

    try {
      final accounts = await _authService.getSavedAccounts();
      accountListLoaded = true;
      hasSavedAccounts = accounts.isNotEmpty;
      if (!mounted) return;

      if (!hasSavedAccounts) {
        // Clear a stale Supabase session so the login screen cannot treat it
        // as an account the user chose to remember on this device.
        await _authService.signOut();
        if (!mounted) return;
        _navigateToLogin();
        return;
      }

      final response = await _authService.tryAutoLogin();
      if (!mounted) return;

      final user = response?.user;
      if (user != null) {
        final role = await _authService.getUserRole();
        if (!mounted) return;

        if (role == 'customer') {
          if (!await _authService.isCustomerProfileComplete()) {
            _replaceWith(const GoogleProfileCompletionScreen());
          } else {
            _replaceWith(const CustomerMainScreen());
          }
          return;
        }
        if (role == 'staff') {
          _replaceWith(const StaffMainScreen());
          return;
        }
        if (role == 'rider') {
          _replaceWith(const RiderMainScreen());
          return;
        }

        await _authService.signOut();
        if (!mounted) return;
      }

      // Keep remembered accounts available when auto-login cannot restore a
      // session, such as when the device is offline or a token has expired.
      _navigateToSavedAccounts();
    } catch (error, stackTrace) {
      debugPrint('Auto-login error: $error\n$stackTrace');
      if (!mounted) return;

      if (accountListLoaded && hasSavedAccounts) {
        _navigateToSavedAccounts();
      } else {
        _navigateToLogin();
      }
    }
  }

  void _navigateToLogin() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  void _navigateToSavedAccounts() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const SavedAccountsScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  void _replaceWith(Widget screen) {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      RoleEntryTransition.route(screen),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.softGray,
      body: const SizedBox.expand(),
    );
  }
}
