import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../orders/customer_orders_screen.dart';
import '../delivery/delivery_tracking_screen.dart';

class CustomerNotificationsScreen extends StatefulWidget {
  final VoidCallback? onNotificationsCleared;

  const CustomerNotificationsScreen({super.key, this.onNotificationsCleared});

  @override
  State<CustomerNotificationsScreen> createState() => _CustomerNotificationsScreenState();
}

class _CustomerNotificationsScreenState extends State<CustomerNotificationsScreen> {
  final List<Map<String, dynamic>> _notifications = [
    {
      'id': '1',
      'title': 'Order In Processing',
      'desc': 'Your laundry for Order #IW-105 is currently being washed and dried.',
      'time': '30 mins ago',
      'type': 'order',
      'isRead': false,
    },
    {
      'id': '2',
      'title': 'Rider Assigned',
      'desc': 'Michael Rider (Honda Click - ABC-1234) has been assigned for your doorstep delivery.',
      'time': '1 hour ago',
      'type': 'delivery',
      'isRead': false,
    },
    {
      'id': '3',
      'title': 'Payment Verified',
      'desc': 'Payment of ₱170.00 via GCash was successfully confirmed for Order #IW-105.',
      'time': '2 hours ago',
      'type': 'payment',
      'isRead': true,
    },
    {
      'id': '4',
      'title': 'Order Delivered',
      'desc': 'Order #IW-102 was delivered to your address. Thank you for washing with InfinityWash!',
      'time': 'Aug 28, 2026',
      'type': 'completed',
      'isRead': true,
    },
  ];

  int get _unreadCount => _notifications.where((n) => !n['isRead']).length;

  void _markAllAsRead() {
    setState(() {
      for (var n in _notifications) {
        n['isRead'] = true;
      }
    });
    widget.onNotificationsCleared?.call();
  }

  void _onNotificationTap(Map<String, dynamic> notif) {
    setState(() {
      notif['isRead'] = true;
    });
    widget.onNotificationsCleared?.call();

    final type = notif['type'];
    if (type == 'delivery') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const DeliveryTrackingScreen()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const CustomerOrdersScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text(
                'Mark all read',
                style: TextStyle(
                  color: AppTheme.accentBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
      body: _notifications.isEmpty
          ? _buildEmptyState()
          : ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: _notifications.length,
              separatorBuilder: (context, index) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final notif = _notifications[index];
                return _buildNotificationCard(notif);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 80, color: AppTheme.textLight.withOpacity(0.2)),
            const SizedBox(height: 16),
            const Text(
              'No notifications yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
            ),
            const SizedBox(height: 8),
            const Text(
              'You\'ll receive live updates here when your laundry order progresses.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textLight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notif) {
    final bool isRead = notif['isRead'];
    Color iconColor;
    Color iconBgColor;
    IconData icon;

    switch (notif['type']) {
      case 'delivery':
        iconColor = AppTheme.teamMemberIconOrange;
        iconBgColor = AppTheme.teamMemberOrange;
        icon = Icons.delivery_dining;
        break;
      case 'payment':
        iconColor = Colors.green;
        iconBgColor = Colors.green.withOpacity(0.12);
        icon = Icons.payments_outlined;
        break;
      case 'completed':
        iconColor = Colors.green;
        iconBgColor = Colors.green.withOpacity(0.12);
        icon = Icons.check_circle_outline;
        break;
      default:
        iconColor = AppTheme.accentBlue;
        iconBgColor = AppTheme.lightBlue;
        icon = Icons.local_laundry_service;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onNotificationTap(notif),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isRead ? Colors.white : AppTheme.accentBlue.withOpacity(0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isRead ? AppTheme.borderGray.withOpacity(0.6) : AppTheme.accentBlue.withOpacity(0.3),
              width: isRead ? 1 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            notif['title'],
                            style: TextStyle(
                              fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                              fontSize: 15,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.accentBlue,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notif['desc'],
                      style: TextStyle(
                        fontSize: 12,
                        color: isRead ? AppTheme.textLight : AppTheme.textDark.withOpacity(0.8),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      notif['time'],
                      style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
