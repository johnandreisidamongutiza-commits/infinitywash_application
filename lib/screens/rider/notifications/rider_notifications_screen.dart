import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class RiderNotificationsScreen extends StatelessWidget {
  const RiderNotificationsScreen({super.key});

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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppTheme.lightBlue, shape: BoxShape.circle),
            child: const Icon(Icons.notifications_active_outlined, color: AppTheme.accentBlue, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('New Task Assigned', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('You have a new pickup request from Cebu IT Park.', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                Text('2 hours ago', style: TextStyle(color: AppTheme.textLight, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
