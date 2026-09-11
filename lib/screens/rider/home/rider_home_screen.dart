import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

import '../route/rider_route_screen.dart';
import '../route/rider_route_map_screen.dart';
import '../../../services/mock_data_service.dart';

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  final List<Map<String, dynamic>> _notifications = [
    {
      'title': 'New Pickup Assigned',
      'message': 'You have a new pickup at 123 Mango Ave, Cebu City.',
      'time': '2 min ago',
      'icon': Icons.shopping_bag_outlined,
      'color': AppTheme.errorRed,
      'isRead': false,
    },
    {
      'title': 'Delivery Completed',
      'message': 'Order #1042 has been marked as delivered.',
      'time': '15 min ago',
      'icon': Icons.check_circle_outline,
      'color': Colors.green,
      'isRead': false,
    },
    {
      'title': 'Route Updated',
      'message': 'Your route has been optimized. Please check the new stops.',
      'time': '1 hr ago',
      'icon': Icons.route_outlined,
      'color': AppTheme.accentBlue,
      'isRead': false,
    },
    {
      'title': 'Schedule Change',
      'message': 'Tomorrow\'s shift starts at 8:00 AM instead of 9:00 AM.',
      'time': '3 hrs ago',
      'icon': Icons.schedule,
      'color': AppTheme.teamMemberIconOrange,
      'isRead': true,
    },
  ];

  int get _unreadCount => _notifications.where((n) => n['isRead'] == false).length;

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.65,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.borderGray,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Row(
                    children: [
                      Text('Notifications', style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontSize: 20)),
                      const Spacer(),
                      if (_unreadCount > 0)
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              for (var n in _notifications) {
                                n['isRead'] = true;
                              }
                            });
                            setState(() {});
                          },
                          child: const Text('Mark all read', style: TextStyle(color: AppTheme.accentBlue, fontSize: 13)),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Notification list
                Expanded(
                  child: _notifications.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.notifications_none, size: 48, color: AppTheme.textLight.withOpacity(0.3)),
                              const SizedBox(height: 12),
                              Text('No notifications', style: TextStyle(color: AppTheme.textLight, fontSize: 14)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _notifications.length,
                          separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                          itemBuilder: (context, index) {
                            final notif = _notifications[index];
                            final bool isRead = notif['isRead'] as bool;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: (notif['color'] as Color).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(notif['icon'] as IconData, color: notif['color'] as Color, size: 22),
                              ),
                              title: Text(
                                notif['title'] as String,
                                style: TextStyle(
                                  fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(notif['message'] as String, style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
                                  const SizedBox(height: 4),
                                  Text(notif['time'] as String, style: TextStyle(fontSize: 11, color: AppTheme.textLight.withOpacity(0.6))),
                                ],
                              ),
                              trailing: !isRead
                                  ? Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: AppTheme.accentBlue,
                                        shape: BoxShape.circle,
                                      ),
                                    )
                                  : null,
                              onTap: () {
                                setModalState(() {
                                  _notifications[index]['isRead'] = true;
                                });
                                setState(() {});
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
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
                child: const Icon(Icons.notifications_outlined, color: AppTheme.textDark, size: 24),
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
                        color: AppTheme.teamMemberIconOrange.withOpacity(0.1),
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
                        color: AppTheme.errorRed.withOpacity(0.1),
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
                  color: Colors.green.withOpacity(0.1),
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
                  Icon(Icons.map_outlined, size: 60, color: AppTheme.textLight.withOpacity(0.1)),
                  Positioned(
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
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
                decoration: BoxDecoration(color: typeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
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
