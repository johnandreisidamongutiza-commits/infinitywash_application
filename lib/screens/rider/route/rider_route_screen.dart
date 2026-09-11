import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../services/mock_data_service.dart';
import 'rider_route_map_screen.dart';
import '../rider_main_screen.dart';
import '../../../widgets/top_notification.dart';

class RiderRouteScreen extends StatefulWidget {
  final VoidCallback? onBackToHome;

  const RiderRouteScreen({super.key, this.onBackToHome});

  @override
  State<RiderRouteScreen> createState() => _RiderRouteScreenState();
}

enum NavigationPhase { onTheWay, arrived, completed }

class _RiderRouteScreenState extends State<RiderRouteScreen> {
  int _currentStopIndex = 0;
  NavigationPhase _phase = NavigationPhase.onTheWay;

  // Mock list of stops for today's active route
  final List<Map<String, dynamic>> _stops = [
    {
      'stopNumber': 1,
      'name': 'Maria Santos',
      'address': '123 Mango Ave, Cebu City',
      'type': 'Pickup',
      'typeColor': AppTheme.errorRed,
      'time': '09:00 AM',
      'eta': '5 mins (1.4 km)',
      'turnInstruction': 'In 250m, turn right onto Mango Ave',
      'phone': '+63 912 345 6789',
      'orderId': 'IW-105',
      'items': '2 Laundry Bags (est. 5 kg)',
      'notes': 'Ring the doorbell at gate #2. Bags are by the front door.',
      'status': 'In Progress',
    },
    {
      'stopNumber': 2,
      'name': 'Juan Dela Cruz',
      'address': '456 Banilad Rd, Cebu City',
      'type': 'Drop-off',
      'typeColor': AppTheme.teamMemberIconOrange,
      'time': '10:15 AM',
      'eta': '14 mins (4.8 km)',
      'turnInstruction': 'Head north on Banilad Rd towards Gov. Cuenco',
      'phone': '+63 917 888 1234',
      'orderId': 'IW-106',
      'items': 'Fresh Clean & Folded (7 kg)',
      'notes': 'COD Payment: ₱450.00. Gate guard will assist.',
      'status': 'Upcoming',
    },
    {
      'stopNumber': 3,
      'name': 'Ana Reyes',
      'address': '789 Parkmall, Mandaue City',
      'type': 'Pickup',
      'typeColor': AppTheme.errorRed,
      'time': '11:30 AM',
      'eta': '22 mins (8.1 km)',
      'turnInstruction': 'Merge onto Mandaue Causeway, take exit 4',
      'phone': '+63 920 555 9876',
      'orderId': 'IW-107',
      'items': '1 Heavy Comforter & Towels',
      'notes': 'Call 5 minutes prior to arrival.',
      'status': 'Upcoming',
    },
  ];

  Map<String, dynamic> get _currentStop =>
      _currentStopIndex < _stops.length ? _stops[_currentStopIndex] : _stops.last;

  bool get _isAllCompleted =>
      MockDataService().isRiderRouteCompleted || _currentStopIndex >= _stops.length;

  void _markAsArrived() {
    setState(() {
      _phase = NavigationPhase.arrived;
    });
    showTopNotification(
      context,
      message: 'Arrived at ${_currentStop['name']}\'s location!',
      icon: Icons.location_on,
      backgroundColor: AppTheme.primaryBlue,
    );
  }

  void _confirmStop() {
    final stopName = _currentStop['name'];
    final isPickup = _currentStop['type'] == 'Pickup';

    setState(() {
      _stops[_currentStopIndex]['status'] = 'Completed';
      _currentStopIndex++;
      if (_currentStopIndex < _stops.length) {
        _phase = NavigationPhase.onTheWay;
        _stops[_currentStopIndex]['status'] = 'In Progress';
      } else {
        _phase = NavigationPhase.completed;
        MockDataService().completeRiderRoute();
      }
    });

    showTopNotification(
      context,
      message: isPickup
          ? 'Pickup from $stopName confirmed!'
          : 'Delivery to $stopName completed!',
      icon: Icons.check_circle,
      backgroundColor: Colors.green,
    );
  }

