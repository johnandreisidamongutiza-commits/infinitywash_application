import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'staff/staff_main_screen.dart';
import 'customer/customer_main_screen.dart';
import 'rider/rider_main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  late AnimationController _animationController;

  // Staggered hardware-accelerated animations (compositor thread)
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _logoFadeAnimation;
  late Animation<Offset> _textSlideAnimation;
  late Animation<double> _textFadeAnimation;
  late Animation<double> _loadingFadeAnimation;

  String _statusMessage = 'Checking saved accounts...';

  @override
  void initState() {
    super.initState();

    // ── Relaxed, smooth 1500ms entrance animation ──
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // 1. Logo scales up gently (0ms - 950ms)
    _logoScaleAnimation = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutCubic),
      ),
    );

    // 2. Logo fades in gently (0ms - 750ms)
    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.50, curve: Curves.easeIn),
      ),
    );

    // 3. Text slides up smoothly (450ms - 1200ms)
    _textSlideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.18),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.30, 0.80, curve: Curves.easeOutCubic),
      ),
    );

    // 4. Text fades in (450ms - 1100ms)
    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.30, 0.75, curve: Curves.easeIn),
      ),
    );

    // 5. Loading indicator & status fades in gently (900ms - 1500ms)
    _loadingFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.60, 1.0, curve: Curves.easeIn),
      ),
    );

    _animationController.forward();

    // Start auto-login check
    _checkAutoLogin();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkAutoLogin() async {
    try {
      // Run auto-login in parallel with a comfortable 2200ms window.
      // This ensures:
      // 1. The 1500ms animation finishes completely with zero rush or jank
      // 2. The user has ample time to clearly read 'Checking saved accounts...'
      // 3. The screen feels calm, polished, and premium
      final results = await Future.wait([
        _authService.tryAutoLogin(),
        Future.delayed(const Duration(milliseconds: 2200)),
      ]);

      final authResponse = results[0];

      if (authResponse != null && authResponse.user != null) {
        if (mounted) {
          setState(() {
            _statusMessage = 'Logging in...';
          });
        }

        // Brief delay so user sees 'Logging in...' transition smoothly
        await Future.delayed(const Duration(milliseconds: 600));

        // Discover the user's role from the backend
        final role = await _authService.getUserRole();

        if (role == null) {
          await _authService.signOut();
          _navigateToLogin();
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
          _navigateToLogin();
          return;
        }

        if (mounted) {
          _navigateWithFade(maybeDestination);
          return;
        }
      }

      // No auto-login or failed, go to login
      _navigateToLogin();
    } catch (e) {
      debugPrint('Auto-login error: $e');
      _navigateToLogin();
    }
  }

  void _navigateToLogin() {
    if (mounted) {
      _navigateWithFade(const LoginScreen());
    }
  }

  // Smooth, fluid transition to the next screen with shared Hero animation
  void _navigateWithFade(Widget targetScreen) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fadeCurve = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.15, 1.0, curve: Curves.easeIn),
          );
          final slideCurve = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: fadeCurve,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.04),
                end: Offset.zero,
              ).animate(slideCurve),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 650),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Animated Logo with Shared Hero flight ──
                RepaintBoundary(
                  child: FadeTransition(
                    opacity: _logoFadeAnimation,
                    child: ScaleTransition(
                      scale: _logoScaleAnimation,
                      child: Hero(
                        tag: 'app_mascot_logo',
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            width: 140,
                            height: 140,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryBlue.withValues(alpha: 0.06),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.asset(
                                'assets/images/logo.jpg',
                                fit: BoxFit.contain,
                                // Restrict decoded bitmap memory to 280x280:
                                // Saves ~85% RAM on low-end phones while ensuring crisp high-DPI clarity
                                cacheWidth: 280,
                                cacheHeight: 280,
                                filterQuality: FilterQuality.medium,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(
                                  Icons.wash,
                                  size: 72,
                                  color: AppTheme.accentBlue,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── Animated App Title & Subtitle ──
                RepaintBoundary(
                  child: SlideTransition(
                    position: _textSlideAnimation,
                    child: FadeTransition(
                      opacity: _textFadeAnimation,
                      child: Column(
                        children: [
                          Text(
                            'Infinity Wash',
                            style: GoogleFonts.lexend(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryBlue,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Professional Laundry Service',
                            style: GoogleFonts.lexend(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: AppTheme.textLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 48),

                // ── Animated Loading & Status ──
                RepaintBoundary(
                  child: FadeTransition(
                    opacity: _loadingFadeAnimation,
                    child: Column(
                      children: [
                        const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.primaryBlue,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            _statusMessage,
                            key: ValueKey<String>(_statusMessage),
                            style: GoogleFonts.lexend(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textLight,
                            ),
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
    );
  }
}
