import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class StaffNotificationsScreen extends StatelessWidget {
  const StaffNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: 5,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) => _buildNotificationCard(index),
      ),
    );
  }

  Widget _buildNotificationCard(int index) {
    final List<Map<String, String>> notifications = [
      {'title': 'Low Stock Alert', 'desc': 'Liquid Detergent is below 20%. Please restock soon.', 'time': '10 mins ago', 'type': 'alert'},
      {'title': 'New Pickup Request', 'desc': 'A new order IW-105 needs to be picked up from Cebu IT Park.', 'time': '30 mins ago', 'type': 'order'},
      {'title': 'Payment Received', 'desc': 'Payment for Order IW-102 (₱300) was successful via G-Cash.', 'time': '1 hour ago', 'type': 'payment'},
      {'title': 'Order Ready', 'desc': 'Order IW-101 has been moved to the Ready rack.', 'time': '2 hours ago', 'type': 'order'},
      {'title': 'System Update', 'desc': 'Infinity Wash v1.2 is now live with improved tracking.', 'time': 'Yesterday', 'type': 'info'},
    ];

    final notification = notifications[index % notifications.length];
    Color iconColor;
    IconData icon;

    switch (notification['type']) {
      case 'alert': iconColor = AppTheme.errorRed; icon = Icons.warning_amber_rounded; break;
      case 'order': iconColor = AppTheme.accentBlue; icon = Icons.shopping_bag_outlined; break;
      case 'payment': iconColor = Colors.green; icon = Icons.payments_outlined; break;
      default: iconColor = AppTheme.textLight; icon = Icons.info_outline;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notification['title']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(notification['desc']!, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                Text(notification['time']!, style: const TextStyle(color: AppTheme.textLight, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
