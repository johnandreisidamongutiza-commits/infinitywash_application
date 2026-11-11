import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/firebase_chat_service.dart';
import '../../services/sound_service.dart';
import '../../services/data_change_monitor.dart';
import '../../widgets/top_notification.dart';
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
  final GlobalKey<OrdersScreenState> _ordersKey = GlobalKey<OrdersScreenState>();
  StreamSubscription<Map<String, dynamic>>? _requestSubscription;

  @override
  void initState() {
    super.initState();
    DataChangeMonitor.instance.start();
    _requestSubscription = DataChangeMonitor.instance.onNewServiceRequest.listen(
      _onIncomingServiceRequest,
    );
  }

  @override
  void dispose() {
    _requestSubscription?.cancel();
    super.dispose();
  }

  void _onIncomingServiceRequest(Map<String, dynamic> data) {
    if (!mounted) return;

    final orderNumber = (data['order_number'] ?? data['orderNumber'] ?? 'New Request').toString();
    final customerName = (data['customer_name'] ?? data['customerName'])?.toString();

    SoundService.instance.playNotificationSound();

    showNewRequestNotification(
      context,
      orderNumber: orderNumber,
      customerName: customerName,
      onReview: () {
        setState(() {
          _currentIndex = 1;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ordersKey.currentState?.switchToTab(0);
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: FirebaseChatService.instance.streamTotalUnreadCount(
        currentUserId: '',
        currentRole: 'staff',
      ),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;
        return _buildScaffold(unreadCount);
      },
    );
  }

  Widget _buildScaffold(int unreadCount) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          StaffHomeScreen(isActive: _currentIndex == 0),
          OrdersScreen(key: _ordersKey, isActive: _currentIndex == 1),
          const StaffChatsScreen(),
          PaymentScreen(isActive: _currentIndex == 3),
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
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: AppTheme.primaryBlue,
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
                          color: AppTheme.primaryBlue,
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
                          color: AppTheme.primaryBlue,
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
