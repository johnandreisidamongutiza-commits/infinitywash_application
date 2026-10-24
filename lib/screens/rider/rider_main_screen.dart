import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'home/rider_home_screen.dart';
import 'route/rider_route_screen_new.dart';
import 'payments/rider_payment_screen.dart';
import 'chats/rider_chats_screen.dart';
import 'profile/rider_profile_screen.dart';

class RiderMainScreen extends StatefulWidget {
  final int initialIndex;

  const RiderMainScreen({super.key, this.initialIndex = 0});

  @override
  State<RiderMainScreen> createState() => _RiderMainScreenState();
}

class _RiderMainScreenState extends State<RiderMainScreen> {
  late int _currentIndex;
  final GlobalKey<RiderPaymentScreenState> _paymentScreenKey = GlobalKey<RiderPaymentScreenState>();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          RiderHomeScreen(
            onSelectTab: (index) {
              setState(() => _currentIndex = index);
              if (index == 2) {
                _paymentScreenKey.currentState?.refreshOrders();
              }
            },
          ),
          RiderRouteScreenNew(
            onBackToHome: () => setState(() => _currentIndex = 0),
            isActive: _currentIndex == 1,
          ),
          RiderPaymentScreen(
            key: _paymentScreenKey,
            isActive: _currentIndex == 2,
          ),
          const RiderChatsScreen(),
          const RiderProfileScreen(),
        ],
      ),
      bottomNavigationBar: Container(
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
            final prevIndex = _currentIndex;
            setState(() {
              _currentIndex = index;
            });
            if (index == 2 && prevIndex != 2) {
              _paymentScreenKey.currentState?.refreshOrders();
            }
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: AppTheme.accentBlue,
          unselectedItemColor: AppTheme.textLight.withValues(alpha: 0.5),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.route_outlined),
              activeIcon: Icon(Icons.route),
              label: 'Route',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.payments_outlined),
              activeIcon: Icon(Icons.payments),
              label: 'Payment',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              activeIcon: Icon(Icons.chat_bubble),
              label: 'Chats',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
