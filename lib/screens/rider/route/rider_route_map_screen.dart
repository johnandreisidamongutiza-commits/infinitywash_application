import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/phone_helper.dart';
import 'rider_route_screen.dart';
import '../../../widgets/top_notification.dart';

class RiderRouteMapScreen extends StatefulWidget {
  final int? initialStopIndex;

  const RiderRouteMapScreen({super.key, this.initialStopIndex});

  @override
  State<RiderRouteMapScreen> createState() => _RiderRouteMapScreenState();
}

class _RiderRouteMapScreenState extends State<RiderRouteMapScreen> {
  int _selectedFilter = 0; // 0: All, 1: Pickups, 2: Deliveries
  int? _expandedStopIndex;

  final List<Map<String, dynamic>> _stops = [
    {
      'stopNumber': 1,
      'name': 'Maria Santos',
      'address': '123 Mango Ave, Cebu City',
      'type': 'Pickup',
      'typeColor': AppTheme.errorRed,
      'time': '09:00 AM - 09:30 AM',
      'orderId': 'IW-105',
      'package': '5 kg Wash & Fold',
      'phone': '+63 912 345 6789',
      'notes': 'Ring the bell at gate #2. Bags will be ready by the door.',
      'status': 'Pending',
    },
    {
      'stopNumber': 2,
      'name': 'Juan Dela Cruz',
      'address': '456 Banilad Rd, Cebu City',
      'type': 'Drop-off',
      'typeColor': AppTheme.teamMemberIconOrange,
      'time': '10:15 AM - 10:45 AM',
      'orderId': 'IW-106',
      'package': '7 kg Dry Clean & Iron',
      'phone': '+63 917 888 1234',
      'notes': 'COD payment of ₱450.00. Leave with lobby concierge if not home.',
      'status': 'Pending',
    },
    {
      'stopNumber': 3,
      'name': 'Ana Reyes',
      'address': '789 Parkmall, Mandaue City',
      'type': 'Pickup',
      'typeColor': AppTheme.errorRed,
      'time': '11:30 AM - 12:00 PM',
      'orderId': 'IW-107',
      'package': '4 kg Beddings & Towels',
      'phone': '+63 920 555 9876',
      'notes': 'Call 5 mins before arrival.',
      'status': 'Pending',
    },
  ];

  @override
  void initState() {
    super.initState();
    _expandedStopIndex = widget.initialStopIndex ?? 0;
  }

  List<Map<String, dynamic>> get _filteredStops {
    if (_selectedFilter == 1) {
      return _stops.where((s) => s['type'] == 'Pickup').toList();
    } else if (_selectedFilter == 2) {
      return _stops.where((s) => s['type'] == 'Drop-off').toList();
    }
    return _stops;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Route Overview'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Route',
            onPressed: () {
              showTopNotification(
                context,
                message: 'Route updated to latest traffic.',
                icon: Icons.refresh,
                backgroundColor: AppTheme.accentBlue,
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Visual Map Overview Banner
          _buildMapHeader(),

          // Route Summary Quick Stats
          _buildQuickStats(),

          // Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                _buildFilterButton('All Stops (${_stops.length})', 0),
                const SizedBox(width: 8),
                _buildFilterButton('Pickups (2)', 1),
                const SizedBox(width: 8),
                _buildFilterButton('Drop-offs (1)', 2),
              ],
            ),
          ),

