import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/location_constants.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';

/// Interactive location picker widget
///
/// Allows users to drop a pin on the map to select a location.
/// Used during registration, customer profile, and dispatch jobs.
///
/// Features:
/// - Tap anywhere to place or move pin
/// - "My Location" GPS button to automatically zoom to current device position
/// - Shows distance from shop and delivery radius status
/// - Returns LatLng coordinates
/// - Validates delivery range
class LocationPickerWidget extends StatefulWidget {
  /// Initial position for the pin (defaults to shop location or null)
  final LatLng? initialPosition;

  /// Whether to enforce delivery radius
  final bool enforceDeliveryRadius;

  /// Callback when location is selected/changed (passes null if cleared)
  final void Function(LatLng?)? onLocationChanged;

  /// Whether to show the shop marker
  final bool showShopMarker;

  /// Whether to show the bottom location info footer
  final bool showFooter;

  const LocationPickerWidget({
    super.key,
    this.initialPosition,
    this.enforceDeliveryRadius = true,
    this.onLocationChanged,
    this.showShopMarker = true,
    this.showFooter = true,
  });

  @override
  State<LocationPickerWidget> createState() => _LocationPickerWidgetState();
}

class _LocationPickerWidgetState extends State<LocationPickerWidget> {
  late final MapController _mapController;
  LatLng? _selectedLocation;
  bool _isOutOfRange = false;
  bool _isLocating = false;

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

