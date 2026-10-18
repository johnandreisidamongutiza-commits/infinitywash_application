import 'package:flutter/material.dart';

import '../models/saved_account.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'customer/customer_main_screen.dart';
import 'customer/google_profile_completion_screen.dart';
import 'login_screen.dart';
import 'rider/rider_main_screen.dart';
import 'staff/staff_main_screen.dart';

class SavedAccountsScreen extends StatefulWidget {
  const SavedAccountsScreen({super.key});

  @override
  State<SavedAccountsScreen> createState() => _SavedAccountsScreenState();
}

class _SavedAccountsScreenState extends State<SavedAccountsScreen> {
  final _authService = AuthService();
  List<SavedAccount> _accounts = [];
  bool _loading = true;
  String? _openingAccountId;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    try {
      final accounts = await _authService.getSavedAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Could not load saved accounts. Please try again.');
    }
  }

  Future<void> _openAccount(SavedAccount account) async {
    setState(() => _openingAccountId = account.id);
    try {
      final currentUser = _authService.getCurrentUser();
      if (currentUser != null && currentUser.id != account.id) {
        await _authService.signOut();
      }
      final response = await _authService.tryAutoLogin(userId: account.id);
      final user = response?.user;
      if (user == null) {
        await _authService.signOut();
        await _loadAccounts();
        if (mounted) _message('That saved session expired. Add the account again to sign in.');
        return;
      }

      final role = await _authService.getUserRole();
      if (!mounted) return;
      if (role == 'customer') {
        if (!await _authService.isCustomerProfileComplete()) {
          _replaceWith(const GoogleProfileCompletionScreen());
          return;
        }
        _replaceWith(const CustomerMainScreen());
      } else if (role == 'staff') {
        _replaceWith(const StaffMainScreen());
      } else if (role == 'rider') {
        _replaceWith(const RiderMainScreen());
      } else if (user.appMetadata['provider'] == 'google') {
        _replaceWith(const GoogleProfileCompletionScreen());
      } else {
        await _authService.signOut();
        _message('We could not verify this saved account. Please sign in again.');
      }
    } catch (_) {
      if (mounted) _message('Could not open this account. Please try again.');
    } finally {
      if (mounted) setState(() => _openingAccountId = null);
    }
  }

  Future<void> _addAccount() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    ).then((_) => _loadAccounts());
  }

  Future<void> _removeAccount(SavedAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove saved account?'),
        content: Text('${account.displayName} will need to sign in again on this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _authService.removeSavedAccount(account.id);
    await _loadAccounts();
  }

  void _replaceWith(Widget screen) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => screen),
      (_) => false,
    );
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 152,
                              height: 152,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.softGray,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.accentBlue.withValues(alpha: 0.12),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: SizedBox.expand(
                                  child: Image.asset(
                                    'assets/images/logo.jpg',
                                    width: 136,
                                    height: 136,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Center(
                                      child: Icon(Icons.wash, size: 88, color: AppTheme.accentBlue),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text('Welcome back', textAlign: TextAlign.center, style: AppTheme.lightTheme.textTheme.headlineMedium),
                          const SizedBox(height: 8),
                          Text(
                            _accounts.isEmpty ? 'Sign in or add an account to continue.' : 'Choose an account to continue.',
                            textAlign: TextAlign.center,
                            style: AppTheme.lightTheme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 24),
                          for (final account in _accounts)
                            Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.accentBlue,
                                  child: Text(account.initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                                title: Text(
                                  account.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  account.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: _openingAccountId == account.id
                                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                    : IconButton(
                                        tooltip: 'Remove saved account',
                                        icon: const Icon(Icons.close),
                                        onPressed: _openingAccountId == null ? () => _removeAccount(account) : null,
                                      ),
                                onTap: _openingAccountId == null ? () => _openAccount(account) : null,
                              ),
                            ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _openingAccountId == null ? _addAccount : null,
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('Add account'),
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      );
}
