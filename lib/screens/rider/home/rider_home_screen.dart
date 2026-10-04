import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../theme/app_theme.dart';
import '../../../services/notification_service.dart';
import '../../../services/rider_service.dart';
import '../../../services/supabase_service.dart';
import '../../../models/dispatch_job.dart';
import '../../../config/location_constants.dart';
import '../../../widgets/cached_tile_provider.dart';
import '../route/rider_route_screen_new.dart';
import '../jobs/rider_job_details_screen.dart';
import '../notifications/rider_notifications_screen.dart';

class RiderHomeScreen extends StatefulWidget {
  final ValueChanged<int>? onSelectTab;

  const RiderHomeScreen({super.key, this.onSelectTab});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  final NotificationService _notificationService = NotificationService();
  final RiderService _riderService = RiderService();
  int _unreadCount = 0;
  bool _isLoading = true;
  List<DispatchJob> _pickupJobs = [];
  List<DispatchJob> _deliveryJobs = [];
  List<DispatchJob> _completedPickupJobs = [];
  List<DispatchJob> _completedDeliveryJobs = [];

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
    _loadOrders();
  }

  Future<void> _loadUnreadCount() async {
    final count = await _notificationService.getUnreadCount();
    if (mounted) {
      setState(() => _unreadCount = count);
    }
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    
    try {
      // Fetch only ACTIVE jobs (pending/in_progress) for today's route
      final pickupJobs = await _riderService.fetchActivePickupJobs();
      final deliveryJobs = await _riderService.fetchActiveDeliveryJobs();
      
      // Fetch COMPLETED jobs (today only) for statistics
      final completedPickupJobs = await _riderService.fetchCompletedPickupJobs();
      final completedDeliveryJobs = await _riderService.fetchCompletedDeliveryJobs();
      
      if (mounted) {
        setState(() {
          _pickupJobs = pickupJobs;
          _deliveryJobs = deliveryJobs;
          _completedPickupJobs = completedPickupJobs;
          _completedDeliveryJobs = completedDeliveryJobs;
          _isLoading = false;
        });
        
        print('✅ Rider home loaded:');
        print('   Active Pickups: ${_pickupJobs.length}');
        print('   Active Deliveries: ${_deliveryJobs.length}');
        print('   Completed Pickups: ${_completedPickupJobs.length}');
        print('   Completed Deliveries: ${_completedDeliveryJobs.length}');
      }
    } catch (e) {
      print('❌ Error loading rider jobs: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
        child: RefreshIndicator(
          onRefresh: _loadOrders,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 30),
                _isLoading ? _buildLoadingState() : _buildDeliveriesSummary(),
                const SizedBox(height: 30),
                _isLoading ? _buildLoadingState() : _buildRouteSection(),
                const SizedBox(height: 30),
                _buildStartButton(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: AppStyles.cardDecoration,
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildStartButton() {
    final hasOrders = _pickupJobs.isNotEmpty || _deliveryJobs.isNotEmpty;
    
    return ElevatedButton(
      onPressed: hasOrders ? () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RiderRouteScreenNew()),
        ).then((_) => _loadOrders());
      } : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: hasOrders ? AppTheme.accentBlue : AppTheme.borderGray,
        minimumSize: const Size(double.infinity, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasOrders ? Icons.play_arrow : Icons.inbox_outlined, 
            size: 30,
            color: hasOrders ? Colors.white : AppTheme.textLight,
          ),
          const SizedBox(width: 12),
          Text(
            hasOrders ? 'Start Route' : 'No Orders Available',
            style: TextStyle(
              color: hasOrders ? Colors.white : AppTheme.textLight,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
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
    int deliveriesLeft = _deliveryJobs.length;
    int pickupsLeft = _pickupJobs.length;
    int completed = _completedPickupJobs.length + _completedDeliveryJobs.length;

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
          if (completed > 0) ...[
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
        ],
      ),
    );
  }

  Widget _buildRouteSection() {
    // Combine pickups and deliveries for route display
    final allJobs = [..._pickupJobs, ..._deliveryJobs];
    
    // Show max 3 jobs in preview
    final displayJobs = allJobs.take(3).toList();

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
                onPressed: () => widget.onSelectTab?.call(2),
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
          // Mini Map Preview (tap to view full map)
          InkWell(
            onTap: () => widget.onSelectTab?.call(1),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderGray),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // Actual map with markers
                  AbsorbPointer(
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: _getMapCenter(),
                        initialZoom: _getMapZoom(),
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.none,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.infinitywash.app',
                          tileProvider: CachedTileProvider(),
                        ),
                        if (_buildMiniMapMarkers().isNotEmpty)
                          MarkerLayer(markers: _buildMiniMapMarkers()),
                      ],
                    ),
                  ),
                  // Tap hint overlay
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
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
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (displayJobs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 48, color: AppTheme.textLight.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text(
                    'No orders for today',
                    style: TextStyle(
                      color: AppTheme.textLight.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          else
            ...displayJobs.asMap().entries.map((entry) {
              final index = entry.key;
              final job = entry.value;
              final isPickup = job.jobType == 'pickup';
              
              return _buildRouteStop(
                index,
                '${index + 1}',
                job.customerName ?? 'Unknown Customer',
                job.address ?? 'No address',
                isPickup ? 'Pickup' : 'Drop-off',
                _formatTime(job.createdAt),
                isPickup ? AppTheme.errorRed : AppTheme.teamMemberIconOrange,
                job,
                isPickup,
              );
            }),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  Widget _buildRouteStop(
    int index, 
    String number, 
    String name, 
    String address, 
    String type, 
    String time, 
    Color typeColor,
    DispatchJob job,
    bool isPickup,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RiderJobDetailsScreen(job: job),
            ),
          ).then((_) => _loadOrders()); // Refresh after viewing details
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
                child: Center(child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(address, style: TextStyle(color: AppTheme.textLight, fontSize: 11), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(type, style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Text(time, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.textLight)),
            ],
          ),
        ),
      ),
    );
  }

  /// Get map center based on job locations
  LatLng _getMapCenter() {
    final allJobs = [..._pickupJobs, ..._deliveryJobs];
    
    // If no jobs, center on shop
    if (allJobs.isEmpty) {
      return LocationConstants.shopLocation;
    }

    // Get jobs with valid coordinates
    final jobsWithCoords = allJobs
        .where((j) => 
            j.latitude != null && 
            j.longitude != null &&
            j.latitude!.isFinite && 
            j.longitude!.isFinite)
        .toList();

    // If no valid coordinates, center on shop
    if (jobsWithCoords.isEmpty) {
      return LocationConstants.shopLocation;
    }

    // Calculate center point
    double avgLat = jobsWithCoords.fold(0.0, (sum, j) => sum + j.latitude!) / jobsWithCoords.length;
    double avgLng = jobsWithCoords.fold(0.0, (sum, j) => sum + j.longitude!) / jobsWithCoords.length;

    return LatLng(avgLat, avgLng);
  }

  /// Get appropriate zoom level based on job spread
  double _getMapZoom() {
    final allJobs = [..._pickupJobs, ..._deliveryJobs];
    
    if (allJobs.isEmpty || allJobs.length == 1) {
      return 14.0;
    }

    // Get jobs with valid coordinates
    final jobsWithCoords = allJobs
        .where((j) => 
            j.latitude != null && 
            j.longitude != null &&
            j.latitude!.isFinite && 
            j.longitude!.isFinite)
        .toList();

    if (jobsWithCoords.length <= 1) {
      return 14.0;
    }

    // Calculate rough bounds
    final lats = jobsWithCoords.map((j) => j.latitude!).toList();
    final lngs = jobsWithCoords.map((j) => j.longitude!).toList();
    
    final latDiff = lats.reduce((a, b) => a > b ? a : b) - lats.reduce((a, b) => a < b ? a : b);
    final lngDiff = lngs.reduce((a, b) => a > b ? a : b) - lngs.reduce((a, b) => a < b ? a : b);
    
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

    // Adjust zoom based on spread
    if (maxDiff > 0.1) return 11.0;
    if (maxDiff > 0.05) return 12.0;
    if (maxDiff > 0.02) return 13.0;
    return 14.0;
  }

  /// Build markers for mini map preview
  List<Marker> _buildMiniMapMarkers() {
    final markers = <Marker>[];
    final allJobs = [..._pickupJobs, ..._deliveryJobs];

    // Always show shop marker
    markers.add(Marker(
      point: LocationConstants.shopLocation,
      width: 30,
      height: 30,
      child: const Icon(Icons.store, color: AppTheme.accentBlue, size: 30),
    ));

    // If no jobs, return just the shop marker
    if (allJobs.isEmpty) {
      return markers;
    }

    // Job markers (max 10 to avoid clutter)
    final displayJobs = allJobs.take(10).toList();
    
    for (int i = 0; i < displayJobs.length; i++) {
      final job = displayJobs[i];
      if (job.latitude == null || job.longitude == null) continue;
      if (!job.latitude!.isFinite || !job.longitude!.isFinite) continue;

      final isPickup = job.jobType == 'pickup';
      final markerColor = isPickup ? AppTheme.errorRed : AppTheme.teamMemberIconOrange;

      markers.add(Marker(
        point: LatLng(job.latitude!, job.longitude!),
        width: 30,
        height: 30,
        child: Stack(
          children: [
            Icon(
              Icons.location_on,
              color: markerColor,
              size: 30,
            ),
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: Text(
                '${i + 1}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ));
    }

    return markers;
  }
}
