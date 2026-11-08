import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/secure_storage_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/customer_tutorial_overlay.dart';
import 'home/customer_home_screen.dart';
import 'orders/customer_orders_screen.dart';
import 'chats/customer_chats_screen.dart';
import 'profile/customer_profile_screen.dart';

class CustomerMainScreen extends StatefulWidget {
  final bool autoStartTutorial;

  const CustomerMainScreen({
    super.key,
    this.autoStartTutorial = false,
  });

  @override
  State<CustomerMainScreen> createState() => _CustomerMainScreenState();
}

class _CustomerMainScreenState extends State<CustomerMainScreen> {
  int _currentIndex = 0;
  bool _showTutorial = false;

  // GlobalKeys for walkthrough tutorial targets
  final GlobalKey _newRequestKey = GlobalKey();
  final GlobalKey _statusCardKey = GlobalKey();
  final GlobalKey _trackDeliveryKey = GlobalKey();
  final GlobalKey _helpButtonKey = GlobalKey();
  final GlobalKey _bottomBarKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _checkTutorialStatus();
  }

  Future<void> _checkTutorialStatus() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (widget.autoStartTutorial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startTutorial();
      });
      return;
    }

    final hasCompleted = await SecureStorageService.instance
        .hasCompletedCustomerTutorial(userId: userId);
    if (!hasCompleted && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startTutorial();
      });
    }
  }

  void _startTutorial() {
    setState(() {
      _currentIndex = 0; // Bring customer to Home screen
      _showTutorial = true;
    });
  }

  Future<void> _onFinishTutorial() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    await SecureStorageService.instance
        .setCustomerTutorialCompleted(userId: userId, completed: true);
    if (mounted) {
      setState(() => _showTutorial = false);
    }
  }

  Future<void> _onSkipTutorial() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    await SecureStorageService.instance
        .setCustomerTutorialCompleted(userId: userId, completed: true);
    if (mounted) {
      setState(() => _showTutorial = false);
    }
  }

  Future<void> _ensureVisible(GlobalKey key) async {
    final context = key.currentContext;
    if (context != null) {
      try {
        await Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 260),
          alignment: 0.35,
          curve: Curves.easeInOut,
        );
      } catch (_) {}
    }
  }

  List<TutorialStep> get _tutorialSteps => [
        TutorialStep(
          targetKey: _newRequestKey,
          title: '1. Start a New Order',
          description:
              'Tap "New Request" to order laundry service. Choose your collection method, upload photos of your clothes, select detergent options, and confirm your address.',
          borderRadius: BorderRadius.circular(20),
          padding: const EdgeInsets.all(4),
        ),
        TutorialStep(
          targetKey: _statusCardKey,
          title: '2. Live Order Tracking',
          description:
              'Track your order status right here in real time — from staff review and pickup, to washing, drying, folding, and delivery.',
          borderRadius: BorderRadius.circular(24),
          padding: const EdgeInsets.all(4),
        ),
        TutorialStep(
          targetKey: _trackDeliveryKey,
          title: '3. Real-Time Delivery Tracking',
          description:
              'Tap "Track Delivery" anytime to view your assigned rider\'s live GPS location and route on the interactive map.',
          borderRadius: BorderRadius.circular(20),
          padding: const EdgeInsets.all(4),
        ),
        TutorialStep(
          targetKey: _bottomBarKey,
          title: '4. Orders & Navigation',
          description:
              'Navigate between tabs at the bottom to check your order history, review past invoices, chat with support, or manage your profile.',
          borderRadius: BorderRadius.circular(16),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        ),
        TutorialStep(
          targetKey: _helpButtonKey,
          title: '5. Help Anytime',
          description:
              'You\'re all set! If you ever want to review this ordering tutorial again, simply tap this help button in the header.',
          borderRadius: BorderRadius.circular(14),
          padding: const EdgeInsets.all(4),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      CustomerHomeScreen(
        key: const ValueKey('customer_home'),
        isActive: _currentIndex == 0,
        newRequestKey: _newRequestKey,
        statusCardKey: _statusCardKey,
        trackDeliveryKey: _trackDeliveryKey,
        helpButtonKey: _helpButtonKey,
        onStartTutorial: _startTutorial,
      ),
      CustomerOrdersScreen(
        key: const ValueKey('customer_orders'),
        isActive: _currentIndex == 1,
      ),
      const CustomerChatsScreen(key: ValueKey('customer_chats')),
      CustomerProfileScreen(
        key: const ValueKey('customer_profile'),
        onStartTutorial: _startTutorial,
      ),
    ];

    final safeIndex = _currentIndex.clamp(0, screens.length - 1);

    return Stack(
      children: [
        Scaffold(
          body: IndexedStack(
            index: safeIndex,
            children: screens,
          ),
          bottomNavigationBar: Container(
            key: _bottomBarKey,
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                if (_showTutorial) return; // Prevent tab change during tutorial
                setState(() => _currentIndex = index);
              },
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.white,
              selectedItemColor: AppTheme.primaryBlue,
              unselectedItemColor: AppTheme.textLight.withValues(alpha: 0.5),
              selectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              unselectedLabelStyle: const TextStyle(fontSize: 11),
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.assignment_outlined),
                  activeIcon: Icon(Icons.assignment),
                  label: 'Orders',
                ),
                BottomNavigationBarItem(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.chat_bubble_outline),
                      Positioned(
                        top: -1,
                        right: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  activeIcon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.chat_bubble),
                      Positioned(
                        top: -1,
                        right: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  label: 'Chats',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  activeIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),

        // Interactive tutorial walkthrough overlay
        if (_showTutorial)
          CustomerTutorialOverlay(
            steps: _tutorialSteps,
            onBeforeStep: _ensureVisible,
            onFinish: _onFinishTutorial,
            onSkip: _onSkipTutorial,
          ),
      ],
    );
  }
}
