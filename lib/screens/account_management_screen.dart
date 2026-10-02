import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../models/saved_account.dart';
import 'login_screen.dart';
import 'staff/staff_main_screen.dart';
import 'customer/customer_main_screen.dart';
import 'rider/rider_main_screen.dart';

class AccountManagementScreen extends StatefulWidget {
  const AccountManagementScreen({super.key});

  @override
  State<AccountManagementScreen> createState() => _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  final _authService = AuthService();
  List<SavedAccount> _savedAccounts = [];
  bool _isLoading = true;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final currentUser = _authService.getCurrentUser();
      _currentUserId = currentUser?.id;
      
      final accounts = await _authService.getSavedAccounts();
      
      setState(() {
        _savedAccounts = accounts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showMessage('Failed to load saved accounts: $e');
    }
  }

  Future<void> _switchAccount(SavedAccount account) async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch Account'),
        content: Text(
          'Switch to ${account.displayName} (${account.email})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);

    try {
      // Sign out current user
      await _authService.signOut();

      // Try to auto-login with selected account
      final authResponse = await _authService.tryAutoLogin(userId: account.id);

      if (authResponse != null && authResponse.user != null) {
        // Discover the account's role from the backend
        final role = await _authService.getUserRole();

        if (role == null) {
          await _authService.signOut();
          if (mounted) {
            setState(() => _isLoading = false);
            _showMessage('Could not verify account access. Please log in again.');
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
            );
          }
          return;
        }

        final maybeDestination = switch (role) {
          'customer' => const CustomerMainScreen(),
          'staff' => const StaffMainScreen(),
          'rider' => const RiderMainScreen(),
          _ => null,
        };

        if (maybeDestination == null) {
          await _authService.signOut();
          if (mounted) {
            setState(() => _isLoading = false);
            _showMessage('This account type is not supported in the app yet. Please contact support.');
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
            );
          }
          return;
        }

        final Widget destination = maybeDestination;

        if (!mounted) return;

        _showMessage('Switched to ${account.displayName}');
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => destination),
          (route) => false,
        );
      } else {
        // Token expired or invalid, go to role selection
        if (!mounted) return;
        _showMessage('Session expired. Please log in again.');
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage('Failed to switch account: $e');
      }
    }
  }

  Future<void> _removeAccount(SavedAccount account) async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Saved Account'),
        content: Text(
          'Remove ${account.displayName} (${account.email}) from saved accounts?\n\nYou will need to log in again to use this account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // If removing current account, sign out
      if (account.id == _currentUserId) {
        await _authService.signOut();
      }

      await _authService.removeSavedAccount(account.id);

      setState(() {
        _savedAccounts.remove(account);
      });

      if (!mounted) return;

      // If removed current account, go to role selection
      if (account.id == _currentUserId) {
        _showMessage('Account removed. Please log in again.');
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      } else {
        _showMessage('Account removed from saved accounts');
      }
    } catch (e) {
      _showMessage('Failed to remove account: $e');
    }
  }

  Future<void> _clearAllAccounts() async {
    if (_savedAccounts.isEmpty) {
      _showMessage('No saved accounts to clear');
      return;
    }

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Saved Accounts'),
        content: Text(
          'Remove all ${_savedAccounts.length} saved account(s)?\n\nYou will be signed out and need to log in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      await _authService.signOut();
      await _authService.clearAllSavedAccounts();

      if (!mounted) return;

      _showMessage('All accounts cleared');
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage('Failed to clear accounts: $e');
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
        title: const Text('Manage Accounts'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_savedAccounts.length > 1)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _clearAllAccounts,
              tooltip: 'Clear all saved accounts',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _savedAccounts.isEmpty
              ? _buildEmptyState()
              : _buildAccountList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_circle_outlined,
            size: 100,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 20),
          Text(
            'No Saved Accounts',
            style: AppTheme.lightTheme.textTheme.headlineSmall?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Enable "Remember Me" when logging in\nto save accounts for quick access.',
            textAlign: TextAlign.center,
            style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountList() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Saved Accounts (${_savedAccounts.length})',
          style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap an account to switch. Long press to see options.',
          style: AppTheme.lightTheme.textTheme.bodySmall?.copyWith(
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 20),
        ..._savedAccounts.map((account) => _buildAccountCard(account)),
      ],
    );
  }

  Widget _buildAccountCard(SavedAccount account) {
    final isCurrentUser = account.id == _currentUserId;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(
          color: isCurrentUser ? AppTheme.accentBlue : AppTheme.borderGray,
          width: isCurrentUser ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
        color: isCurrentUser ? AppTheme.accentBlue.withValues(alpha: 0.05) : Colors.white,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          radius: 30,
          backgroundColor: AppTheme.accentBlue,
          child: Text(
            account.initials,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                account.displayName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
            if (isCurrentUser)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Current',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              account.email,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  _formatLastLogin(account.lastLoginDate),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'switch' && !isCurrentUser) {
              _switchAccount(account);
            } else if (value == 'remove') {
              _removeAccount(account);
            }
          },
          itemBuilder: (context) => [
            if (!isCurrentUser)
              const PopupMenuItem(
                value: 'switch',
                child: Row(
                  children: [
                    Icon(Icons.swap_horiz, size: 20),
                    SizedBox(width: 8),
                    Text('Switch to this account'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'remove',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Remove', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
        onTap: isCurrentUser ? null : () => _switchAccount(account),
      ),
    );
  }

  String _formatLastLogin(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }
}
