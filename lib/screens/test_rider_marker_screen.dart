import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../widgets/map_widget.dart';
import '../config/location_constants.dart';
import '../state/gps_provider.dart';

/// Test screen for Phase 6: Rider Marker
/// 
/// Tests:
/// - Live rider location marker displays
/// - Marker follows GPS updates in real-time
/// - Marker styling and appearance
/// - Integration with GpsProvider
/// - Marker updates smoothly as device moves
class TestRiderMarkerScreen extends StatefulWidget {
  const TestRiderMarkerScreen({super.key});

  @override
  State<TestRiderMarkerScreen> createState() => _TestRiderMarkerScreenState();
}

class _TestRiderMarkerScreenState extends State<TestRiderMarkerScreen> {
  late final MapController _mapController;
  late final GpsProvider _gpsProvider;
  bool _followUser = true;
  bool _showShop = true;
  int _updateCount = 0;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _gpsProvider = GpsProvider();
    _initializeGps();
  }

  Future<void> _initializeGps() async {
    try {
      await _gpsProvider.initialize();
      
      if (_gpsProvider.hasPermission && _gpsProvider.isServiceEnabled) {
        await _gpsProvider.startTracking();
        
        // Listen to location changes
        _gpsProvider.addListener(_onLocationUpdate);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onLocationUpdate() {
    setState(() {
      _updateCount++;
    });
    
    // Center map on user location if follow mode is enabled
    if (_followUser && _gpsProvider.currentLocation != null) {
      _mapController.move(_gpsProvider.currentLocation!, 16.0);
    }
  }

  @override
  void dispose() {
    _gpsProvider.removeListener(_onLocationUpdate);
    _gpsProvider.stopTracking();
    _gpsProvider.dispose();
    super.dispose();
  }

  List<Marker> _getStaticMarkers() {
    if (!_showShop) return [];
    
    return [
      MapMarkers.createShopMarker(
        id: 'shop',
        position: LocationConstants.infinityWashShop,
        label: 'Hub',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _gpsProvider,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Rider Marker Test - Phase 6'),
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: Icon(_followUser ? Icons.gps_fixed : Icons.gps_not_fixed),
              tooltip: _followUser ? 'Following User' : 'Free Movement',
              onPressed: () {
                setState(() {
                  _followUser = !_followUser;
                });
              },
            ),
            IconButton(
              icon: Icon(_showShop ? Icons.visibility : Icons.visibility_off),
              tooltip: 'Toggle Shop Marker',
              onPressed: () {
                setState(() {
                  _showShop = !_showShop;
                });
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // Info banner
            Consumer<GpsProvider>(
              builder: (context, gps, child) {
                Color bannerColor;
                String statusText;
                IconData statusIcon;

                if (gps.errorMessage != null) {
                  bannerColor = Colors.red.shade50;
                  statusText = gps.errorMessage!;
                  statusIcon = Icons.error;
                } else if (!gps.hasPermission) {
                  bannerColor = Colors.orange.shade50;
                  statusText = 'Location permission required';
                  statusIcon = Icons.warning;
                } else if (!gps.isServiceEnabled) {
                  bannerColor = Colors.orange.shade50;
                  statusText = 'GPS service disabled';
                  statusIcon = Icons.gps_off;
                } else if (gps.isTracking) {
                  bannerColor = Colors.green.shade50;
                  statusText = 'Tracking active • Updates: $_updateCount';
                  statusIcon = Icons.check_circle;
                } else {
                  bannerColor = Colors.blue.shade50;
                  statusText = 'Ready to track';
                  statusIcon = Icons.info_outline;
                }

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: bannerColor,
                  child: Row(
                    children: [
                      Icon(statusIcon, size: 20, color: Colors.grey.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '✅ Phase 6: Rider Marker Test',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Map
            Expanded(
              child: Consumer<GpsProvider>(
                builder: (context, gps, child) {
                  final center = gps.currentLocation ?? LocationConstants.infinityWashShop;
                  
                  return FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 16.0,
                      minZoom: 10.0,
                      maxZoom: 18.0,
                    ),
                    children: [
                      // Tile layer
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.infinitywash.app',
                      ),

                      // Static markers (shop)
                      if (_showShop)
                        MarkerLayer(
                          markers: _getStaticMarkers(),
                        ),

                      // Live location marker
                      CurrentLocationLayer(
                        alignPositionOnUpdate: _followUser ? AlignOnUpdate.always : AlignOnUpdate.never,
                        alignDirectionOnUpdate: AlignOnUpdate.never,
                        style: const LocationMarkerStyle(
                          marker: DefaultLocationMarker(
                            color: Colors.blue,
                            child: Icon(
                              Icons.navigation,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          markerSize: Size(40, 40),
                          markerDirection: MarkerDirection.heading,
                          accuracyCircleColor: Color.fromARGB(50, 33, 150, 243),
                          headingSectorColor: Color.fromARGB(150, 33, 150, 243),
                          headingSectorRadius: 60,
                        ),
                      ),

                      // Attribution
                      RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution(
                            'OpenStreetMap contributors',
                            onTap: () {},
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),

            // Location info footer
            Consumer<GpsProvider>(
              builder: (context, gps, child) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
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
                          Row(
                            children: [
                              if (_followUser)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.gps_fixed, size: 12, color: Colors.blue),
                                      SizedBox(width: 4),
                                      Text(
                                        'Following',
                                        style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () {
                                  if (gps.currentLocation != null) {
                                    _mapController.move(gps.currentLocation!, 16.0);
                                  }
                                },
                                icon: const Icon(Icons.my_location, size: 16),
                                label: const Text('Center', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildCheckItem('Blue rider marker visible on map'),
                      _buildCheckItem('Marker shows navigation icon'),
                      _buildCheckItem('Accuracy circle appears around marker'),
                      _buildCheckItem('Marker updates when device moves'),
                      _buildCheckItem('Follow mode keeps marker centered'),
                      if (gps.currentLocation != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Current Location:',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${gps.currentLocation!.latitude.toStringAsFixed(6)}, ${gps.currentLocation!.longitude.toStringAsFixed(6)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: gps.isReady ? _showTestResultDialog : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade300,
                          ),
                          child: Text(
                            gps.isReady
                                ? 'Phase 6 Complete ✓'
                                : 'Enable GPS to continue',
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
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

  void _showTestResultDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('Phase 6 Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rider marker functionality verified!'),
            const SizedBox(height: 16),
            const Text(
              'What was tested:\n'
              '✓ Live location marker displays\n'
              '✓ Marker follows GPS updates\n'
              '✓ Navigation icon and accuracy circle\n'
              '✓ Follow mode keeps marker centered\n'
              '✓ Updates smoothly as device moves',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Text(
              'Next steps:\n'
              '• Phase 7: Routing service\n'
              '• Phase 8: Polyline rendering\n'
              '• Phase 9: Supabase integration',
              style: TextStyle(fontSize: 12),
            ),
          ],
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
