import 'package:flutter/material.dart';
import '../services/profile_sync_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Screen to fix missing profiles for users who have auth but no profile
class ProfileFixScreen extends StatefulWidget {
  const ProfileFixScreen({super.key});

  @override
  State<ProfileFixScreen> createState() => _ProfileFixScreenState();
}

class _ProfileFixScreenState extends State<ProfileFixScreen> {
  final _profileSyncService = ProfileSyncService();
  final _authService = AuthService();
  bool _isLoading = false;
  String _statusMessage = '';
  
  @override
  void initState() {
    super.initState();
    _checkStatus();
  }
  
  Future<void> _checkStatus() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Checking...';
    });
    
    await _profileSyncService.debugCheckMissingProfiles();
    
    setState(() {
      _isLoading = false;
      _statusMessage = 'Check console for details';
    });
  }
  
  Future<void> _createProfile() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Creating profile...';
    });
    
    try {
      final success = await _profileSyncService.ensureCurrentUserProfile();
      
      if (success) {
        setState(() {
          _statusMessage = '✅ Profile created successfully!';
        });
        
        // Show success dialog
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Success!'),
              content: const Text(
                'Your profile has been created. You can now use password reset and other features.'
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // Close dialog
                    Navigator.pop(context); // Close fix screen
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      } else {
        setState(() {
          _statusMessage = '❌ Failed to create profile. Check console.';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final currentUser = _authService.getCurrentUser();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fix Missing Profile'),
        backgroundColor: AppTheme.accentBlue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.account_circle_outlined,
              size: 80,
              color: AppTheme.accentBlue,
            ),
            const SizedBox(height: 24),
            const Text(
              'Profile Sync Tool',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'This tool creates a profile in the database for your account.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current Account:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (currentUser != null) ...[
                      Text('Email: ${currentUser.email}'),
                      Text('User ID: ${currentUser.id}'),
                      const SizedBox(height: 8),
                      Text(
                        _statusMessage,
                        style: const TextStyle(
                          color: AppTheme.accentBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ] else ...[
                      const Text(
                        'Not logged in',
                        style: TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please log in first, then come back here.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (currentUser != null) ...[
              ElevatedButton(
                onPressed: _isLoading ? null : _createProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentBlue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Create Missing Profile',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _isLoading ? null : _checkStatus,
                child: const Text('Check Status Again'),
              ),
            ] else ...[
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentBlue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Back to Login'),
              ),
            ],
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'How to use:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1. Make sure you are logged in\n'
              '2. Click "Create Missing Profile"\n'
              '3. Your profile will be created in the database\n'
              '4. You can now use password reset',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
