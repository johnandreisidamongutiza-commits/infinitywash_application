import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

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
            _buildDriverInfo(),
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
          Icon(Icons.map_outlined, size: 100, color: AppTheme.textLight.withOpacity(0.1)),
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
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)]),
              child: const Text('Rider is 5 mins away', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: AppTheme.lightBlue, shape: BoxShape.circle),
            child: const Icon(Icons.person, color: AppTheme.accentBlue, size: 30),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rider: Michael Rider', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                Text('Vehicle: Honda Click (ABC-1234)', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
            child: const Icon(Icons.phone, color: Colors.white, size: 20),
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
