import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'home/rider_home_screen.dart';
import 'orders/rider_orders_screen.dart';
import 'route/rider_route_screen.dart';
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
  int _previousIndex = 0;
  
  // Key to access RiderOrdersScreen state
  final GlobalKey<RiderOrdersScreenState> _ordersScreenKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _previousIndex = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const RiderHomeScreen(),
          RiderRouteScreen(
            onBackToHome: () => setState(() => _currentIndex = 0),
          ),
          RiderOrdersScreen(key: _ordersScreenKey),
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
            setState(() {
              _previousIndex = _currentIndex;
              _currentIndex = index;
            });
            
            // If navigating TO Orders screen (index 2) FROM another screen
            if (index == 2 && _previousIndex != 2) {
              print('🔵 RIDER MAIN: Switched to Orders tab (from tab $_previousIndex)');
              print('🔵 RIDER MAIN: RiderOrdersScreen key is mounted: ${_ordersScreenKey.currentState?.mounted}');
              if (_ordersScreenKey.currentState != null) {
                print('🔵 RIDER MAIN: RiderOrdersScreen state exists, calling refreshOrders()');
                _ordersScreenKey.currentState!.refreshOrders();
              } else {
                print('❌ RIDER MAIN: RiderOrdersScreen state is NULL! Cannot refresh.');
              }
            } else {
              print('🔵 RIDER MAIN: Switched to tab $index (from $_previousIndex), no action needed');
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
              icon: Icon(Icons.shopping_bag_outlined),
              activeIcon: Icon(Icons.shopping_bag),
              label: 'Orders',
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
