import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../services/rider_service.dart';
import '../../../models/order.dart';
import 'rider_route_map_screen.dart';
import '../rider_main_screen.dart';
import '../../../widgets/top_notification.dart';

class RiderRouteScreen extends StatefulWidget {
  final VoidCallback? onBackToHome;

  const RiderRouteScreen({super.key, this.onBackToHome});

  @override
  State<RiderRouteScreen> createState() => _RiderRouteScreenState();
}

enum NavigationPhase { onTheWay, arrived, completing, completed }

class _RiderRouteScreenState extends State<RiderRouteScreen> {
  final RiderService _riderService = RiderService();
  
  int _currentStopIndex = 0;
  NavigationPhase _phase = NavigationPhase.onTheWay;
  bool _isLoading = true;
  String? _error;
  
  List<LaundryOrder> _pickupOrders = [];
  List<LaundryOrder> _deliveryOrders = [];
  List<LaundryOrder> _routeOrders = [];
  
  // Track dispatch job IDs for completion
  final Map<String, String> _orderToJobMap = {};

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Clear adapter cache for fresh data
      _riderService.clearAdapterCache();
      
      // Fetch active dispatch jobs
      final pickupJobs = await _riderService.fetchActivePickupJobs();
      final deliveryJobs = await _riderService.fetchActiveDeliveryJobs();
      
      // Convert to LaundryOrders using adapter
      final results = await Future.wait([
        _riderService.fetchActivePickupOrders(),
        _riderService.fetchActiveDeliveryOrders(),
      ]);

      _pickupOrders = results[0];
      _deliveryOrders = results[1];
      
      // Build mapping from order ID to dispatch job ID
      _orderToJobMap.clear();
      for (var job in pickupJobs) {
        _orderToJobMap[job.orderId] = job.id;
      }
      for (var job in deliveryJobs) {
        _orderToJobMap[job.orderId] = job.id;
      }

