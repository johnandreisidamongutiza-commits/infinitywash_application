import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/top_notification.dart';
import '../chats/customer_chat_detail_screen.dart';

class DeliveryTrackingScreen extends StatelessWidget {
  const DeliveryTrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Track Delivery'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildMapMock(),
            const SizedBox(height: 30),
            _buildDriverInfo(context),
            const SizedBox(height: 30),
            _buildDeliveryStatus(),
          ],
        ),
      ),
    );
  }

  Widget _buildMapMock() {
    return Container(
      height: 250,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.softGray,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.map_outlined, size: 100, color: AppTheme.textLight.withValues(alpha: 0.1)),
          Positioned(
            top: 50,
            right: 80,
            child: Icon(Icons.moped, color: AppTheme.errorRed, size: 40),
          ),
          Positioned(
            bottom: 40,
            left: 60,
            child: Icon(Icons.location_on, color: AppTheme.accentBlue, size: 40),
          ),
          Positioned(
            top: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)]),
              child: const Text('Rider is 5 mins away', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverInfo(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: AppTheme.lightBlue, shape: BoxShape.circle),
            child: const Icon(Icons.delivery_dining, color: AppTheme.accentBlue, size: 28),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Michael Rider', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                SizedBox(height: 2),
                Text('Honda Click (ABC-1234)', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
              ],
            ),
          ),
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CustomerChatDetailScreen(
                    recipientName: 'Michael Rider',
                    recipientRole: 'Assigned Delivery Rider',
                    recipientType: ChatRecipientType.rider,
                    orderId: 'IW-105',
                    phoneNumber: '+63 912 345 6789',
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.accentBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.chat_bubble_outline, color: AppTheme.accentBlue, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () {
              showTopNotification(
                context,
                message: 'Calling rider Michael (+63 912 345 6789)...',
                icon: Icons.phone,
                backgroundColor: AppTheme.accentBlue,
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.phone, color: Colors.green, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryStatus() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Delivery Progress', style: AppTheme.lightTheme.textTheme.titleMedium),
          const SizedBox(height: 20),
          _buildStatusLine('Order Picked Up', '10:30 AM', true),
          _buildStatusLine('Out for Delivery', '11:15 AM', true),
          _buildStatusLine('Arrived', 'Waiting...', false),
        ],
      ),
    );
  }

  Widget _buildStatusLine(String title, String time, bool isDone) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(isDone ? Icons.check_circle : Icons.radio_button_unchecked, color: isDone ? Colors.green : AppTheme.textLight),
          const SizedBox(width: 16),
          Text(title, style: TextStyle(color: isDone ? AppTheme.textDark : AppTheme.textLight, fontWeight: isDone ? FontWeight.bold : FontWeight.normal)),
          const Spacer(),
          Text(time, style: const TextStyle(fontSize: 12, color: AppTheme.textLight)),
        ],
      ),
    );
  }
}
