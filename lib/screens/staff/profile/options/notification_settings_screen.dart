import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _newOrder = true;
  bool _lowStock = true;
  bool _paymentAlerts = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Notification Settings'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildSwitchTile('New Order Assigned', 'Receive alerts when a new laundry order is assigned.', _newOrder, (val) => setState(() => _newOrder = val)),
            const SizedBox(height: 12),
            _buildSwitchTile('Low Stock Alerts', 'Get notified when supplies are running low.', _lowStock, (val) => setState(() => _lowStock = val)),
            const SizedBox(height: 12),
            _buildSwitchTile('Payment Alerts', 'Receive notifications for successful payments.', _paymentAlerts, (val) => setState(() => _paymentAlerts = val)),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, Function(bool) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: AppStyles.cardDecoration,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontSize: 16)),
                Text(subtitle, style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppTheme.accentBlue,
          ),
        ],
      ),
    );
  }
}
