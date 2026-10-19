import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../utils/app_error.dart';
import '../utils/validators.dart';
import '../services/connectivity_service.dart';
import '../widgets/custom_text_field.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../utils/save_account_prompt.dart';
import 'staff/staff_main_screen.dart';
import 'customer/customer_main_screen.dart';
import 'rider/rider_main_screen.dart';
import 'customer/customer_registration_screen.dart';
import 'customer/google_profile_completion_screen.dart';
import 'forgot_password_screen.dart';

/// Single, role-agnostic login screen and the app's logged-out entry point.
///
/// The role is never chosen here: after sign-in it is discovered from the
/// backend ([AuthService.getUserRole]) and the user is routed to the matching
/// main screen.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  StreamSubscription<AuthState>? _authSubscription;
  bool _handlingGoogleCallback = false;

  @override
  void initState() {
    super.initState();
    _authSubscription = SupabaseService.client.auth.onAuthStateChange.listen((state) {
      if (CustomerRegistrationScreen.googleSignupInProgress) return;
      final user = state.session?.user;
      if (state.event == AuthChangeEvent.signedIn &&
          user?.appMetadata['provider'] == 'google') {
        _finishGoogleSignIn();
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Map an active backend role to its main screen (null = unsupported role).
  Widget? _destinationForRole(String role) {
    return switch (role) {
      'customer' => const CustomerMainScreen(),
      'staff' => const StaffMainScreen(),
      'rider' => const RiderMainScreen(),
      _ => null,
    };
  }

  Future<void> _signIn() async {
    if (_formKey.currentState?.validate() != true) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // Client-side validation with friendly messages before hitting the API.
    final emailError = Validators.email(email);
    if (emailError != null) {
      _showMessage(emailError);
      return;
    }
    final passwordError = Validators.passwordRequired(password);
    if (passwordError != null) {
      _showMessage(passwordError);
      return;
    }

    // Fail fast when offline — a clear message beats a confusing timeout.
    if (!await ConnectivityService.instance.checkNow()) {
      _showMessage(
        'No internet connection. Please check your connection and try again.',
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _authService.signIn(
        email: email,
        password: password,
        rememberMe: false,
      );

      // Discover the role from the backend — never from local state.
      final role = await _authService.getUserRole();

      if (role == null) {
        await _authService.signOut();
        if (mounted) {
          _showMessage(
            'No active role found for this account. Please contact support.',
          );
        }
        return;
      }

      final maybeDestination = _destinationForRole(role);
      if (maybeDestination == null) {
        await _authService.signOut();
        if (mounted) {
          _showMessage(
            'This account type is not supported in the app yet. '
            'Please contact support.',
          );
        }
        return;
      }

      // Ensure the customer record exists and stays up to date, but only
      // for accounts the backend confirms as customers. Running this
      // before role discovery could overwrite the profile of a promoted
      // staff/rider/admin user whose auth metadata still says 'customer'.
      if (role == 'customer') {
        await _authService.ensureCustomerProfileFromMetadata();
        if (!await _authService.isCustomerProfileComplete()) {
          if (!mounted) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const GoogleProfileCompletionScreen()),
            (_) => false,
          );
          return;
        }
      }

      await offerSaveAccount(context, _authService);

      final Widget destination = maybeDestination;

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => destination),
        (route) => false,
      );
    } catch (error) {
      if (mounted) {
        // mapErrorToMessage turns auth errors (wrong password, unconfirmed
        // email, deactivated account with reason) and network failures into
        // friendly text — never a raw exception dump.
        final message = mapErrorToMessage(error);
        _showMessage(message);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!await ConnectivityService.instance.checkNow()) {
      _showMessage('No internet connection. Please check your connection and try again.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await SupabaseService.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'com.example.infinitywash://login-callback/',
      );
    } catch (error) {
      if (mounted) _showMessage(mapErrorToMessage(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _finishGoogleSignIn() async {
    if (_handlingGoogleCallback) return;
    _handlingGoogleCallback = true;
    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) return;
      final profile = await SupabaseService.client
          .from('profiles')
          .select('role, status')
          .eq('supabase_user_id', user.id)
          .maybeSingle();
      if (!mounted) return;
      if (profile == null || profile['role'] == 'customer') {
        final ready = profile != null && await _authService.isCustomerProfileComplete();
        if (!mounted) return;
        if (!ready) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const GoogleProfileCompletionScreen()),
            (_) => false,
          );
          return;
        }
        await offerSaveAccount(context, _authService);
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const CustomerMainScreen()),
          (_) => false,
        );
        return;
      }
      final role = await _authService.getUserRole();
      final destination = role == null ? null : _destinationForRole(role);
      if (destination == null) {
        await _authService.signOut();
        if (mounted) _showMessage('This account does not have an active app role. Please contact support.');
        return;
      }
      await offerSaveAccount(context, _authService);
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => destination), (_) => false);
    } catch (error) {
      if (mounted) _showMessage(mapErrorToMessage(error));
    } finally {
      _handlingGoogleCallback = false;
    }
  }

  void _showMessage(String message) {
    // Check if it's a deactivation message - show dialog instead of snackbar
    if (message.contains('Your account has been deactivated')) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.block, color: AppTheme.errorRed),
              SizedBox(width: 12),
              Text('Account Deactivated'),
            ],
          ),
          content: Text(
            message,
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK', style: TextStyle(color: AppTheme.accentBlue)),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        // This screen is the logged-out entry point, so only offer going
        // back when it was actually pushed on top of another route.
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: 8),

            // Branding: mascot logo in a clean rounded card (Hero transition from Splash)
            Hero(
              tag: 'app_mascot_logo',
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.05),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/images/logo.jpg',
                      height: 110,
                      width: 110,
                      cacheWidth: 280,
                      cacheHeight: 280,
                      filterQuality: FilterQuality.medium,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.wash,
                        size: 80,
                        color: AppTheme.accentBlue,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Welcome heading.
            Text(
              'Welcome to\nInfinity Wash',
              textAlign: TextAlign.center,
              style: AppTheme.lightTheme.textTheme.displaySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to continue to your account.',
              style: AppTheme.lightTheme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 28),

            CustomTextField(
              label: 'Email',
              hint: 'Enter your email',
              prefixIcon: Icons.email_outlined,
              controller: _emailController,
              validator: Validators.emailField,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 20),
            CustomTextField(
              label: 'Password',
              hint: 'Enter your password',
              prefixIcon: Icons.lock_outline,
              isPassword: true,
              controller: _passwordController,
              validator: Validators.passwordRequired,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ForgotPasswordScreen()),
                    );
                  },
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(color: AppTheme.accentBlue),
                  ),
                ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _isLoading ? null : _signIn,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  const SizedBox(width: 8),
                  Text(_isLoading ? 'Signing In...' : 'Sign In'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _signInWithGoogle,
              icon: const Icon(Icons.g_mobiledata, size: 28),
              label: const Text('Continue with Google'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            ),
            const SizedBox(height: 24),
            // Wrap so the prompt and its action stack instead of overflowing
            // when the text gets wider than the row.
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  "Don't have an account? ",
                  style: AppTheme.lightTheme.textTheme.bodyMedium,
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CustomerRegistrationScreen()),
                    );
                  },
                  child: const Text(
                    'Register',
                    style: TextStyle(color: AppTheme.accentBlue, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
          ),
        ),
      ),
    );
  }
}
