import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../route/rider_route_screen.dart';

class RiderOrderDetailsScreen extends StatelessWidget {
  final int orderIndex;
  final bool isPickup;

  const RiderOrderDetailsScreen({
    super.key,
    required this.orderIndex,
    required this.isPickup,
  });

  @override
  Widget build(BuildContext context) {
    // Mock data - in production, this would come from a database/API
    String orderNumber = 'IW-${105 + orderIndex}';
    String customerName = isPickup ? 'New Customer ${orderIndex + 1}' : 'Existing Customer ${orderIndex + 1}';
    String address = '123 Mango Ave, Cebu City';
    String phoneNumber = '+63 912 345 6789';
    String rfidTag = 'IW-RF-${10234 + orderIndex}';
    String serviceType = 'Wash & Fold';
    String weight = '${5 + orderIndex} kg';
    String instructions = 'No fabric softener please.';
    String total = '₱${350 + (orderIndex * 50)}.00';
    String date = 'Sept ${4 + orderIndex}, 2026';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Order Details'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card - Order Number and Type
            _buildHeaderCard(orderNumber, date),
            const SizedBox(height: 24),

            // Customer Information Section
            Text('Customer Information', style: AppTheme.lightTheme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildCustomerInfoCard(customerName, address, phoneNumber, rfidTag),
            const SizedBox(height: 24),

            // Order Details Section
            Text('Order Details', style: AppTheme.lightTheme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildOrderDetailsCard(serviceType, weight, instructions, total),
            const SizedBox(height: 24),

            // Order Status Section
            Text('Order Status', style: AppTheme.lightTheme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildOrderStatusCard(),
            const SizedBox(height: 32),

            // Action Buttons
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RiderRouteScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.navigation),
                  SizedBox(width: 8),
                  Text('Navigate to Location'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                // Show contact options (call or message)
                _showContactOptions(context, phoneNumber, customerName, orderNumber);
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.phone),
                  SizedBox(width: 8),
                  Text('Contact Customer'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(String orderNumber, String date) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Order $orderNumber',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppTheme.accentBlue,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                date,
                style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isPickup ? AppTheme.errorRed.withValues(alpha: 0.1) : AppTheme.teamMemberIconOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isPickup ? 'PICKUP' : 'DELIVERY',
              style: TextStyle(
                color: isPickup ? AppTheme.errorRed : AppTheme.teamMemberIconOrange,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerInfoCard(String name, String address, String phone, String rfid) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        children: [
          _buildInfoRow(Icons.person_outline, name),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.location_on_outlined, address),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.phone_outlined, phone),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.style_outlined, 'RFID: $rfid'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppTheme.accentBlue),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, color: AppTheme.textDark),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderDetailsCard(String serviceType, String weight, String instructions, String total) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        children: [
          _buildDetailRow('Service Type', serviceType),
          const Divider(height: 24),
          _buildDetailRow('Weight', weight),
          const Divider(height: 24),
          _buildDetailRow('Instructions', instructions),
          const Divider(height: 24),
          _buildDetailRow('Estimated Total', total, isTotal: true),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textLight,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textDark,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        children: [
          _buildStatusStep(
            isPickup ? 'Pending Pickup' : 'Pending Delivery',
            Icons.pending,
            true,
            isLast: false,
          ),
          _buildConnector(true),
          _buildStatusStep(
            'In Transit',
            Icons.local_shipping_outlined,
            false,
            isLast: false,
          ),
          _buildConnector(false),
          _buildStatusStep(
            isPickup ? 'Picked Up' : 'Delivered',
            Icons.check_circle_outline,
            false,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusStep(String label, IconData icon, bool isActive, {required bool isLast}) {
    Color color = isActive ? AppTheme.accentBlue : AppTheme.textLight.withValues(alpha: 0.3);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? AppTheme.textDark : AppTheme.textLight,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
        if (isActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.accentBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Current',
              style: TextStyle(
                color: AppTheme.accentBlue,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildConnector(bool isActive) {
    return Container(
      margin: const EdgeInsets.only(left: 19, top: 4, bottom: 4),
      height: 24,
      width: 2,
      color: isActive ? AppTheme.accentBlue : AppTheme.borderGray,
    );
  }

  void _showContactOptions(BuildContext context, String phoneNumber, String customerName, String orderNumber) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.borderGray,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Contact Customer',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.phone, color: AppTheme.accentBlue),
              title: const Text('Call Customer'),
              subtitle: Text(phoneNumber),
              onTap: () {
                Navigator.pop(context);
                // In production, implement actual phone call
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Calling $phoneNumber...')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.message, color: AppTheme.accentBlue),
              title: const Text('Send Message'),
              subtitle: const Text('Send SMS or in-app message'),
              onTap: () {
                Navigator.pop(context);
                // In production, implement messaging
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Opening messenger...')),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
