import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../widgets/map_widget.dart';
import '../config/location_constants.dart';

/// Test screen for Phase 4: Job Marker (Hardcoded)
/// 
/// Tests:
/// - Shop marker and job markers display together
/// - Different marker types (shop, pickup, delivery)
/// - Multiple markers visible simultaneously
/// - Map bounds fit all markers
class TestJobMarkerScreen extends StatefulWidget {
  const TestJobMarkerScreen({super.key});

  @override
  State<TestJobMarkerScreen> createState() => _TestJobMarkerScreenState();
}

class _TestJobMarkerScreenState extends State<TestJobMarkerScreen> {
  late final MapController _mapController;
  bool _showShop = true;
  bool _showPickup = true;
  bool _showDelivery = true;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    
    // Fit map to show all markers after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitBoundsToMarkers();
    });
  }

  void _fitBoundsToMarkers() {
    final points = <LatLng>[
      if (_showShop) LocationConstants.infinityWashShop,
      if (_showPickup) LocationConstants.testPickupLocation,
      if (_showDelivery) LocationConstants.testDeliveryLocation,
    ];

    if (points.isEmpty) return;

    // Calculate bounds
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    final bounds = LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );

    // Fit bounds with padding
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  List<Marker> _getMarkers() {
    final markers = <Marker>[];

    if (_showShop) {
      markers.add(
        MapMarkers.createShopMarker(
          id: 'shop',
          position: LocationConstants.infinityWashShop,
          label: 'Hub',
        ),
      );
    }

    if (_showPickup) {
      markers.add(
        MapMarkers.createPickupMarker(
          id: 'pickup',
          position: LocationConstants.testPickupLocation,
          label: '1',
        ),
      );
    }

    if (_showDelivery) {
      markers.add(
        MapMarkers.createDeliveryMarker(
          id: 'delivery',
          position: LocationConstants.testDeliveryLocation,
          label: '2',
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Markers Test - Phase 4'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                switch (value) {
                  case 'toggle_shop':
                    _showShop = !_showShop;
                    break;
                  case 'toggle_pickup':
                    _showPickup = !_showPickup;
                    break;
                  case 'toggle_delivery':
                    _showDelivery = !_showDelivery;
                    break;
                }
              });
              _fitBoundsToMarkers();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'toggle_shop',
                child: Row(
                  children: [
                    Icon(
                      _showShop ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 20,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    const Text('Shop Marker'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'toggle_pickup',
                child: Row(
                  children: [
                    Icon(
                      _showPickup ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 20,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 8),
                    const Text('Pickup Marker'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'toggle_delivery',
                child: Row(
                  children: [
                    Icon(
                      _showDelivery ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 20,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    const Text('Delivery Marker'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Info banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.orange.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '✅ Phase 4: Job Marker Test',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Testing: Shop + Pickup + Delivery markers display together',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),

          // Legend
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLegendItem(Icons.storefront, 'Hub', Colors.blue),
                _buildLegendItem(Icons.shopping_bag, 'Pickup', Colors.red),
                _buildLegendItem(Icons.delivery_dining, 'Delivery', Colors.orange),
              ],
            ),
          ),

          // Map
          Expanded(
            child: MapWidget(
              center: LocationConstants.infinityWashShop,
              zoom: LocationConstants.routeOverviewZoom,
              markers: _getMarkers(),
              polylines: const [],
              mapController: _mapController,
              onTap: (latLng) {
                _showLocationInfo(latLng);
              },
            ),
          ),

          // Test instructions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Test Checklist:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    TextButton.icon(
                      onPressed: _fitBoundsToMarkers,
                      icon: const Icon(Icons.fit_screen, size: 16),
                      label: const Text('Fit All', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildCheckItem('Blue shop marker (Hub) visible'),
                _buildCheckItem('Red pickup marker (1) visible'),
                _buildCheckItem('Orange delivery marker (2) visible'),
                _buildCheckItem('All markers distinct and not overlapping'),
                _buildCheckItem('Filter menu toggles markers on/off'),
                _buildCheckItem('Tap marker shows info'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _showTestResultDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Phase 4 Complete ✓'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'info_shop',
            onPressed: () => _showMarkerInfo('shop'),
            tooltip: 'Shop Info',
            child: const Icon(Icons.storefront),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'info_pickup',
            onPressed: () => _showMarkerInfo('pickup'),
            tooltip: 'Pickup Info',
            backgroundColor: Colors.red,
            child: const Icon(Icons.shopping_bag),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'info_delivery',
            onPressed: () => _showMarkerInfo('delivery'),
            tooltip: 'Delivery Info',
            backgroundColor: Colors.orange,
            child: const Icon(Icons.delivery_dining),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildCheckItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.check_box_outline_blank, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _showLocationInfo(LatLng latLng) {
    final distanceFromShop = LocationHelper.getFormattedDistance(latLng);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Distance from shop: $distanceFromShop'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showMarkerInfo(String type) {
    late String title;
    late IconData icon;
    late Color color;
    late LatLng location;
    late String address;

    switch (type) {
      case 'shop':
        title = 'Shop Location';
        icon = Icons.storefront;
        color = Colors.blue;
        location = LocationConstants.infinityWashShop;
        address = LocationConstants.shopAddress;
        break;
      case 'pickup':
        title = 'Pickup Location';
        icon = Icons.shopping_bag;
        color = Colors.red;
        location = LocationConstants.testPickupLocation;
        address = LocationConstants.testPickupAddress;
        break;
      case 'delivery':
        title = 'Delivery Location';
        icon = Icons.delivery_dining;
        color = Colors.orange;
        location = LocationConstants.testDeliveryLocation;
        address = LocationConstants.testDeliveryAddress;
        break;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              address,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
              'Coordinates:',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
            ),
            Text(
              '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            if (type != 'shop') ...[
              const SizedBox(height: 12),
              Text(
                'Distance from shop: ${LocationHelper.getFormattedDistance(location)}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _mapController.move(location, LocationConstants.defaultZoom);
            },
            child: const Text('Go There'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showTestResultDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('Phase 4 Complete'),
          ],
        ),
        content: const Text(
          'Multiple markers functionality verified!\n\n'
          'What was tested:\n'
          '✓ Shop marker (blue, hub)\n'
          '✓ Pickup marker (red, #1)\n'
          '✓ Delivery marker (orange, #2)\n'
          '✓ All markers visible together\n'
          '✓ Distinct styling for each type\n\n'
          'Next steps:\n'
          '• Phase 5: GPS integration (Android + iOS)\n'
          '• Phase 6: Rider marker\n'
          '• Phase 7: Routing service',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