  void _skipStopDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Skip This Stop?'),
        content: Text('Are you sure you want to skip Stop #${_currentStop['stopNumber']} (${_currentStop['name']})? You can revisit it later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _stops[_currentStopIndex]['status'] = 'Skipped';
                _currentStopIndex++;
                if (_currentStopIndex < _stops.length) {
                  _phase = NavigationPhase.onTheWay;
                  _stops[_currentStopIndex]['status'] = 'In Progress';
                } else {
                  _phase = NavigationPhase.completed;
                  MockDataService().completeRiderRoute();
                }
              });
              showTopNotification(
                context,
                message: 'Stop skipped. Moving to next stop.',
                icon: Icons.skip_next,
                backgroundColor: AppTheme.errorRed,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            child: const Text('Skip Stop'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isAllCompleted) {
      return _buildAllCaughtUpScreen();
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Stop ${_currentStopIndex + 1} of ${_stops.length}'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RiderRouteMapScreen()),
              );
            },
            icon: const Icon(Icons.map_outlined, size: 18, color: AppTheme.accentBlue),
            label: const Text('View Map', style: TextStyle(color: AppTheme.accentBlue, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress Bar at top
            _buildProgressBar(),

            // Turn-by-Turn Header Card
            _buildTurnBanner(),

            // Interactive Navigation Map Simulation
            Expanded(
              flex: 5,
              child: _buildNavigationMap(),
            ),

            // Active Customer & Destination Card with Actions
            _buildBottomActionPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    double progress = (_currentStopIndex) / _stops.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Route Progress: ${(_currentStopIndex)}/${_stops.length} completed',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (_currentStop['typeColor'] as Color).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _currentStop['type'] as String,
                  style: TextStyle(
                    color: _currentStop['typeColor'] as Color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppTheme.softGray,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentBlue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurnBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.turn_right, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _phase == NavigationPhase.onTheWay
                      ? (_currentStop['turnInstruction'] as String)
                      : 'You have arrived at the destination',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _phase == NavigationPhase.onTheWay
                      ? 'ETA: ${_currentStop['eta']}'
                      : 'Park safely & proceed to door',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (_phase == NavigationPhase.onTheWay)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Column(
                children: [
                  Text(
                    '35',
                    style: TextStyle(
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'km/h',
                    style: TextStyle(
                      color: AppTheme.textLight,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNavigationMap() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE5EBEF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Mock Navigation Map Graphic
            CustomPaint(
              size: const Size(double.infinity, double.infinity),
              painter: _NavMapPainter(),
            ),

            // Center Rider Arrow (Live location simulation)
            Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: AppTheme.accentBlue,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accentBlue,
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.navigation, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),

            // Destination Pin Icon
            Positioned(
              top: 30,
              right: 50,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _currentStop['typeColor'] as Color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: (_currentStop['typeColor'] as Color).withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Icon(
                      _currentStop['type'] == 'Pickup' ? Icons.shopping_bag : Icons.local_shipping,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Text(
                      'Stop #${_currentStop['stopNumber']}',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

            // Compass overlay
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.explore, size: 22, color: AppTheme.primaryBlue),
              ),
            ),

            // Recenter Button
            Positioned(
              bottom: 12,
              right: 12,
              child: FloatingActionButton.small(
                heroTag: 'recenter_fab',
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primaryBlue,
                onPressed: () {
                  showTopNotification(
                    context,
                    message: 'Recentered to GPS location',
                    icon: Icons.my_location,
                    backgroundColor: AppTheme.primaryBlue,
                  );
                },
                child: const Icon(Icons.my_location),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionPanel() {
    final isPickup = _currentStop['type'] == 'Pickup';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Customer quick details
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (_currentStop['typeColor'] as Color).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPickup ? Icons.shopping_bag_outlined : Icons.delivery_dining,
                  color: _currentStop['typeColor'] as Color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _currentStop['name'] as String,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(${_currentStop['orderId']})',
                          style: const TextStyle(fontSize: 12, color: AppTheme.accentBlue, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _currentStop['address'] as String,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Call action
              IconButton(
                icon: const Icon(Icons.phone, color: AppTheme.accentBlue),
                onPressed: () {
                  showTopNotification(
                    context,
                    message: 'Calling ${_currentStop['phone']}...',
                    icon: Icons.phone,
                    backgroundColor: AppTheme.accentBlue,
                  );
                },
              ),
              // Message action
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline, color: AppTheme.accentBlue),
                onPressed: () {
                  showTopNotification(
                    context,
                    message: 'Opening chat with ${_currentStop['name']}...',
                    icon: Icons.chat_bubble_outline,
                    backgroundColor: AppTheme.accentBlue,
                  );
                },
              ),
            ],
          ),

          // Instructions/Notes banner
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.softGray,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: AppTheme.textDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentStop['notes'] as String,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textDark),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Action Buttons
          if (_phase == NavigationPhase.onTheWay)
            Row(
              children: [
                OutlinedButton(
                  onPressed: _skipStopDialog,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(100, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Skip'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _markAsArrived,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, size: 20),
                        SizedBox(width: 8),
                        Text('Mark as Arrived', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _phase = NavigationPhase.onTheWay),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(80, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Back'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _confirmStop,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.done_all, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          isPickup ? 'Confirm Pickup' : 'Confirm Delivery',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildAllCaughtUpScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Route Status'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            children: [
              const SizedBox(height: 10),
              // Success / Trophy graphic
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.task_alt, color: Colors.green, size: 50),
              ),
              const SizedBox(height: 20),
              const Text(
                'All Caught Up for Today! 🎉',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You have completed all scheduled route stops for Metro Cebu. Great work keeping Infinity Wash moving!',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textLight, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 24),

              // Route Performance Summary Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: AppStyles.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.analytics_outlined, color: AppTheme.accentBlue, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          "Today's Performance",
                          style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatItem(label: 'Stops Serviced', value: '3 / 3', color: Colors.green),
                        _StatItem(label: 'Pickups', value: '2', color: AppTheme.errorRed),
                        _StatItem(label: 'Deliveries', value: '1', color: AppTheme.teamMemberIconOrange),
                      ],
                    ),
                    const Divider(height: 28),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatItem(label: 'Total Time', value: '1h 18m', color: AppTheme.primaryBlue),
                        _StatItem(label: 'Total Distance', value: '14.2 km', color: AppTheme.primaryBlue),
                        _StatItem(label: 'On-Time Rate', value: '100%', color: Colors.green),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Dispatch queue status card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.softGray,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.borderGray),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Status: Online & Available',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Waiting for next dispatch batch from shop.',
                            style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Action Buttons
              ElevatedButton(
                onPressed: _returnToDashboard,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.home_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Go to Dashboard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _resetRouteForDemo,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh, size: 18),
                    SizedBox(width: 8),
                    Text('Reset Route (Demo Mode)', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _returnToDashboard() {
    MockDataService().completeRiderRoute();

    if (widget.onBackToHome != null) {
      widget.onBackToHome!();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const RiderMainScreen(initialIndex: 0)),
        (route) => false,
      );
    }
  }

  void _resetRouteForDemo() {
    MockDataService().resetRiderRoute();
    setState(() {
      _currentStopIndex = 0;
      _phase = NavigationPhase.onTheWay;
      for (var s in _stops) {
        s['status'] = s['stopNumber'] == 1 ? 'In Progress' : 'Upcoming';
      }
    });
    showTopNotification(
      context,
      message: 'Route has been reset for demonstration!',
      icon: Icons.refresh,
      backgroundColor: AppTheme.accentBlue,
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatItem({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
        ),
      ],
    );
  }
}

class _NavMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Background roads
    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 24
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final roadBorderPaint = Paint()
      ..color = const Color(0xFFD0D7DE)
      ..strokeWidth = 28
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Active Navigation Line
    final navLinePaint = Paint()
      ..color = AppTheme.accentBlue
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(size.width * 0.5, size.height * 0.85);
    path.lineTo(size.width * 0.5, size.height * 0.5);
    path.quadraticBezierTo(size.width * 0.5, size.height * 0.3, size.width * 0.7, size.height * 0.25);
    path.lineTo(size.width * 0.82, size.height * 0.2);

    canvas.drawPath(path, roadBorderPaint);
    canvas.drawPath(path, roadPaint);
    canvas.drawPath(path, navLinePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
