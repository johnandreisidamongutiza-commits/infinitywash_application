import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_text_field.dart';
import '../services/auth_service.dart';
import '../models/saved_account.dart';
import 'staff/staff_main_screen.dart';
import 'customer/customer_main_screen.dart';
import 'rider/rider_main_screen.dart';
import 'customer/customer_registration_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  final String role;

  const LoginScreen({super.key, required this.role});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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
      print('📋 LOGIN SCREEN: Loading saved accounts for role: ${widget.role}');
      
      final accounts = await _authService.getSavedAccountsByRole(widget.role);
      print('📋 LOGIN SCREEN: Found ${accounts.length} saved accounts');
      
      for (var account in accounts) {
        print('📋   - ${account.email} (${account.displayName})');
      }
      
      setState(() {
        _savedAccounts = accounts;
        _isLoadingSavedAccounts = false;
        
        // Pre-fill the most recent account if available
        if (_savedAccounts.isNotEmpty) {
          _selectedAccount = _savedAccounts.first;
          _emailController.text = _selectedAccount!.email;
          rememberMe = true;
          print('📋 LOGIN SCREEN: Pre-filled with ${_selectedAccount!.email}');
        }
      });
    } catch (e) {
      print('❌ LOGIN SCREEN: Failed to load saved accounts: $e');
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

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Enter your email and password.');
      return;
    }

    print('\n========== LOGIN ATTEMPT ==========');
    print('Email: $email');
    print('Role: ${widget.role}');
    print('Remember Me: $rememberMe');
    print('===================================\n');

    setState(() => _isLoading = true);
    try {
      await _authService.signIn(
        email: email,
        password: password,
        rememberMe: rememberMe,
        role: widget.role,
      );
      
      print('✅ LOGIN: Sign in successful');
      
      if (widget.role == 'Customer') {
        await _authService.ensureCustomerProfileFromMetadata();
      }
      
      final hasRole = widget.role == 'Customer'
          ? await _authService.hasActiveRole(widget.role)
          : await _authService.hasActiveEmployeeRole(widget.role);
      
      print('✅ LOGIN: Role check passed: $hasRole');
          
      if (!hasRole) {
        await _authService.signOut();
        throw Exception('This account is not authorized for the ${widget.role} role.');
      }

      if (!mounted) return;

      final destination = switch (widget.role) {
        'Staff' => const StaffMainScreen(),
        'Customer' => const CustomerMainScreen(),
        'Rider' => const RiderMainScreen(),
        _ => null,
      };

      if (destination != null) {
        print('✅ LOGIN: Navigating to main screen');
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => destination),
          (route) => false,
        );
      }
    } catch (error) {
      print('❌ LOGIN: Failed - $error');
      if (mounted) {
        final message = error is AuthApiException && error.code == 'email_not_confirmed'
            ? 'Email not confirmed. Check your inbox or confirm this user in Supabase Authentication.'
            : 'Login failed: ${error.toString()}';
        _showMessage(message);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.softGray,
                  shape: BoxShape.circle,
                ),
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
              '${widget.role} Login',
              style: AppTheme.lightTheme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to continue to your ${widget.role} account.',
              style: AppTheme.lightTheme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 30),
            
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
                        color: isSelected ? AppTheme.accentBlue.withOpacity(0.05) : Colors.white,
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
            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.borderGray),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, color: AppTheme.accentBlue),
                  const SizedBox(width: 12),
                  Text(
                    widget.role,
                    style: AppTheme.lightTheme.textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Change',
                      style: TextStyle(color: AppTheme.accentBlue),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            CustomTextField(
              label: 'Work Email',
              hint: 'Enter your work email',
              prefixIcon: Icons.email_outlined,
              controller: _emailController,
            ),
            const SizedBox(height: 20),
            CustomTextField(
              label: 'Password',
              hint: 'Enter your password',
              prefixIcon: Icons.lock_outline,
              isPassword: true,
              controller: _passwordController,
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
                      MaterialPageRoute(builder: (context) => ForgotPasswordScreen(role: widget.role)),
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
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.role == 'Customer' ? "Don't have an account? " : 'Need help? ',
                  style: AppTheme.lightTheme.textTheme.bodyMedium,
                ),
                TextButton(
                  onPressed: () {
                    if (widget.role == 'Customer') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const CustomerRegistrationScreen()),
                      );
                    }
                  },
                  child: Text(
                    widget.role == 'Customer' ? 'Register' : 'Contact administrator.',
                    style: const TextStyle(color: AppTheme.accentBlue, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
