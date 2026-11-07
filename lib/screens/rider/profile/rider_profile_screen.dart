import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../services/profile_service.dart';
import '../../../services/push_notification_service.dart';
import '../../../widgets/editable_profile_avatar.dart';
import '../../../widgets/skeleton_loading.dart';
import '../../saved_accounts_screen.dart';
import 'options/account_details_screen.dart';
import 'options/change_password_screen.dart';

class RiderProfileScreen extends StatefulWidget {
  const RiderProfileScreen({super.key});

  @override
  State<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends State<RiderProfileScreen> {
  final _profileService = ProfileService();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  String? _avatarUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profileService.getProfile();
      final employee = await _profileService.getEmployee(profile['id']);
      _firstNameController.text = profile['first_name'] ?? '';
      _lastNameController.text = profile['last_name'] ?? '';
      _phoneController.text = profile['phone'] ?? employee['phone'] ?? '';
      _emailController.text = profile['email'] ?? employee['email'] ?? '';
      _nameController.text = employee['name'] ?? '';
      _avatarUrl = profile['avatar_url'] as String?;
    } catch (error) {
      _showMessage('Could not load profile: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
        body: _isLoading
          ? const ProfileScreenSkeleton(optionCount: 2)
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Center(
              child: EditableProfileAvatar(
                avatarUrl: _avatarUrl,
                name: _nameController.text.trim().isNotEmpty
                    ? _nameController.text.trim()
                    : '${_firstNameController.text} ${_lastNameController.text}'.trim(),
                role: 'Rider',
                radius: 60,
                onAvatarChanged: (newUrl) {
                  setState(() => _avatarUrl = newUrl);
                },
              ),
            ),
            const SizedBox(height: 24),
            Text(_nameController.text, style: AppTheme.lightTheme.textTheme.headlineMedium),
            Text(_emailController.text, style: AppTheme.lightTheme.textTheme.bodyMedium),
            const SizedBox(height: 40),
            _buildProfileOption(
              context,
              Icons.person_outline,
              'Account Details',
              const RiderAccountDetailsScreen(),
            ),
            _buildProfileOption(
              context,
              Icons.lock_outline,
              'Change Password',
              const RiderChangePasswordScreen(),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                // The saved account relies on this refresh token. Calling
                // Supabase signOut revokes it, so leave the local session
                // restorable and return to the account chooser.
                PushNotificationService.instance.unregisterCurrentUser();
                if (!context.mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const SavedAccountsScreen()),
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.errorRed,
                side: const BorderSide(color: AppTheme.errorRed),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout),
                  SizedBox(width: 8),
                  Text('Logout'),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileOption(BuildContext context, IconData icon, String label, Widget destination) {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => destination),
        );
        if (result == true) {
          _loadProfile();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: AppStyles.cardDecoration,
        child: Row(
          children: [
            Icon(icon, color: AppTheme.textDark),
            const SizedBox(width: 16),
            // Expanded: a long label (or a large system font) wraps instead of
            // overflowing the row.
            Expanded(
              child: Text(
                label,
                style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontSize: 16),
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.textLight),
          ],
        ),
      ),
    );
  }
}
