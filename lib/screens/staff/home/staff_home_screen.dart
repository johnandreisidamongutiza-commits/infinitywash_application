import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class StaffHomeScreen extends StatelessWidget {
  const StaffHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 30),
              _buildTodayQueue(),
              const SizedBox(height: 30),
              _buildScanButton(),
              const SizedBox(height: 30),
              _buildTasksSection(),
              const SizedBox(height: 30),
              _buildSummarizationSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: AppTheme.softGray,
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(4),
          child: ClipOval(
            child: Image.asset(
              'assets/images/logo.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.person),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hi, Staff!',
              style: AppTheme.lightTheme.textTheme.headlineMedium,
            ),
            Text(
              'Let\'s keep things moving today. ✨',
              style: AppTheme.lightTheme.textTheme.bodyMedium,
            ),
          ],
        ),
        const Spacer(),
        _buildNotificationIcon(),
      ],
    );
  }

  Widget _buildNotificationIcon() {
    return Stack(
      children: [
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.notifications_none, size: 28),
        ),
        Positioned(
          right: 8,
          top: 8,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: AppTheme.errorRed,
              shape: BoxShape.circle,
            ),
            child: const Text(
              '3',
              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTodayQueue() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Today\'s Queue', style: AppTheme.lightTheme.textTheme.titleMedium),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildQueueCard('24', 'To Be\nPicked Up', Icons.shopping_bag_outlined, AppTheme.lightBlue, AppTheme.accentBlue),
              _buildQueueCard('18', 'In Progress', Icons.camera_alt_outlined, AppTheme.teamMemberOrange, AppTheme.teamMemberIconOrange),
              _buildQueueCard('7', 'Ready for\nPickup', Icons.shopping_basket_outlined, const Color(0xFFFCE4EC), AppTheme.errorRed),
              _buildQueueCard('5', 'Completed', Icons.check_circle_outline, const Color(0xFFE8F5E9), Colors.green),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQueueCard(String count, String label, IconData icon, Color bgColor, Color iconColor) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(height: 8),
        Text(count, style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontSize: 20)),
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildScanButton() {
    return ElevatedButton(
      onPressed: () {},
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code_scanner, size: 30),
          const SizedBox(width: 16),
          Text('Scan Order', style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(color: Colors.white, fontSize: 20)),
        ],
      ),
    );
  }

  Widget _buildTasksSection() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('My Tasks', style: AppTheme.lightTheme.textTheme.titleMedium),
            TextButton(onPressed: () {}, child: const Text('View All', style: TextStyle(color: AppTheme.accentBlue))),
          ],
        ),
        const SizedBox(height: 10),
        _buildTaskItem('Pick Up Orders', '12 orders', Icons.shopping_bag_outlined, AppTheme.lightBlue, AppTheme.accentBlue),
        const SizedBox(height: 12),
        _buildTaskItem('Process Orders', '8 orders', Icons.camera_alt_outlined, AppTheme.teamMemberOrange, AppTheme.teamMemberIconOrange),
        const SizedBox(height: 12),
        _buildTaskItem('Ready for Pickup', '5 orders', Icons.shopping_basket_outlined, const Color(0xFFFCE4EC), AppTheme.errorRed),
      ],
    );
  }

  Widget _buildTaskItem(String title, String subtitle, IconData icon, Color bgColor, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppStyles.cardDecoration,
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.lightTheme.textTheme.titleMedium),
                Text(subtitle, style: AppTheme.lightTheme.textTheme.bodyMedium),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.textLight),
        ],
      ),
    );
  }

  Widget _buildSummarizationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Daily Summary', style: AppTheme.lightTheme.textTheme.titleMedium),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildSummaryStat('Earnings', '₱2,450', Icons.payments_outlined, Colors.green)),
            const SizedBox(width: 16),
            Expanded(child: _buildSummaryStat('Low Stock', '2 items', Icons.inventory_2_outlined, AppTheme.errorRed)),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryStat(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(value, style: AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(fontSize: 22, color: color)),
          Text(title, style: AppTheme.lightTheme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
