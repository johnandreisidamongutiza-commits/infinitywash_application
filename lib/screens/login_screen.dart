import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/app_error.dart';
import '../utils/validators.dart';
import '../services/connectivity_service.dart';
import '../widgets/custom_text_field.dart';
import '../services/auth_service.dart';
import '../models/saved_account.dart';
import 'staff/staff_main_screen.dart';
import 'customer/customer_main_screen.dart';
import 'rider/rider_main_screen.dart';
import 'customer/customer_registration_screen.dart';
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
  bool rememberMe = false;
  bool _isLoading = false;
  bool _isLoadingSavedAccounts = true;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  List<SavedAccount> _savedAccounts = [];
  SavedAccount? _selectedAccount;

  @override
  void initState() {
    super.initState();
    _loadSavedAccounts();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAccounts() async {
    try {
      final accounts = await _authService.getSavedAccounts();

      if (!mounted) return;
      setState(() {
        _savedAccounts = accounts;
        _isLoadingSavedAccounts = false;

        // Pre-fill the most recent account if available
        if (_savedAccounts.isNotEmpty) {
          _selectedAccount = _savedAccounts.first;
          _emailController.text = _selectedAccount!.email;
          rememberMe = true;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingSavedAccounts = false;
      });
    }
  }

  void _selectAccount(SavedAccount account) {
    setState(() {
      _selectedAccount = account;
      _emailController.text = account.email;
      _passwordController.clear();
      rememberMe = true;
    });
  }

  Future<void> _removeSavedAccount(SavedAccount account) async {
    try {
      await _authService.removeSavedAccount(account.id);
      setState(() {
        _savedAccounts.remove(account);
        if (_selectedAccount?.id == account.id) {
          _selectedAccount = null;
          _emailController.clear();
          _passwordController.clear();
        }
      });
      _showMessage('Account removed from saved accounts');
    } catch (e) {
      _showMessage('Failed to remove account');
    }
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
        rememberMe: rememberMe,
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

      // Ensure the customer record exists and stays up to date, but only
      // for accounts the backend confirms as customers. Running this
      // before role discovery could overwrite the profile of a promoted
      // staff/rider/admin user whose auth metadata still says 'customer'.
      if (role == 'customer') {
        await _authService.ensureCustomerProfileFromMetadata();
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

            // Branding: mascot logo in a soft circle.
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: AppTheme.softGray,
                shape: BoxShape.circle,
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

            // Saved Accounts Section
            if (_isLoadingSavedAccounts)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(),
              )
            else if (_savedAccounts.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Saved Accounts',
                  style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _savedAccounts.length,
                  itemBuilder: (context, index) {
                    final account = _savedAccounts[index];
                    final isSelected = _selectedAccount?.id == account.id;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isSelected ? AppTheme.accentBlue : AppTheme.borderGray,
                          width: isSelected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: isSelected ? AppTheme.accentBlue.withValues(alpha: 0.05) : Colors.white,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.accentBlue,
                          child: Text(
                            account.initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          account.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          account.email,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => _removeSavedAccount(account),
                          tooltip: 'Remove account',
                        ),
                        onTap: () => _selectAccount(account),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 20),
            ],

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
            Row(
              children: [
                Checkbox(
                  value: rememberMe,
                  onChanged: (value) => setState(() => rememberMe = value!),
                  activeColor: AppTheme.accentBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                const Text('Remember me'),
                const Spacer(),
                TextButton(
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
              ],
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
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