      // Combine and sort by creation time (FIFO - oldest first)
      _routeOrders = [..._pickupOrders, ..._deliveryOrders]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      print('✅ Route loaded: ${_routeOrders.length} stops');
      print('   Pickups: ${_pickupOrders.length}');
      print('   Deliveries: ${_deliveryOrders.length}');
      print('   Order->Job mapping: ${_orderToJobMap.length} entries');
    } catch (e) {
      print('❌ Error loading route: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  LaundryOrder? get _currentOrder =>
      _currentStopIndex < _routeOrders.length ? _routeOrders[_currentStopIndex] : null;

  bool get _isPickup => _currentOrder != null && _pickupOrders.contains(_currentOrder);

  bool get _isAllCompleted => _routeOrders.isEmpty || _currentStopIndex >= _routeOrders.length;

  void _markAsArrived() {
    setState(() {
      _phase = NavigationPhase.arrived;
    });
    showTopNotification(
      context,
      message: 'Arrived at ${_currentOrder?.customerName}\'s location!',
      icon: Icons.location_on,
      backgroundColor: AppTheme.primaryBlue,
    );
  }

  Future<void> _confirmStop() async {
    if (_currentOrder == null) return;

    final orderName = _currentOrder!.customerName;
    final orderId = _currentOrder!.id;
    
    // Get the dispatch job ID from our mapping
    final jobId = _orderToJobMap[orderId];
    if (jobId == null) {
      print('❌ Error: No dispatch job ID found for order $orderId');
      if (mounted) {
        showTopNotification(
          context,
          message: 'Error: Job information not found. Please refresh.',
          icon: Icons.error,
          backgroundColor: AppTheme.errorRed,
        );
      }
      return;
    }

    try {
      // Set to completing state to show animation
      setState(() {
        _phase = NavigationPhase.completing;
      });

      // Complete dispatch job (this also updates order status automatically)
      if (_isPickup) {
        print('📦 Completing pickup: jobId=$jobId, orderId=$orderId');
        await _riderService.completePickup(jobId, orderId);
      } else {
        print('🚚 Completing delivery: jobId=$jobId, orderId=$orderId');
        await _riderService.completeDelivery(jobId, orderId);
      }

      // Show success notification
      showTopNotification(
        context,
        message: _isPickup 
            ? 'Pickup from $orderName confirmed!' 
            : 'Delivery to $orderName completed!',
        icon: Icons.check_circle,
        backgroundColor: Colors.green,
      );

      // Wait 2.5 seconds to show completion animation
      await Future.delayed(const Duration(milliseconds: 2500));

      // Move to next stop
      if (mounted) {
        setState(() {
          _currentStopIndex++;
          if (_currentStopIndex < _routeOrders.length) {
            _phase = NavigationPhase.onTheWay;
          } else {
            _phase = NavigationPhase.completed;
          }
        });

        // Reload orders to get fresh data
        await _loadOrders();
      }
    } catch (e) {
      print('❌ Error confirming stop: $e');
      if (mounted) {
        setState(() {
          _phase = NavigationPhase.arrived; // Revert to arrived state
        });
        showTopNotification(
          context,
          message: 'Error updating order. Please try again.',
          icon: Icons.error,
          backgroundColor: AppTheme.errorRed,
        );
      }
    }
  }

  void _skipStopDialog() {
    if (_currentOrder == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Skip This Stop?'),
        content: Text('Are you sure you want to skip ${_currentOrder!.customerName}? You can revisit it later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _currentStopIndex++;
                if (_currentStopIndex < _routeOrders.length) {
                  _phase = NavigationPhase.onTheWay;
                } else {
                  _phase = NavigationPhase.completed;
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
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Loading Route...'),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Route Error'),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: AppTheme.errorRed),
                const SizedBox(height: 16),
                const Text(
                  'Error loading route',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textLight),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadOrders,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isAllCompleted) {
      return _buildAllCaughtUpScreen();
    }

    if (_currentOrder == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('No Orders'),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        body: const Center(
          child: Text('No orders available for route'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Stop ${_currentStopIndex + 1} of ${_routeOrders.length}'),
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
    double progress = (_currentStopIndex) / _routeOrders.length;
    final typeColor = _isPickup ? AppTheme.errorRed : AppTheme.teamMemberIconOrange;
    final type = _isPickup ? 'Pickup' : 'Delivery';
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Route Progress: $_currentStopIndex/${_routeOrders.length} completed',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  type,
                  style: TextStyle(
                    color: typeColor,
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
    final address = _currentOrder!.deliveryAddress ?? 'Address not provided';
    
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
            child: const Icon(Icons.navigation, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _phase == NavigationPhase.onTheWay
                      ? 'Navigate to: $address'
                      : 'You have arrived at the destination',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _phase == NavigationPhase.onTheWay
                      ? 'Use navigation app for directions'
                      : 'Park safely & proceed to door',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
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
    final typeColor = _isPickup ? AppTheme.errorRed : AppTheme.teamMemberIconOrange;
    
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
                      color: typeColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: typeColor.withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isPickup ? Icons.shopping_bag : Icons.local_shipping,
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
                      'Stop #${_currentStopIndex + 1}',
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
    final customerName = _currentOrder!.customerName;
    final address = _currentOrder!.deliveryAddress ?? 'Address not provided';
    final phone = _currentOrder!.customerPhone ?? 'No phone';
    final orderNumber = _currentOrder!.orderNumber ?? _currentOrder!.displayNumber;
    final instructions = _currentOrder!.instructions ?? _currentOrder!.staffMessage ?? 'No special instructions';
    final typeColor = _isPickup ? AppTheme.errorRed : AppTheme.teamMemberIconOrange;

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
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _isPickup ? Icons.shopping_bag_outlined : Icons.delivery_dining,
                  color: typeColor,
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
                            customerName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '($orderNumber)',
                          style: const TextStyle(fontSize: 12, color: AppTheme.accentBlue, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      address,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Call action
              if (phone != 'No phone')
                IconButton(
                  icon: const Icon(Icons.phone, color: AppTheme.accentBlue),
                  onPressed: () {
                    showTopNotification(
                      context,
                      message: 'Calling $phone...',
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
                    message: 'Opening chat with $customerName...',
                    icon: Icons.chat_bubble_outline,
                    backgroundColor: AppTheme.accentBlue,
                  );
                },
              ),
            ],
          ),

          // Instructions/Notes banner
          if (instructions.isNotEmpty && instructions != 'No special instructions')
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
                      instructions,
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
          else if (_phase == NavigationPhase.completing)
            // Completing state - show animated success indicator
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 500),
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: 0.8 + (value * 0.2),
                        child: Opacity(
                          opacity: value,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 50,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isPickup ? '✓ Pickup Confirmed!' : '✓ Delivery Completed!',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Moving to next stop...',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textLight,
                    ),
                  ),
                ],
              ),
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
                          _isPickup ? 'Confirm Pickup' : 'Confirm Delivery',
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
    final totalStops = _routeOrders.length;
    final pickupsCount = _pickupOrders.length;
    final deliveriesCount = _deliveryOrders.length;

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
                'You have completed all scheduled route stops. Great work keeping Infinity Wash moving!',
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatItem(label: 'Stops Serviced', value: '$totalStops / $totalStops', color: Colors.green),
                        _StatItem(label: 'Pickups', value: '$pickupsCount', color: AppTheme.errorRed),
                        _StatItem(label: 'Deliveries', value: '$deliveriesCount', color: AppTheme.teamMemberIconOrange),
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
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _returnToDashboard() {
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
