import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../services/notification_service.dart';

import '../route/rider_route_screen.dart';
import '../route/rider_route_map_screen.dart';
import '../../../services/mock_data_service.dart';
import '../notifications/rider_notifications_screen.dart';

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  final NotificationService _notificationService = NotificationService();
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    final count = await _notificationService.getUnreadCount();
    if (mounted) {
      setState(() => _unreadCount = count);
    }
  }

  void _showNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RiderNotificationsScreen()),
    ).then((_) => _loadUnreadCount()); // Reload count when returning
  }

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
              _buildDeliveriesSummary(),
              const SizedBox(height: 30),
              _buildRouteSection(),
              const SizedBox(height: 30),
              Builder(
                builder: (context) {
                  final isRouteCompleted = MockDataService().isRiderRouteCompleted;
                  return ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RiderRouteScreen()),
                      ).then((_) => setState(() {}));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRouteCompleted ? Colors.green : AppTheme.accentBlue,
                      minimumSize: const Size(double.infinity, 80),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(isRouteCompleted ? Icons.check_circle_outline : Icons.play_arrow, size: 30),
                        const SizedBox(width: 12),
                        Text(
                          isRouteCompleted ? 'Route Completed' : 'Start Route',
                          style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(color: Colors.white, fontSize: 20),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
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
          width: 50,
          height: 50,
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Infinity Wash',
                style: AppTheme.lightTheme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
              const Text(
                'RIDER',
                style: TextStyle(color: AppTheme.accentBlue, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _showNotifications,
          child: Stack(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.softGray,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.notifications_outlined, 
                  color: _unreadCount > 0 ? AppTheme.errorRed : AppTheme.textDark, 
                  size: 24
                ),
              ),
              if (_unreadCount > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppTheme.errorRed,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        '$_unreadCount',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveriesSummary() {
    final isDone = MockDataService().isRiderRouteCompleted;
    int deliveriesLeft = isDone ? 0 : 3;
    int pickupsLeft = isDone ? 0 : 2;
    int completed = isDone ? 5 : 3;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppStyles.cardDecoration,
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, color: AppTheme.errorRed, size: 20),
              const SizedBox(width: 12),
              Text('Today\'s Deliveries', style: AppTheme.lightTheme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 24),
          // Pending Tasks (Primary Focus)
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.teamMemberIconOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.local_shipping_outlined, color: AppTheme.teamMemberIconOrange),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$deliveriesLeft', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
                          Text('Deliveries Left', style: TextStyle(color: AppTheme.textLight, fontSize: 10), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 40, color: AppTheme.borderGray),
              Expanded(
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.errorRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.shopping_bag_outlined, color: AppTheme.errorRed),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$pickupsLeft', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
                          Text('Pick-ups Left', style: TextStyle(color: AppTheme.textLight, fontSize: 10), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Divider
          Container(
            height: 1,
            color: AppTheme.borderGray,
          ),
          const SizedBox(height: 20),
          // Completed Tasks (Secondary Info)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, color: Colors.green, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                '$completed Completed',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRouteSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppStyles.cardDecoration,
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.route_outlined, color: AppTheme.accentBlue, size: 20),
              const SizedBox(width: 12),
              Text('Today\'s Route', style: AppTheme.lightTheme.textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RiderRouteMapScreen()),
                  );
                },
                child: const Row(
                  children: [
                    Text('View Map', style: TextStyle(color: AppTheme.accentBlue)),
                    Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.accentBlue),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Mock Map Area (tap to view full map)
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RiderRouteMapScreen()),
              );
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderGray),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.map_outlined, size: 60, color: AppTheme.textLight.withValues(alpha: 0.1)),
                  Positioned(
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.touch_app_outlined, size: 14, color: AppTheme.accentBlue),
                          SizedBox(width: 4),
                          Text(
                            'Tap to explore route map',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.accentBlue),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildRouteStop(0, '1', 'Maria Santos', '123 Mango Ave, Cebu City', 'Pickup', '09:00 AM', AppTheme.errorRed),
          _buildRouteStop(1, '2', 'Juan Dela Cruz', '456 Banilad Rd, Cebu City', 'Drop-off', '10:15 AM', AppTheme.teamMemberIconOrange),
          _buildRouteStop(2, '3', 'Ana Reyes', '789 Parkmall, Mandaue City', 'Pickup', '11:30 AM', AppTheme.errorRed),
        ],
      ),
    );
  }

  Widget _buildRouteStop(int index, String number, String name, String address, String type, String time, Color typeColor) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => RiderRouteMapScreen(initialStopIndex: index)),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(color: AppTheme.accentBlue, shape: BoxShape.circle),
                child: Center(child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(address, style: TextStyle(color: AppTheme.textLight, fontSize: 10), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(type, style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Text(time, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
