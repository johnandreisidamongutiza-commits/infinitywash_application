import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../widgets/map_widget.dart';
import '../config/location_constants.dart';

/// Test screen to verify map functionality with shop marker
/// 
/// Phase 1 Tests:
/// - Map loads and renders
/// - Tiles display correctly
/// - Zoom in/out works
/// - Pan/drag works
/// - Attribution is visible
/// 
/// Phase 2 Tests:
/// - Shop marker appears at correct location
/// - Marker is visible and styled correctly
/// - Tap on marker shows info
class TestMapScreen extends StatefulWidget {
  const TestMapScreen({super.key});

  @override
  State<TestMapScreen> createState() => _TestMapScreenState();
}

class _TestMapScreenState extends State<TestMapScreen> {
  late final MapController _mapController;
  bool _showShopMarker = true;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  List<Marker> _getMarkers() {
    if (!_showShopMarker) return [];
    
    return [
      MapMarkers.createShopMarker(
        id: 'infinity_wash_shop',
        position: LocationConstants.infinityWashShop,
        label: 'Hub',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map Test - Phase 2'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_showShopMarker ? Icons.visibility : Icons.visibility_off),
            tooltip: 'Toggle Shop Marker',
            onPressed: () {
              setState(() {
                _showShopMarker = !_showShopMarker;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Info banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.green.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '✅ Phase 2: Shop Marker Test',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Testing: Shop marker appears, styled correctly, at right location',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),

          // Map
          Expanded(
            child: MapWidget(
              center: LocationConstants.infinityWashShop,
              zoom: LocationConstants.defaultZoom,
              markers: _getMarkers(),
              polylines: const [],
              mapController: _mapController,
              onTap: (latLng) {
                // Calculate distance from shop
                final distance = LocationHelper.getFormattedDistance(latLng);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Distance from shop: $distance'),
                    duration: const Duration(seconds: 2),
                  ),
                );
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
                      onPressed: () {
                        _mapController.move(
                          LocationConstants.infinityWashShop,
                          LocationConstants.defaultZoom,
                        );
                      },
                      icon: const Icon(Icons.my_location, size: 16),
                      label: const Text('Center on Shop', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildCheckItem('Blue shop marker visible with "Hub" label'),
                _buildCheckItem('Marker has storefront icon'),
                _buildCheckItem('Marker positioned at Cebu IT Park area'),
                _buildCheckItem('Toggle button hides/shows marker'),
                _buildCheckItem('Tap map shows distance from shop'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      _showTestResultDialog();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Phase 2 Complete ✓'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () {
          _showShopInfoDialog();
        },
        tooltip: 'Shop Info',
        child: const Icon(Icons.info_outline),
      ),
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

  void _showShopInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.storefront, color: Colors.blue, size: 28),
            SizedBox(width: 8),
            Text('Shop Location'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocationConstants.shopName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              LocationConstants.shopAddress,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'Coordinates:\n${LocationConstants.infinityWashShop.latitude.toStringAsFixed(6)}, ${LocationConstants.infinityWashShop.longitude.toStringAsFixed(6)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'TODO: Update with actual shop coordinates in location_constants.dart',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
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
            Text('Phase 2 Complete'),
          ],
        ),
        content: const Text(
          'Shop marker functionality verified!\n\n'
          'Next steps:\n'
          '• Phase 3: Location picker widget\n'
          '• Phase 4: Job marker (hardcoded)\n'
          '• Phase 5: GPS integration',
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
