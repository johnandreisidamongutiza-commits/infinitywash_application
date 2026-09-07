import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Help & Support'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Contact Administrator', style: AppTheme.lightTheme.textTheme.titleMedium),
            const SizedBox(height: 16),
            _buildSupportTile(Icons.email_outlined, 'admin@infinitywash.com', 'Send us an email'),
            const SizedBox(height: 12),
            _buildSupportTile(Icons.phone_outlined, '+63 912 345 6789', 'Call for urgent assistance'),
            const SizedBox(height: 30),
            Text('Frequently Asked Questions', style: AppTheme.lightTheme.textTheme.titleMedium),
            const SizedBox(height: 16),
            _buildFaqTile('How do I process a bulk order?'),
            _buildFaqTile('What to do if G-Cash payment fails?'),
            _buildFaqTile('How to update supply inventory?'),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportTile(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accentBlue),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(subtitle, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFaqTile(String question) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Row(
        children: [
          Expanded(child: Text(question, style: const TextStyle(fontSize: 14))),
          const Icon(Icons.keyboard_arrow_down, color: AppTheme.textLight),
        ],
      ),
    );
  }
}
