import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../services/profile_service.dart';
import '../../../services/push_notification_service.dart';
import '../../../widgets/editable_profile_avatar.dart';
import '../../../widgets/skeleton_loading.dart';
import '../../saved_accounts_screen.dart';
import 'options/account_details_screen.dart';
import 'options/change_password_screen.dart';
import 'options/loyalty_card_screen.dart';
import 'options/terms_and_privacy_screen.dart';

class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({super.key});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  final _profileService = ProfileService();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
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
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profileService.getProfile();
      _firstNameController.text = profile['first_name'] ?? '';
      _lastNameController.text = profile['last_name'] ?? '';
      _phoneController.text = profile['phone'] ?? '';
      _emailController.text = profile['email'] ?? '';
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
          ? const ProfileScreenSkeleton(optionCount: 4)
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Center(
              child: EditableProfileAvatar(
                avatarUrl: _avatarUrl,
                name: '${_firstNameController.text} ${_lastNameController.text}'.trim(),
                role: 'Customer',
                radius: 60,
                onAvatarChanged: (newUrl) {
                  setState(() => _avatarUrl = newUrl);
                },
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '${_firstNameController.text} ${_lastNameController.text}'.trim().isEmpty 
                ? 'Customer' 
                : '${_firstNameController.text} ${_lastNameController.text}'.trim(),
              style: AppTheme.lightTheme.textTheme.headlineMedium,
            ),
            Text(_emailController.text, style: AppTheme.lightTheme.textTheme.bodyMedium),
            const SizedBox(height: 40),
            _buildProfileOption(
              context,
              Icons.person_outline,
              'Account Details',
              const CustomerAccountDetailsScreen(),
            ),
            _buildProfileOption(
              context,
              Icons.card_membership_outlined,
              'Loyalty Card',
              const CustomerLoyaltyCardScreen(),
            ),
            _buildProfileOption(
              context,
              Icons.lock_outline,
              'Change Password',
              const CustomerChangePasswordScreen(),
            ),
            _buildProfileOption(
              context,
              Icons.gavel_outlined,
              'Terms & Privacy',
              const CustomerTermsAndPrivacyScreen(),
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
