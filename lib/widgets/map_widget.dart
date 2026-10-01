import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/location_constants.dart';

/// Reusable map widget using flutter_map and OpenStreetMap tiles
/// 
/// Features:
/// - OpenStreetMap tile layer with proper attribution
/// - Customizable center position and zoom level
/// - Support for markers, polylines, and other layers
/// - 10km delivery radius circle (optional)
/// - Interactive controls (zoom, pan)
class MapWidget extends StatefulWidget {
  final LatLng center;
  final double zoom;
  final List<Marker> markers;
  final List<Polyline> polylines;
  final MapController? mapController;
  final Function(LatLng)? onTap;
  final Function(LatLng)? onLongPress;
  final bool showAttribution;
  final bool showDeliveryRadius;
  final double minZoom;
  final double maxZoom;

  const MapWidget({
    super.key,
    required this.center,
    this.zoom = 13.0,
    this.markers = const [],
    this.polylines = const [],
    this.mapController,
    this.onTap,
    this.onLongPress,
    this.showAttribution = true,
    this.showDeliveryRadius = false,
    this.minZoom = 5.0,
    this.maxZoom = 18.0,
  });

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget> {
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = widget.mapController ?? MapController();
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.center,
        initialZoom: widget.zoom,
        minZoom: widget.minZoom,
        maxZoom: widget.maxZoom,
        onTap: widget.onTap != null
            ? (tapPosition, latLng) => widget.onTap!(latLng)
            : null,
        onLongPress: widget.onLongPress != null
            ? (tapPosition, latLng) => widget.onLongPress!(latLng)
            : null,
      ),
      children: [
        // OpenStreetMap Tile Layer
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.infinitywash.app',
          maxZoom: 19,
          // Tile loading configuration
          tileProvider: NetworkTileProvider(),
        ),

        // Delivery Radius Circle (10km from shop)
        if (widget.showDeliveryRadius)
          CircleLayer(
            circles: [
              CircleMarker(
                point: LocationConstants.infinityWashShop,
                radius: LocationConstants.deliveryRadiusKm * 1000, // Convert km to meters
                useRadiusInMeter: true,
                color: Colors.blue.withValues(alpha: 0.1),
                borderColor: Colors.blue.withValues(alpha: 0.5),
                borderStrokeWidth: 2.0,
              ),
            ],
          ),

        // Polyline Layer (routes)
        if (widget.polylines.isNotEmpty)
          PolylineLayer(
            polylines: widget.polylines,
          ),

        // Marker Layer (pins)
        if (widget.markers.isNotEmpty)
          MarkerLayer(
            markers: widget.markers,
          ),

        // Attribution Layer (required by OpenStreetMap)
        if (widget.showAttribution)
          RichAttributionWidget(
            attributions: [
              TextSourceAttribution(
                'OpenStreetMap contributors',
                onTap: () => _showAttributionDialog(context),
              ),
            ],
          ),
      ],
    );
  }

  void _showAttributionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Map Attribution'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Map Tiles',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text('© OpenStreetMap contributors'),
              SizedBox(height: 8),
              Text(
                'OpenStreetMap is open data, licensed under the Open Data Commons Open Database License (ODbL).',
                style: TextStyle(fontSize: 12),
              ),
              SizedBox(height: 8),
              Text(
                'Learn more at: www.openstreetmap.org/copyright',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ),
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
}

/// Helper class to create common marker styles
class MapMarkers {
  /// Create a marker with a custom icon
  static Marker createMarker({
    required String id,
    required LatLng position,
    required Widget child,
    double width = 40.0,
    double height = 40.0,
    Alignment alignment = Alignment.center,
  }) {
    return Marker(
      point: position,
      width: width,
      height: height,
      alignment: alignment,
      child: child,
    );
  }

  /// Create a pin marker with a label
  static Marker createPinMarker({
    required String id,
    required LatLng position,
    required String label,
    Color color = Colors.blue,
    IconData icon = Icons.location_on,
  }) {
    return createMarker(
      id: id,
      position: position,
      width: 50,
      height: 50,
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          if (label.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color, width: 1),
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
      ),
    );
  }

  /// Create a shop/hub marker
  static Marker createShopMarker({
    required String id,
    required LatLng position,
    String label = 'Hub',
  }) {
    return createPinMarker(
      id: id,
      position: position,
      label: label,
      color: Colors.blue,
      icon: Icons.storefront,
    );
  }

  /// Create a pickup marker
  static Marker createPickupMarker({
    required String id,
    required LatLng position,
    String label = '',
  }) {
    return createPinMarker(
      id: id,
      position: position,
      label: label,
      color: Colors.red,
      icon: Icons.shopping_bag,
    );
  }

  /// Create a delivery marker
  static Marker createDeliveryMarker({
    required String id,
    required LatLng position,
    String label = '',
  }) {
    return createPinMarker(
      id: id,
      position: position,
      label: label,
      color: Colors.orange,
      icon: Icons.delivery_dining,
    );
  }
}

/// Helper class to create polylines for routes
class MapPolylines {
  /// Create a route polyline
  static Polyline createRoute({
    required List<LatLng> points,
    Color color = Colors.blue,
    double strokeWidth = 4.0,
    bool isDashed = false,
  }) {
    return Polyline(
      points: points,
      color: color,
      strokeWidth: strokeWidth,
      // Dashed pattern for fallback routes
      pattern: isDashed
          ? StrokePattern.dashed(segments: [10, 5])
          : StrokePattern.solid(),
    );
  }

  /// Create a primary route (rider to destination)
  static Polyline createPrimaryRoute(List<LatLng> points) {
    return createRoute(
      points: points,
      color: Colors.blue,
      strokeWidth: 5.0,
    );
  }

  /// Create a fallback route (straight line when API fails)
  static Polyline createFallbackRoute(List<LatLng> points) {
    return createRoute(
      points: points,
      color: Colors.grey,
      strokeWidth: 3.0,
      isDashed: true,
    );
  }
}