          // Scrollable stops list
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
              itemCount: _filteredStops.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final stop = _filteredStops[index];
                final isExpanded = _expandedStopIndex == index;
                return _buildStopCard(stop, index, isExpanded);
              },
            ),
          ),
        ],
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: ElevatedButton(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const RiderRouteScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.navigation, size: 22),
                SizedBox(width: 10),
                Text(
                  'Start This Route',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapHeader() {
    return Container(
      height: 200,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE8ECEF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Mock map grid & roads simulation
            CustomPaint(
              size: const Size(double.infinity, 200),
              painter: _MapCanvasPainter(),
            ),

            // Depot pin
            Positioned(
              top: 30,
              left: 35,
              child: _buildPin(
                label: 'Hub',
                icon: Icons.storefront,
                color: AppTheme.primaryBlue,
              ),
            ),

            // Stop pins
            Positioned(
              top: 50,
              left: 120,
              child: _buildPin(
                label: '1',
                icon: Icons.shopping_bag,
                color: AppTheme.errorRed,
                isSelected: _expandedStopIndex == 0,
              ),
            ),
            Positioned(
              top: 110,
              right: 120,
              child: _buildPin(
                label: '2',
                icon: Icons.delivery_dining,
                color: AppTheme.teamMemberIconOrange,
                isSelected: _expandedStopIndex == 1,
              ),
            ),
            Positioned(
              bottom: 25,
              right: 40,
              child: _buildPin(
                label: '3',
                icon: Icons.shopping_bag,
                color: AppTheme.errorRed,
                isSelected: _expandedStopIndex == 2,
              ),
            ),

            // Map overlay tag
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map, size: 14, color: AppTheme.accentBlue),
                    SizedBox(width: 4),
                    Text(
                      'Metro Cebu Route',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPin({
    required String label,
    required IconData icon,
    required Color color,
    bool isSelected = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white,
              width: isSelected ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: isSelected ? 8 : 4,
                spreadRadius: isSelected ? 2 : 0,
              ),
            ],
          ),
          child: Icon(icon, size: isSelected ? 18 : 14, color: Colors.white),
        ),
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.softGray,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatColumn(icon: Icons.alt_route, label: 'Distance', value: '14.2 km'),
          _StatDivider(),
          _StatColumn(icon: Icons.timer_outlined, label: 'Est. Time', value: '1h 45m'),
          _StatDivider(),
          _StatColumn(icon: Icons.pin_drop_outlined, label: 'Total Stops', value: '3 Stops'),
        ],
      ),
    );
  }

  Widget _buildFilterButton(String title, int index) {
    final isSelected = _selectedFilter == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentBlue : AppTheme.softGray,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textDark,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildStopCard(Map<String, dynamic> stop, int index, bool isExpanded) {
    return Container(
      decoration: AppStyles.cardDecoration,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: isExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              _expandedStopIndex = expanded ? index : null;
            });
          },
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (stop['typeColor'] as Color).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${stop['stopNumber']}',
                style: TextStyle(
                  color: stop['typeColor'] as Color,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  stop['name'] as String,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (stop['typeColor'] as Color).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  stop['type'] as String,
                  style: TextStyle(
                    color: stop['typeColor'] as Color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textLight),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      stop['address'] as String,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 13, color: AppTheme.accentBlue),
                  const SizedBox(width: 4),
                  Text(
                    stop['time'] as String,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.accentBlue),
                  ),
                ],
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.receipt_outlined, 'Order ID', stop['orderId'] as String),
                  const SizedBox(height: 6),
                  _buildDetailRow(Icons.inventory_2_outlined, 'Package', stop['package'] as String),
                  const SizedBox(height: 6),
                  _buildDetailRow(Icons.notes_outlined, 'Instructions', stop['notes'] as String),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final phone = stop['phone'] as String? ?? '';
                            PhoneHelper.openDialer(
                              context,
                              phone: (phone.isNotEmpty && phone != 'No phone') ? phone : null,
                              contactName: (stop['name'] ?? stop['customer']) as String?,
                            );
                          },
                          icon: const Icon(Icons.phone_outlined, size: 16),
                          label: const Text('Call', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => const RiderRouteScreen()),
                            );
                          },
                          icon: const Icon(Icons.navigation, size: 16),
                          label: const Text('Go Here', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppTheme.textLight),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
          ),
        ),
      ],
    );
  }
}

class _StatColumn extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatColumn({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: AppTheme.accentBlue),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textLight)),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 28, width: 1, color: AppTheme.borderGray);
  }
}

class _MapCanvasPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;

    final pathPaint = Paint()
      ..color = AppTheme.accentBlue
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Roads background
    final roadPath = Path();
    roadPath.moveTo(0, size.height * 0.4);
    roadPath.quadraticBezierTo(size.width * 0.3, size.height * 0.3, size.width * 0.5, size.height * 0.6);
    roadPath.lineTo(size.width, size.height * 0.5);

    roadPath.moveTo(size.width * 0.3, 0);
    roadPath.lineTo(size.width * 0.4, size.height);

    roadPath.moveTo(size.width * 0.75, 0);
    roadPath.lineTo(size.width * 0.65, size.height);

    canvas.drawPath(roadPath, roadPaint);

    // Active Route Path line
    final routePath = Path();
    routePath.moveTo(45, 55); // Hub
    routePath.lineTo(130, 75); // Stop 1
    routePath.lineTo(size.width - 110, 135); // Stop 2
    routePath.lineTo(size.width - 30, size.height - 35); // Stop 3

    canvas.drawPath(routePath, pathPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
