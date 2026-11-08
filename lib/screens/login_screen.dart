import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../utils/app_error.dart';
import '../utils/role_entry_transition.dart';
import '../utils/validators.dart';
import '../services/connectivity_service.dart';
import '../widgets/custom_text_field.dart';
import '../services/auth_service.dart';
import '../services/secure_storage_service.dart';
import '../services/google_sign_in_service.dart';
import '../services/supabase_service.dart';
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
  final bool isAddingAccount;

  const LoginScreen({
    super.key,
    this.isAddingAccount = false,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _saveAccount = true;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  StreamSubscription<AuthState>? _authSubscription;
  bool _handlingGoogleCallback = false;
  bool _googleSignInInProgress = false;

  late final AnimationController _animController;
  late final Animation<double> _cardFade;
  late final Animation<Offset> _cardSlide;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _cardFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.85, curve: Curves.fastOutSlowIn),
      ),
    );
    _cardSlide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.85, curve: Curves.fastOutSlowIn),
      ),
    );

    _animController.forward();

    _authSubscription = SupabaseService.client.auth.onAuthStateChange.listen((state) {
      if (CustomerRegistrationScreen.googleSignupInProgress) return;
      if (state.event == AuthChangeEvent.signedIn &&
          (_googleSignInInProgress ||
              state.session?.user.appMetadata['provider'] == 'google')) {
        _finishGoogleSignIn();
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animController.dispose();
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
        rememberMe: _saveAccount,
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
            RoleEntryTransition.route(const GoogleProfileCompletionScreen()),
            (_) => false,
          );
          return;
        }
      }

      final Widget destination = maybeDestination;

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        RoleEntryTransition.route(destination),
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
    setState(() {
      _isLoading = true;
      _googleSignInInProgress = true;
    });
    try {
      await GoogleSignInService.signIn();
      await _finishGoogleSignIn();
    } catch (error) {
      if (mounted && !GoogleSignInService.isCancelled(error)) {
        _showMessage(GoogleSignInService.errorMessage(error));
      }
    } finally {
      _googleSignInInProgress = false;
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
            RoleEntryTransition.route(const GoogleProfileCompletionScreen()),
            (_) => false,
          );
          return;
        }
        if (_saveAccount) {
          await _authService.rememberCurrentSession();
        } else {
          await SecureStorageService.instance.clearLastAutoLoginUser();
        }
        Navigator.pushAndRemoveUntil(
          context,
          RoleEntryTransition.route(const CustomerMainScreen()),
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
      if (_saveAccount) {
        await _authService.rememberCurrentSession();
      } else {
        await SecureStorageService.instance.clearLastAutoLoginUser();
      }
      Navigator.pushAndRemoveUntil(
        context,
        RoleEntryTransition.route(destination),
        (_) => false,
      );
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
              child: Text('OK', style: TextStyle(color: AppTheme.primaryBlue)),
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
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AppTheme.softGray,
      appBar: canPop
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
                onPressed: () => Navigator.pop(context),
              ),
            )
          : null,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight > 48.0 ? constraints.maxHeight - 48.0 : 0.0,
                ),
                child: IntrinsicHeight(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: SlideTransition(
                        position: _cardSlide,
                        child: FadeTransition(
                          opacity: _cardFade,
                          child: RepaintBoundary(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(26),
                                border: Border.all(
                                  color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primaryBlue.withValues(alpha: 0.05),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.02),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // Centered Brand Logo
                                    Center(
                                      child: Hero(
                                        tag: 'app_brand_logo',
                                        createRectTween: (begin, end) => RectTween(begin: begin, end: end),
                                        child: RepaintBoundary(
                                          child: Material(
                                            color: Colors.transparent,
                                            child: Container(
                                              width: 80,
                                              height: 80,
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: AppTheme.softGray.withValues(alpha: 0.5),
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                                                  width: 1,
                                                ),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(14),
                                                child: Image.asset(
                                                  'assets/images/logo.png',
                                                  fit: BoxFit.contain,
                                                  filterQuality: FilterQuality.high,
                                                  errorBuilder: (context, error, stackTrace) => const Icon(
                                                    Icons.local_laundry_service,
                                                    size: 40,
                                                    color: AppTheme.primaryBlue,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // Heading
                                    Text(
                                      widget.isAddingAccount
                                          ? 'Add Account to Infinity Wash'
                                          : 'Welcome to Infinity Wash',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.lexend(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primaryBlue,
                                        height: 1.25,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      widget.isAddingAccount
                                          ? 'Sign in to save this account on this device'
                                          : 'Sign in to continue to your account',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.lexend(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                        color: AppTheme.textLight,
                                      ),
                                    ),
                                    const SizedBox(height: 22),

                                    // Email Field
                                    CustomTextField(
                                      label: 'Email address',
                                      hint: 'Enter your email',
                                      prefixIcon: Icons.email_outlined,
                                      controller: _emailController,
                                      validator: Validators.emailField,
                                      keyboardType: TextInputType.emailAddress,
                                      floatingLabel: true,
                                    ),
                                    const SizedBox(height: 14),

                                    // Password Field
                                    CustomTextField(
                                      label: 'Password',
                                      hint: 'Enter your password',
                                      prefixIcon: Icons.lock_outline,
                                      isPassword: true,
                                      controller: _passwordController,
                                      validator: Validators.passwordRequired,
                                      floatingLabel: true,
                                    ),
                                    const SizedBox(height: 12),

                                    // Save Account & Forgot Password
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        InkWell(
                                          onTap: () => setState(() => _saveAccount = !_saveAccount),
                                          borderRadius: BorderRadius.circular(8),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                SizedBox(
                                                  height: 20,
                                                  width: 20,
                                                  child: Checkbox(
                                                    value: _saveAccount,
                                                    onChanged: (v) =>
                                                        setState(() => _saveAccount = v ?? false),
                                                    activeColor: AppTheme.primaryBlue,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    materialTapTargetSize:
                                                        MaterialTapTargetSize.shrinkWrap,
                                                    visualDensity: VisualDensity.compact,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'Save account',
                                                  style: GoogleFonts.lexend(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500,
                                                    color: AppTheme.textDark,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (context) => const ForgotPasswordScreen()),
                                            );
                                          },
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 4, vertical: 4),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          child: Text(
                                            'Forgot password?',
                                            style: GoogleFonts.lexend(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.primaryBlue,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),

                                    // Sign In Button
                                    SizedBox(
                                      height: 48,
                                      child: ElevatedButton(
                                        onPressed: _isLoading ? null : _signIn,
                                        style: ElevatedButton.styleFrom(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            if (_isLoading)
                                              const SizedBox(
                                                height: 18,
                                                width: 18,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                ),
                                              )
                                            else ...[
                                              const Icon(Icons.login, size: 20),
                                              const SizedBox(width: 8),
                                            ],
                                            Text(
                                              _isLoading
                                                  ? 'Signing In...'
                                                  : (widget.isAddingAccount ? 'Sign In & Save' : 'Sign In'),
                                              style: GoogleFonts.lexend(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // Divider "or"
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Divider(
                                            color: AppTheme.borderGray.withValues(alpha: 0.6),
                                            height: 1,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 14),
                                          child: Text(
                                            'or',
                                            style: GoogleFonts.lexend(
                                              fontSize: 12,
                                              color: AppTheme.textLight,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Divider(
                                            color: AppTheme.borderGray.withValues(alpha: 0.6),
                                            height: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // Continue with Google Button
                                    SizedBox(
                                      height: 48,
                                      child: OutlinedButton.icon(
                                        onPressed: _isLoading ? null : _signInWithGoogle,
                                        icon: const Icon(Icons.g_mobiledata, size: 28),
                                        label: Text(
                                          'Continue with Google',
                                          style: GoogleFonts.lexend(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          side: BorderSide(
                                            color: AppTheme.borderGray.withValues(alpha: 0.8),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),

                                    // Footer Register Prompt
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          "Don't have an account? ",
                                          style: GoogleFonts.lexend(
                                            fontSize: 13,
                                            color: AppTheme.textLight,
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => const CustomerRegistrationScreen(),
                                              ),
                                            );
                                          },
                                          borderRadius: BorderRadius.circular(4),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            child: Text(
                                              'Register',
                                              style: GoogleFonts.lexend(
                                                fontSize: 13,
                                                color: AppTheme.primaryBlue,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
