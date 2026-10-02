// TEMPORARY DEBUG SCREEN - FOR TESTING ONLY
// Add a button to your profile/settings to navigate here
// Remove this file once remember me is working

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/secure_storage_service.dart';
import '../services/saved_accounts_db.dart';

class RememberMeDebugScreen extends StatefulWidget {
  const RememberMeDebugScreen({super.key});

  @override
  State<RememberMeDebugScreen> createState() => _RememberMeDebugScreenState();
}

class _RememberMeDebugScreenState extends State<RememberMeDebugScreen> {
  final _authService = AuthService();
  final _secureStorage = SecureStorageService.instance;
  final _db = SavedAccountsDatabase.instance;
  
  String _output = 'Tap "Run Diagnostics" to check Remember Me status';
  bool _isLoading = false;

  Future<void> _runDiagnostics() async {
    setState(() {
      _isLoading = true;
      _output = 'Running diagnostics...\n';
    });

    final buffer = StringBuffer();
    buffer.writeln('========== REMEMBER ME DIAGNOSTICS ==========\n');

    try {
      // 1. Check current user
      buffer.writeln('1. CURRENT SESSION:');
      final currentUser = _authService.getCurrentUser();
      if (currentUser != null) {
        buffer.writeln('   ✅ Logged in as: ${currentUser.email}');
        buffer.writeln('   User ID: ${currentUser.id}');
      } else {
        buffer.writeln('   ❌ No user logged in');
      }
      buffer.writeln('');

      // 2. Check saved accounts in database
      buffer.writeln('2. SAVED ACCOUNTS (SQLite):');
      final accounts = await _authService.getSavedAccounts();
      buffer.writeln('   Total accounts: ${accounts.length}');
      if (accounts.isEmpty) {
        buffer.writeln('   ⚠️  No saved accounts found');
        buffer.writeln('   💡 Try logging in with "Remember Me" checked');
      } else {
        for (var account in accounts) {
          buffer.writeln('   - ${account.email}');
          buffer.writeln('     Name: ${account.displayName}');
          buffer.writeln('     Last login: ${account.lastLoginDate}');
        }
      }
      buffer.writeln('');

      // 3. Check last auto-login user
      buffer.writeln('3. AUTO-LOGIN CONFIGURATION:');
      final lastAutoUser = await _secureStorage.getLastAutoLoginUser();
      if (lastAutoUser != null) {
        buffer.writeln('   ✅ Last auto-login user: $lastAutoUser');
        
        // Check if this user has valid token
        final hasValidToken = await _secureStorage.isTokenValid(lastAutoUser);
        buffer.writeln('   Token valid: ${hasValidToken ? "✅ Yes" : "❌ No (expired)"}');
        
        if (hasValidToken) {
          final tokenExpiry = await _secureStorage.getTokenExpiry(lastAutoUser);
          if (tokenExpiry != null) {
            final remaining = tokenExpiry.difference(DateTime.now());
            buffer.writeln('   Token expires in: ${remaining.inMinutes} minutes');
          }
        }
      } else {
        buffer.writeln('   ⚠️  No auto-login user configured');
      }
      buffer.writeln('');

      // 4. Check secure storage
      buffer.writeln('4. SECURE STORAGE:');
      final userIds = await _secureStorage.getAllUserIdsWithTokens();
      buffer.writeln('   Users with stored tokens: ${userIds.length}');
      for (var userId in userIds) {
        buffer.writeln('   - $userId');
        final hasAccessToken = await _secureStorage.getAccessToken(userId) != null;
        final hasRefreshToken = await _secureStorage.getRefreshToken(userId) != null;
        buffer.writeln('     Access token: ${hasAccessToken ? "✅" : "❌"}');
        buffer.writeln('     Refresh token: ${hasRefreshToken ? "✅" : "❌"}');
      }
      buffer.writeln('');

      // 5. Database file location
      buffer.writeln('5. DATABASE LOCATION:');
      final dbPath = await getDatabasesPath();
      buffer.writeln('   Path: $dbPath');
      buffer.writeln('   File: ${path.join(dbPath, 'saved_accounts.db')}');
      buffer.writeln('');

      // 6. Check raw database
      buffer.writeln('6. RAW DATABASE QUERY:');
      try {
        final db = await _db.database;
        final rawAccounts = await db.query('saved_accounts');
        buffer.writeln('   Raw rows: ${rawAccounts.length}');
        if (rawAccounts.isNotEmpty) {
          buffer.writeln('   Sample: ${rawAccounts.first}');
        }
      } catch (e) {
        buffer.writeln('   ❌ Error: $e');
      }
      buffer.writeln('');

      buffer.writeln('========== DIAGNOSIS COMPLETE ==========\n');

      // Recommendations
      buffer.writeln('RECOMMENDATIONS:');
      if (accounts.isEmpty) {
        buffer.writeln('❗ No saved accounts. Login with "Remember Me" checked.');
      } else if (lastAutoUser == null) {
        buffer.writeln('⚠️  Auto-login not configured. Should be set after login.');
      } else {
        final hasValidToken = await _secureStorage.isTokenValid(lastAutoUser);
        if (!hasValidToken) {
          buffer.writeln('⚠️  Token expired. Login again to refresh.');
        } else {
          buffer.writeln('✅ Everything looks good! Auto-login should work.');
        }
      }

    } catch (e) {
      buffer.writeln('\n❌ ERROR DURING DIAGNOSTICS:');
      buffer.writeln(e.toString());
      buffer.writeln('\nStack trace:');
      buffer.writeln(StackTrace.current.toString());
    }

    setState(() {
      _output = buffer.toString();
      _isLoading = false;
    });
  }

  Future<void> _testSecureStorage() async {
    setState(() => _isLoading = true);
    final buffer = StringBuffer();
    buffer.writeln('Testing Secure Storage...\n');

    try {
      // Write test
      await _secureStorage.storage.write(key: 'test_key', value: 'test_value');
      buffer.writeln('✅ Write test: Success');

      // Read test
      final value = await _secureStorage.storage.read(key: 'test_key');
      if (value == 'test_value') {
        buffer.writeln('✅ Read test: Success');
      } else {
        buffer.writeln('❌ Read test: Failed (got: $value)');
      }

      // Delete test
      await _secureStorage.storage.delete(key: 'test_key');
      final deletedValue = await _secureStorage.storage.read(key: 'test_key');
      if (deletedValue == null) {
        buffer.writeln('✅ Delete test: Success');
      } else {
        buffer.writeln('❌ Delete test: Failed');
      }

      buffer.writeln('\n✅ Secure Storage is working correctly!');
    } catch (e) {
      buffer.writeln('\n❌ Secure Storage Error: $e');
    }

    setState(() {
      _output = buffer.toString();
      _isLoading = false;
    });
  }

  Future<void> _clearAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
          'This will remove all saved accounts and tokens.\n\n'
          'You will need to login again with "Remember Me" checked.\n\n'
          'Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await _authService.clearAllSavedAccounts();
      setState(() {
        _output = '✅ All saved accounts and tokens cleared!\n\n'
            'Now login with "Remember Me" checked to test the feature.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _output = '❌ Error clearing data: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Remember Me Debug'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _runDiagnostics,
                        icon: const Icon(Icons.bug_report),
                        label: const Text('Run Diagnostics'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentBlue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _testSecureStorage,
                        icon: const Icon(Icons.security),
                        label: const Text('Test Storage'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _clearAllData,
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('Clear All Saved Data'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SelectableText(
                      _output,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
