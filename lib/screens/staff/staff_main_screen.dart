import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/chat_service.dart';
import 'home/staff_home_screen.dart';
import 'orders/orders_screen.dart';
import 'chats/staff_chats_screen.dart';
import 'payment/payment_screen.dart';
import 'profile/staff_profile_screen.dart';

class StaffMainScreen extends StatefulWidget {
  const StaffMainScreen({super.key});

  @override
  State<StaffMainScreen> createState() => _StaffMainScreenState();
}

class _StaffMainScreenState extends State<StaffMainScreen> {
  int _currentIndex = 0;
  int _previousIndex = 0;
  final ChatService _chatService = ChatService();
  
  // Key to access OrdersScreen state
  final GlobalKey<OrdersScreenState> _ordersScreenKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final unreadCount = _chatService.getTotalUnreadCount();

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const StaffHomeScreen(),
          OrdersScreen(key: _ordersScreenKey),
          const StaffChatsScreen(),
          const PaymentScreen(),
          const StaffProfileScreen(),
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
            
            // If navigating TO Orders screen (index 1) FROM another screen
            if (index == 1 && _previousIndex != 1) {
              print('🔵 STAFF MAIN: Switched to Orders tab (from tab $_previousIndex)');
              print('🔵 STAFF MAIN: OrdersScreen key is mounted: ${_ordersScreenKey.currentState?.mounted}');
              if (_ordersScreenKey.currentState != null) {
                print('🔵 STAFF MAIN: OrdersScreen state exists, calling refreshCurrentTab()');
                _ordersScreenKey.currentState!.refreshCurrentTab();
              } else {
                print('❌ STAFF MAIN: OrdersScreen state is NULL! Cannot refresh.');
              }
            } else {
              print('🔵 STAFF MAIN: Switched to tab $index (from $_previousIndex), no action needed');
            }
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: AppTheme.accentBlue,
          unselectedItemColor: AppTheme.textLight.withValues(alpha: 0.5),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
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
                  if (unreadCount > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              activeIcon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.chat_bubble),
                  if (unreadCount > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              label: 'Chats',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.payments_outlined),
              activeIcon: Icon(Icons.payments),
              label: 'Payment',
            ),
            const BottomNavigationBarItem(
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
