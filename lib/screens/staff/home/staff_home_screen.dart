import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import '../orders/orders_screen.dart';
import '../orders/create_order_flow.dart';
import '../orders/order_status_screen.dart';
import '../notifications/staff_notifications_screen.dart';
import '../../../services/mock_data_service.dart';

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
              _buildServiceRequestsButton(context),
              const SizedBox(height: 20),
              _buildTodayQueue(),
              const SizedBox(height: 30),
              _buildQuickActions(context),
              const SizedBox(height: 30),
              _buildCurrentlyProcessing(context),
              const SizedBox(height: 30),
              _buildSummarizationSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final pendingCount = MockDataService().pendingRequests.length;
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
            if (pendingCount > 0)
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
                  child: Text(
                    '$pendingCount',
                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildServiceRequestsButton(BuildContext context) {
    final pendingCount = MockDataService().pendingRequests.length;
    if (pendingCount == 0) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const OrdersScreen(initialTab: 0)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.accentBlue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.accentBlue.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.online_prediction, color: AppTheme.accentBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'You have $pendingCount new service requests!',
                style: const TextStyle(color: AppTheme.accentBlue, fontWeight: FontWeight.bold),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.accentBlue),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayQueue() {
    final service = MockDataService();
    final requestCount = service.pendingRequests.length;
    final processingCount = service.processingOrders.length;
    final readyCount = service.readyOrders.length;
    final completedCount = service.completedOrders.length;

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
              Expanded(child: _buildQueueCard(requestCount.toString(), 'Requests', Icons.online_prediction, AppTheme.lightBlue, AppTheme.accentBlue)),
              Expanded(child: _buildQueueCard(processingCount.toString(), 'Processing', Icons.sync, AppTheme.teamMemberOrange, AppTheme.teamMemberIconOrange)),
              Expanded(child: _buildQueueCard(readyCount.toString(), 'Ready', Icons.check_circle_outline, const Color(0xFFE8F5E9), Colors.green)),
              Expanded(child: _buildQueueCard(completedCount.toString(), 'Completed', Icons.verified_outlined, const Color(0xFFE3F2FD), const Color(0xFF1565C0))),
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

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: AppTheme.lightTheme.textTheme.titleMedium),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildQuickActionCard(
                context,
                'New Walk-in\nOrder',
                Icons.add_shopping_cart_outlined,
                AppTheme.accentBlue,
                AppTheme.lightBlue,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CreateOrderFlow()),
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildQuickActionCard(
                context,
                'View All\nOrders',
                Icons.assignment_outlined,
                AppTheme.teamMemberIconOrange,
                AppTheme.teamMemberOrange,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const OrdersScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionCard(BuildContext context, String label, IconData icon, Color iconColor, Color bgColor, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: AppStyles.cardDecoration,
          child: Column(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDark,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentlyProcessing(BuildContext context) {
    final processingOrders = MockDataService().processingOrders;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Currently Processing', style: AppTheme.lightTheme.textTheme.titleMedium),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const OrdersScreen()),
                );
              },
              child: const Text('See All', style: TextStyle(color: AppTheme.accentBlue)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (processingOrders.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
            decoration: AppStyles.cardDecoration,
            child: Column(
              children: [
                Icon(Icons.local_laundry_service_outlined, size: 48, color: AppTheme.textLight.withOpacity(0.3)),
                const SizedBox(height: 12),
                Text(
                  'No laundry in the machines right now 🧺',
                  textAlign: TextAlign.center,
                  style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textLight.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          )
        else
          ...processingOrders.map((order) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildProcessingCard(context, order),
          )),
      ],
    );
  }

  Widget _buildProcessingCard(BuildContext context, LaundryOrder order) {
    final elapsed = DateTime.now().difference(order.createdAt);
    String elapsedText;
    if (elapsed.inHours > 0) {
      elapsedText = '${elapsed.inHours}h ${elapsed.inMinutes % 60}m ago';
    } else {
      elapsedText = '${elapsed.inMinutes}m ago';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => OrderStatusScreen(order: order)),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: AppStyles.cardDecoration.copyWith(
            border: Border.all(color: AppTheme.teamMemberIconOrange.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppTheme.teamMemberOrange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.sync, color: AppTheme.teamMemberIconOrange, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          order.id,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accentBlue,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '•',
                          style: TextStyle(color: AppTheme.textLight.withOpacity(0.5)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            order.customerName,
                            style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.scale_outlined, size: 14, color: AppTheme.textLight.withOpacity(0.7)),
                        const SizedBox(width: 4),
                        Text(
                          '${order.weight} kg',
                          style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                        ),
                        const SizedBox(width: 16),
                        if (order.rfidTag != null) ...[
                          Icon(Icons.nfc_outlined, size: 14, color: AppTheme.accentBlue.withOpacity(0.7)),
                          const SizedBox(width: 4),
                          Text(
                            order.rfidTag!,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.accentBlue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 14, color: AppTheme.textLight.withOpacity(0.7)),
                        const SizedBox(width: 4),
                        Text(
                          'Started $elapsedText',
                          style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
                            fontSize: 11,
                            color: AppTheme.textLight.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textLight),
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
