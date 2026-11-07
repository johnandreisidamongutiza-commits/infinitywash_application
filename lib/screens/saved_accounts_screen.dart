import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/saved_account.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/role_entry_transition.dart';
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

class _SavedAccountsScreenState extends State<SavedAccountsScreen> with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  List<SavedAccount> _accounts = [];
  bool _loading = true;
  String? _openingAccountId;

  late final AnimationController _animController;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _contentFade;
  late final Animation<Offset> _contentSlide;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.55, curve: Curves.fastOutSlowIn),
      ),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.55, curve: Curves.fastOutSlowIn),
      ),
    );

    _contentFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.20, 0.85, curve: Curves.fastOutSlowIn),
      ),
    );
    _contentSlide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.20, 0.85, curve: Curves.fastOutSlowIn),
      ),
    );

    _animController.forward();
    _loadAccounts();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
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
      // Do not call Supabase signOut while switching saved accounts. Supabase
      // revokes the active refresh token on sign-out, which would invalidate
      // that account's encrypted saved session. tryAutoLogin installs the
      // selected account's session directly.
      final response = await _authService.tryAutoLogin(userId: account.id);
      final user = response?.user;
      if (user == null) {
        await _loadAccounts();
        if (mounted) {
          _message(
            'That saved session expired. Add the account again to sign in.',
          );
        }
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
        _message(
          'We could not verify this saved account. Please sign in again.',
        );
      }
    } catch (_) {
      if (mounted) _message('Could not open this account. Please try again.');
    } finally {
      if (mounted) setState(() => _openingAccountId = null);
    }
  }

  Future<void> _addAccount() async {
    // Navigating to LoginScreen with isAddingAccount: true preserves context
    // and returns to refresh saved accounts upon finish.
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen(isAddingAccount: true)),
    ).then((_) => _loadAccounts());
  }

  Future<void> _removeAccount(SavedAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove saved account?'),
        content: Text(
          '${account.displayName} will need to sign in again on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textLight)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove', style: TextStyle(color: AppTheme.errorRed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _authService.removeSavedAccount(account.id);
    await _loadAccounts();
    if (_accounts.isEmpty && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  void _replaceWith(Widget screen) {
    Navigator.pushAndRemoveUntil(
      context,
      RoleEntryTransition.route(screen),
      (_) => false,
    );
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.softGray,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.primaryBlue),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
                ),
              )
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Centered Brand Logo (Hero target from Splash, straight flight, razor sharp)
                        Center(
                          child: Hero(
                            tag: 'app_brand_logo',
                            createRectTween: (begin, end) => RectTween(begin: begin, end: end),
                            child: RepaintBoundary(
                              child: Material(
                                color: Colors.transparent,
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  padding: const EdgeInsets.all(9),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.primaryBlue.withValues(alpha: 0.06),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Image.asset(
                                      'assets/images/logo.png',
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.high,
                                      errorBuilder: (context, error, stackTrace) => const Icon(
                                        Icons.local_laundry_service,
                                        size: 48,
                                        color: AppTheme.primaryBlue,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Animated Heading
                        SlideTransition(
                          position: _titleSlide,
                          child: FadeTransition(
                            opacity: _titleFade,
                            child: Column(
                              children: [
                                Text(
                                  'Welcome Back',
                                  textAlign: TextAlign.center,
                                  style: AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryBlue,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _accounts.isEmpty
                                      ? 'Sign in or add an account to continue'
                                      : 'Choose an account to continue',
                                  textAlign: TextAlign.center,
                                  style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.textLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Animated Content (Accounts List & Add Account Button)
                        SlideTransition(
                          position: _contentSlide,
                          child: FadeTransition(
                            opacity: _contentFade,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final account in _accounts)
                                  RepaintBoundary(
                                    key: ValueKey(account.id),
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.primaryBlue.withValues(alpha: 0.04),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.circular(20),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(20),
                                          onTap: _openingAccountId == null
                                              ? () => _openAccount(account)
                                              : null,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                            child: Row(
                                              children: [
                                                // Initials Avatar (Lightweight vector rendering for low-end GPUs)
                                                Container(
                                                  width: 44,
                                                  height: 44,
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.primaryBlue,
                                                    borderRadius: BorderRadius.circular(14),
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    account.initials,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 14),

                                                // Name & Email
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        account.displayName,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          color: AppTheme.primaryBlue,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        account.email,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          color: AppTheme.textLight,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),

                                                // Loading Indicator or Remove Button
                                                if (_openingAccountId == account.id)
                                                  const SizedBox(
                                                    width: 22,
                                                    height: 22,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
                                                    ),
                                                  )
                                                else
                                                  IconButton(
                                                    icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                                                    tooltip: 'Remove saved account',
                                                    onPressed: _openingAccountId == null
                                                        ? () => _removeAccount(account)
                                                        : null,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                const SizedBox(height: 4),

                                // Add Another Account Button
                                OutlinedButton.icon(
                                  onPressed: _openingAccountId == null ? _addAccount : null,
                                  icon: const Icon(Icons.person_add_alt_1, size: 20),
                                  label: Text(
                                    'Add Another Account',
                                    style: GoogleFonts.lexend(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(50),
                                    backgroundColor: Colors.white,
                                    foregroundColor: AppTheme.primaryBlue,
                                    side: BorderSide(
                                      color: AppTheme.primaryBlue.withValues(alpha: 0.18),
                                      width: 1.2,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
