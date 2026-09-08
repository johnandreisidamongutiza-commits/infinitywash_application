import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../orders/orders_screen.dart';
import '../notifications/staff_notifications_screen.dart';

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
              _buildHeader(context),
              const SizedBox(height: 30),
              _buildTodayQueue(),
              const SizedBox(height: 30),
              _buildTasksSection(context),
              const SizedBox(height: 30),
              _buildSummarizationSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: AppTheme.softGray,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.textDark, width: 1.5),
          ),
          padding: const EdgeInsets.all(2),
          child: ClipOval(
            child: Image.asset(
              'assets/images/logo.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.person),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Hi, Staff!',
                style: AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Let\'s keep things moving today. ✨',
                style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const StaffNotificationsScreen()),
                );
              },
              icon: const Icon(Icons.notifications_none, size: 28),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.errorRed,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: const Text(
                  '3',
                  style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildQueueCard('24', 'To Be\nPicked Up', Icons.shopping_bag_outlined, AppTheme.lightBlue, AppTheme.accentBlue)),
              Expanded(child: _buildQueueCard('18', 'In Progress', Icons.camera_alt_outlined, AppTheme.teamMemberOrange, AppTheme.teamMemberIconOrange)),
              Expanded(child: _buildQueueCard('7', 'Ready for\nPickup', Icons.shopping_basket_outlined, const Color(0xFFFCE4EC), AppTheme.errorRed)),
              Expanded(child: _buildQueueCard('5', 'Completed', Icons.check_circle_outline, const Color(0xFFE8F5E9), Colors.green)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQueueCard(String count, String label, IconData icon, Color bgColor, Color iconColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          count,
          style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 30,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
              fontSize: 9,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildTasksSection(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('My Tasks', style: AppTheme.lightTheme.textTheme.titleMedium),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const OrdersScreen()),
                );
              },
              child: const Text('View All', style: TextStyle(color: AppTheme.accentBlue)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildTaskItem(
          context,
          'Pick Up Orders',
          '12 orders',
          Icons.shopping_bag_outlined,
          AppTheme.lightBlue,
          AppTheme.accentBlue,
        ),
        const SizedBox(height: 12),
        _buildTaskItem(
          context,
          'Process Orders',
          '8 orders',
          Icons.camera_alt_outlined,
          AppTheme.teamMemberOrange,
          AppTheme.teamMemberIconOrange,
        ),
        const SizedBox(height: 12),
        _buildTaskItem(
          context,
          'Ready for Pickup',
          '5 orders',
          Icons.shopping_basket_outlined,
          const Color(0xFFFCE4EC),
          AppTheme.errorRed,
        ),
      ],
    );
  }

  Widget _buildTaskItem(BuildContext context, String title, String subtitle, IconData icon, Color bgColor, Color iconColor) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const OrdersScreen()),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: AppStyles.cardDecoration.copyWith(color: Colors.transparent),
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
        ),
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
