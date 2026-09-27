import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/location_constants.dart';

/// Interactive location picker widget
/// 
/// Allows users to drop a pin on the map to select a location.
/// Used when creating dispatch jobs to capture exact coordinates.
/// 
/// Features:
/// - Tap to place pin
/// - Drag pin to adjust position
/// - Shows distance from shop
/// - Returns LatLng coordinates
/// - Validates delivery range
class LocationPickerWidget extends StatefulWidget {
  /// Initial position for the pin (defaults to shop location)
  final LatLng? initialPosition;
  
  /// Whether to enforce delivery radius
  final bool enforceDeliveryRadius;
  
  /// Callback when location is selected/changed
  final Function(LatLng)? onLocationChanged;
  
  /// Whether to show the shop marker
  final bool showShopMarker;

  const LocationPickerWidget({
    super.key,
    this.initialPosition,
    this.enforceDeliveryRadius = true,
    this.onLocationChanged,
    this.showShopMarker = true,
  });

  @override
  State<LocationPickerWidget> createState() => _LocationPickerWidgetState();
}

class _LocationPickerWidgetState extends State<LocationPickerWidget> {
  late MapController _mapController;
  LatLng? _selectedLocation;
  bool _isOutOfRange = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _selectedLocation = widget.initialPosition;
    _checkDeliveryRange();
  }

  void _checkDeliveryRange() {
    if (_selectedLocation != null && widget.enforceDeliveryRadius) {
      _isOutOfRange = !LocationHelper.isWithinDeliveryRange(_selectedLocation!);
    } else {
      _isOutOfRange = false;
    }
  }

  void _onMapTap(LatLng latLng) {
    setState(() {
      _selectedLocation = latLng;
      _checkDeliveryRange();
    });
    widget.onLocationChanged?.call(latLng);
  }

  String _getDistanceText() {
    if (_selectedLocation == null) return '';
    return LocationHelper.getFormattedDistance(_selectedLocation!);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Instructions banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isOutOfRange ? Colors.red.shade50 : Colors.blue.shade50,
            border: Border(
              bottom: BorderSide(
                color: _isOutOfRange ? Colors.red.shade200 : Colors.blue.shade200,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isOutOfRange ? Icons.warning_amber : Icons.info_outline,
                size: 20,
                color: _isOutOfRange ? Colors.red : Colors.blue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedLocation == null
                          ? 'Tap on the map to select a location'
                          : _isOutOfRange
                              ? 'Location is outside delivery range'
                              : 'Location selected',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _isOutOfRange ? Colors.red.shade900 : Colors.blue.shade900,
                      ),
                    ),
                    if (_selectedLocation != null)
                      Text(
                        'Distance from shop: ${_getDistanceText()}',
                        style: TextStyle(
                          fontSize: 11,
                          color: _isOutOfRange ? Colors.red.shade700 : Colors.grey.shade700,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Map
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _selectedLocation ?? LocationConstants.infinityWashShop,
                  initialZoom: 15.0,
                  minZoom: 10.0,
                  maxZoom: 18.0,
                  onTap: (tapPosition, latLng) => _onMapTap(latLng),
                ),
                children: [
                  // Tile layer
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.infinitywash.app',
                  ),

                  // Delivery radius circle (optional)
                  if (widget.enforceDeliveryRadius && widget.showShopMarker)
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: LocationConstants.infinityWashShop,
                          radius: LocationConstants.deliveryRadiusKm * 1000, // Convert to meters
                          useRadiusInMeter: true,
                          color: Colors.blue.withOpacity(0.1),
                          borderColor: Colors.blue.withOpacity(0.3),
                          borderStrokeWidth: 2,
                        ),
                      ],
                    ),

                  // Markers layer
                  MarkerLayer(
                    markers: [
                      // Shop marker
                      if (widget.showShopMarker)
                        Marker(
                          point: LocationConstants.infinityWashShop,
                          width: 40,
                          height: 40,
                          alignment: Alignment.topCenter,
                          child: const Icon(
                            Icons.storefront,
                            color: Colors.blue,
                            size: 32,
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),

                      // Selected location pin
                      if (_selectedLocation != null)
                        Marker(
                          point: _selectedLocation!,
                          width: 50,
                          height: 50,
                          alignment: Alignment.topCenter,
                          child: Icon(
                            Icons.location_on,
                            color: _isOutOfRange ? Colors.red : Colors.green,
                            size: 50,
                            shadows: const [
                              Shadow(
                                color: Colors.black38,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                    ],
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
              ),

              // Center crosshair (visual aid)
              if (_selectedLocation == null)
                Center(
                  child: Icon(
                    Icons.add,
                    size: 32,
                    color: Colors.grey.withOpacity(0.5),
                  ),
                ),
            ],
          ),
        ),

        // Location info footer
        if (_selectedLocation != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
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
                const Text(
                  'Selected Coordinates:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        _mapController.move(
                          LocationConstants.infinityWashShop,
                          LocationConstants.defaultZoom,
                        );
                      },
                      icon: const Icon(Icons.my_location, size: 16),
                      label: const Text('Shop', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedLocation = null;
                          _isOutOfRange = false;
                        });
                        widget.onLocationChanged?.call(LocationConstants.infinityWashShop);
                      },
                      icon: const Icon(Icons.clear, size: 16),
                      label: const Text('Clear', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Dialog wrapper for location picker
/// 
/// Use this to show the location picker as a dialog and get the result
class LocationPickerDialog {
  static Future<LatLng?> show(
    BuildContext context, {
    LatLng? initialPosition,
    bool enforceDeliveryRadius = true,
    String title = 'Select Location',
  }) async {
    LatLng? selectedLocation = initialPosition;

    final result = await showDialog<LatLng?>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Location picker
              Expanded(
                child: LocationPickerWidget(
                  initialPosition: initialPosition,
                  enforceDeliveryRadius: enforceDeliveryRadius,
                  onLocationChanged: (latLng) {
                    selectedLocation = latLng;
                  },
                ),
              ),

              // Footer buttons
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: selectedLocation != null
                          ? () => Navigator.of(context).pop(selectedLocation)
                          : null,
                      child: const Text('Confirm Location'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return result;
  }
}
