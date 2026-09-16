import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../models/saved_account.dart';
import '../screens/account_management_screen.dart';

/// A widget that displays saved accounts count and provides quick access to account management
/// Add this to your profile or settings screen
class SavedAccountsWidget extends StatefulWidget {
  const SavedAccountsWidget({super.key});

  @override
  State<SavedAccountsWidget> createState() => _SavedAccountsWidgetState();
}

class _SavedAccountsWidgetState extends State<SavedAccountsWidget> {
  final _authService = AuthService();
  int _accountCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAccountCount();
  }

  Future<void> _loadAccountCount() async {
    try {
      final accounts = await _authService.getSavedAccounts();
      if (mounted) {
        setState(() {
          _accountCount = accounts.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.accentBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.people_outline,
            color: AppTheme.accentBlue,
            size: 28,
          ),
        ),
        title: const Text(
          'Saved Accounts',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: _isLoading
            ? const Text('Loading...')
            : Text(
                _accountCount == 0
                    ? 'No saved accounts'
                    : '$_accountCount saved account${_accountCount > 1 ? 's' : ''}',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AccountManagementScreen(),
            ),
          ).then((_) {
            // Refresh count when returning from account management
            _loadAccountCount();
          });
        },
      ),
    );
  }
}

/// A compact version for use in settings lists
class SavedAccountsListTile extends StatefulWidget {
  const SavedAccountsListTile({super.key});

  @override
  State<SavedAccountsListTile> createState() => _SavedAccountsListTileState();
}

class _SavedAccountsListTileState extends State<SavedAccountsListTile> {
  final _authService = AuthService();
  int _accountCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAccountCount();
  }

  Future<void> _loadAccountCount() async {
    try {
      final accounts = await _authService.getSavedAccounts();
      if (mounted) {
        setState(() {
          _accountCount = accounts.length;
        });
      }
    } catch (e) {
      // Silent fail
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.people_outline, color: AppTheme.accentBlue),
      title: const Text('Saved Accounts'),
      subtitle: Text('$_accountCount account${_accountCount != 1 ? 's' : ''}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const AccountManagementScreen(),
          ),
        ).then((_) => _loadAccountCount());
      },
    );
  }
}