  Future<void> _locateUser() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);

    try {
      final locationData = await LocationService().getCurrentLocation();
      if (!mounted) return;

      if (locationData != null &&
          locationData.latitude != null &&
          locationData.longitude != null) {
        final userLatLng = LatLng(locationData.latitude!, locationData.longitude!);
        _mapController.move(userLatLng, 16.0);
        _onMapTap(userLatLng);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not access current location. Please check device permissions.'),
            backgroundColor: AppTheme.errorRed,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location: $e'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _clearLocation() {
    setState(() {
      _selectedLocation = null;
      _isOutOfRange = false;
    });
    widget.onLocationChanged?.call(null);
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                _isOutOfRange ? Icons.warning_amber_rounded : Icons.info_outline,
                size: 20,
                color: _isOutOfRange ? AppTheme.errorRed : AppTheme.accentBlue,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedLocation == null
                          ? 'Tap anywhere on map or tap GPS button to pin'
                          : _isOutOfRange
                              ? 'Location is outside delivery range'
                              : 'Pin placed successfully',
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
                          radius: LocationConstants.deliveryRadiusKm * 1000,
                          useRadiusInMeter: true,
                          color: Colors.blue.withValues(alpha: 0.08),
                          borderColor: Colors.blue.withValues(alpha: 0.35),
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
                          width: 44,
                          height: 44,
                          alignment: Alignment.topCenter,
                          child: const Icon(
                            Icons.storefront,
                            color: AppTheme.primaryBlue,
                            size: 34,
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
                            color: _isOutOfRange ? AppTheme.errorRed : Colors.green.shade600,
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

              // Center crosshair (visual aid - ignores pointers so taps reach the map)
              if (_selectedLocation == null)
                Center(
                  child: IgnorePointer(
                    child: Icon(
                      Icons.add,
                      size: 36,
                      color: Colors.black.withValues(alpha: 0.4),
                    ),
                  ),
                ),

              // Floating map action controls (Locate GPS & Shop)
              Positioned(
                top: 12,
                right: 12,
                child: Column(
                  children: [
                    // Locate Me GPS
                    Material(
                      elevation: 3,
                      shape: const CircleBorder(),
                      color: Colors.white,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _isLocating ? null : _locateUser,
                        child: Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: _isLocating
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.2),
                                )
                              : const Icon(
                                  Icons.my_location,
                                  color: AppTheme.accentBlue,
                                  size: 22,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Recenter Shop
                    Material(
                      elevation: 3,
                      shape: const CircleBorder(),
                      color: Colors.white,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          _mapController.move(
                            LocationConstants.infinityWashShop,
                            LocationConstants.defaultZoom,
                          );
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(10.0),
                          child: Icon(
                            Icons.storefront,
                            color: AppTheme.primaryBlue,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Optional footer for standalone mode
        if (widget.showFooter)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedLocation != null ? 'Coordinates:' : 'No pin placed',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textLight,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _selectedLocation != null
                            ? '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}'
                            : 'Tap on the map to drop a pin',
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: _selectedLocation != null ? 'monospace' : null,
                          color: _selectedLocation != null ? AppTheme.textDark : AppTheme.textLight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _isLocating ? null : _locateUser,
                  icon: const Icon(Icons.my_location, size: 16),
                  label: const Text('Locate', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accentBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () {
                    _mapController.move(
                      LocationConstants.infinityWashShop,
                      LocationConstants.defaultZoom,
                    );
                  },
                  icon: const Icon(Icons.storefront, size: 16),
                  label: const Text('Shop', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.textDark,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                if (_selectedLocation != null) ...[
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: _clearLocation,
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Clear', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.errorRed,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Modal wrapper for location picker
///
/// Uses a fullscreen [MaterialPageRoute] with [Scaffold] for a smooth,
/// responsive map experience with zero layout or clipping assertion issues.
class LocationPickerDialog {
  static Future<LatLng?> show(
    BuildContext context, {
    LatLng? initialPosition,
    bool enforceDeliveryRadius = true,
    String title = 'Pin Your Location',
  }) {
    return Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _LocationPickerScreen(
          initialPosition: initialPosition,
          enforceDeliveryRadius: enforceDeliveryRadius,
          title: title,
        ),
      ),
    );
  }
}

class _LocationPickerScreen extends StatefulWidget {
  final LatLng? initialPosition;
  final bool enforceDeliveryRadius;
  final String title;

  const _LocationPickerScreen({
    this.initialPosition,
    this.enforceDeliveryRadius = true,
    this.title = 'Pin Your Location',
  });

  @override
  State<_LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<_LocationPickerScreen> {
  late LatLng? _selectedLocation;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialPosition;
  }

  @override
  Widget build(BuildContext context) {
    final isOutOfRange = _selectedLocation != null &&
        widget.enforceDeliveryRadius &&
        !LocationHelper.isWithinDeliveryRange(_selectedLocation!);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_selectedLocation != null)
            TextButton(
              onPressed: () {
                setState(() => _selectedLocation = null);
              },
              child: const Text(
                'Clear',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
      body: LocationPickerWidget(
        initialPosition: widget.initialPosition,
        enforceDeliveryRadius: widget.enforceDeliveryRadius,
        showFooter: false,
        onLocationChanged: (latLng) {
          setState(() {
            _selectedLocation = latLng;
          });
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    _selectedLocation == null
                        ? Icons.touch_app_outlined
                        : isOutOfRange
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                    size: 20,
                    color: _selectedLocation == null
                        ? AppTheme.accentBlue
                        : isOutOfRange
                            ? AppTheme.errorRed
                            : Colors.green.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _selectedLocation == null
                              ? 'Tap map or GPS to set your location'
                              : isOutOfRange
                                  ? 'Outside delivery range'
                                  : 'Within delivery range',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _selectedLocation == null
                                ? AppTheme.textDark
                                : isOutOfRange
                                    ? AppTheme.errorRed
                                    : Colors.green.shade800,
                          ),
                        ),
                        if (_selectedLocation != null)
                          Text(
                            '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)} • ${LocationHelper.getFormattedDistance(_selectedLocation!)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textLight,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade600,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _selectedLocation != null
                      ? () => Navigator.of(context).pop(_selectedLocation)
                      : null,
                  child: const Text(
                    'Confirm Location',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
