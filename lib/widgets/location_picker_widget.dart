import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/location_constants.dart';
import '../services/geocoding_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';

/// Result object returned by [LocationPickerDialog.show].
class LocationPickResult {
  final LatLng coordinates;
  final String? address;

  const LocationPickResult({
    required this.coordinates,
    this.address,
  });

  double get latitude => coordinates.latitude;
  double get longitude => coordinates.longitude;
}

/// Interactive location picker widget
///
/// Allows users to search for an address, drop a pin on the map,
/// or use GPS to select their location.
///
/// Features:
/// - Search bar with live address/landmark autocompletion (OpenStreetMap Nominatim)
/// - Tap anywhere on the map to place or adjust the pin
/// - "My Location" GPS button to automatically zoom to current device position
/// - Shows distance from shop and delivery radius status
/// - Validates delivery range
class LocationPickerWidget extends StatefulWidget {
  /// Initial position for the pin (defaults to shop location or null)
  final LatLng? initialPosition;

  /// Whether to enforce delivery radius
  final bool enforceDeliveryRadius;

  /// Callback when location is selected/changed (passes null if cleared)
  final void Function(LatLng?)? onLocationChanged;

  /// Callback when location and its resolved address are selected
  final void Function(LatLng?, String?)? onLocationWithAddressChanged;

  /// Whether to show the shop marker
  final bool showShopMarker;

  /// Whether to show the bottom location info footer
  final bool showFooter;

  const LocationPickerWidget({
    super.key,
    this.initialPosition,
    this.enforceDeliveryRadius = true,
    this.onLocationChanged,
    this.onLocationWithAddressChanged,
    this.showShopMarker = true,
    this.showFooter = true,
  });

  @override
  State<LocationPickerWidget> createState() => _LocationPickerWidgetState();
}

class _LocationPickerWidgetState extends State<LocationPickerWidget> {
  late final MapController _mapController;
  LatLng? _selectedLocation;
  String? _resolvedAddress;
  bool _isOutOfRange = false;
  bool _isLocating = false;
  bool _isResolvingAddress = false;

  // Address search state
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounceTimer;
  List<GeocodingResult> _searchResults = [];
  bool _isSearching = false;
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _selectedLocation = widget.initialPosition;
    _checkDeliveryRange();
    if (_selectedLocation != null) {
      _resolveAddress(_selectedLocation!);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _checkDeliveryRange() {
    if (_selectedLocation != null && widget.enforceDeliveryRadius) {
      _isOutOfRange = !LocationHelper.isWithinDeliveryRange(_selectedLocation!);
    } else {
      _isOutOfRange = false;
    }
  }

  Future<void> _resolveAddress(LatLng latLng) async {
    setState(() => _isResolvingAddress = true);
    final addr = await GeocodingService().reverseGeocode(latLng.latitude, latLng.longitude);
    if (!mounted) return;
    if (_selectedLocation == latLng) {
      setState(() {
        _resolvedAddress = addr;
        _isResolvingAddress = false;
      });
      widget.onLocationWithAddressChanged?.call(latLng, addr);
    }
  }

  void _onMapTap(LatLng latLng) {
    if (_showSuggestions) {
      setState(() => _showSuggestions = false);
      _searchFocusNode.unfocus();
    }
    setState(() {
      _selectedLocation = latLng;
      _resolvedAddress = null;
      _checkDeliveryRange();
    });
    widget.onLocationChanged?.call(latLng);
    _resolveAddress(latLng);
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();

    if (trimmed.length < 3) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _showSuggestions = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _showSuggestions = true;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 450), () async {
      final results = await GeocodingService().search(trimmed);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    });
  }

  void _selectSearchResult(GeocodingResult result) {
    final latLng = LatLng(result.latitude, result.longitude);
    final addressText = result.title + (result.subtitle.isNotEmpty ? ', ${result.subtitle}' : '');

    _searchFocusNode.unfocus();
    _searchController.text = result.title;
    setState(() {
      _showSuggestions = false;
      _selectedLocation = latLng;
      _resolvedAddress = addressText;
      _isResolvingAddress = false;
      _checkDeliveryRange();
    });
    _mapController.move(latLng, 16.5);
    widget.onLocationChanged?.call(latLng);
    widget.onLocationWithAddressChanged?.call(latLng, addressText);
  }

  Future<void> _locateUser() async {
    if (_isLocating) return;
    setState(() {
      _isLocating = true;
      _showSuggestions = false;
    });
    _searchFocusNode.unfocus();

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
    _searchController.clear();
    setState(() {
      _selectedLocation = null;
      _resolvedAddress = null;
      _isOutOfRange = false;
      _showSuggestions = false;
      _searchResults = [];
    });
    widget.onLocationChanged?.call(null);
    widget.onLocationWithAddressChanged?.call(null, null);
  }

  String _getDistanceText() {
    if (_selectedLocation == null) return '';
    return LocationHelper.getFormattedDistance(_selectedLocation!);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Instructions & Delivery range banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                size: 18,
                color: _isOutOfRange ? AppTheme.errorRed : AppTheme.accentBlue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedLocation == null
                      ? 'Search your address, tap the map, or use GPS to pin'
                      : _isOutOfRange
                          ? 'Outside delivery range (${_getDistanceText()} from shop)'
                          : 'Within delivery range (${_getDistanceText()} from shop)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _isOutOfRange ? Colors.red.shade900 : Colors.blue.shade900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // Map with overlays
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _selectedLocation ?? LocationConstants.infinityWashShop,
                  initialZoom: 15.0,
                  minZoom: 12.0,
                  maxZoom: 18.0,
                  cameraConstraint: CameraConstraint.contain(
                    bounds: LatLngBounds(
                      LatLng(
                        LocationConstants.shopLocation.latitude - 0.15,
                        LocationConstants.shopLocation.longitude - 0.15,
                      ),
                      LatLng(
                        LocationConstants.shopLocation.latitude + 0.15,
                        LocationConstants.shopLocation.longitude + 0.15,
                      ),
                    ),
                  ),
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
                      color: Colors.black.withValues(alpha: 0.35),
                    ),
                  ),
                ),

              // Floating map action controls (Locate GPS & Shop at bottom-right)
              Positioned(
                bottom: 16,
                right: 12,
                child: Column(
                  children: [
                    // Locate Me GPS button
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
                    // Recenter Shop button
                    Material(
                      elevation: 3,
                      shape: const CircleBorder(),
                      color: Colors.white,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          _searchFocusNode.unfocus();
                          setState(() => _showSuggestions = false);
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

              // Floating Search Bar & Auto-complete suggestions at top of the map
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      elevation: 3,
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onChanged: _onSearchChanged,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) {
                          if (_searchResults.isNotEmpty) {
                            _selectSearchResult(_searchResults.first);
                          }
                        },
                        decoration: InputDecoration(
                          hintText: 'Search street, barangay, or landmark in Laguna...',
                          hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textLight),
                          prefixIcon: const Icon(Icons.search, color: AppTheme.accentBlue, size: 20),
                          suffixIcon: _isSearching
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.close, size: 18, color: AppTheme.textLight),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {
                                          _searchResults = [];
                                          _showSuggestions = false;
                                        });
                                      },
                                    )
                                  : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),

                    // Suggestion dropdown
                    if (_showSuggestions) ...[
                      const SizedBox(height: 6),
                      Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: _searchResults.isEmpty && !_isSearching
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  child: Row(
                                    children: [
                                      Icon(Icons.location_off_outlined, size: 18, color: AppTheme.textLight),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'No matching places found. Try a different keyword or tap the map directly.',
                                          style: TextStyle(fontSize: 12, color: AppTheme.textLight),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  shrinkWrap: true,
                                  itemCount: _searchResults.length,
                                  separatorBuilder: (c, i) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final item = _searchResults[index];
                                    return ListTile(
                                      dense: true,
                                      leading: const Icon(
                                        Icons.location_on_outlined,
                                        color: AppTheme.accentBlue,
                                        size: 20,
                                      ),
                                      title: Text(
                                        item.title,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textDark,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: item.subtitle.isNotEmpty
                                          ? Text(
                                              item.subtitle,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppTheme.textLight,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            )
                                          : null,
                                      onTap: () => _selectSearchResult(item),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
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
                        _selectedLocation != null
                            ? (_isResolvingAddress ? 'Finding address name...' : (_resolvedAddress ?? 'Selected Location'))
                            : 'No pin placed',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _selectedLocation != null
                            ? '${_selectedLocation!.latitude.toStringAsFixed(5)}, ${_selectedLocation!.longitude.toStringAsFixed(5)} • ${_getDistanceText()}'
                            : 'Tap on the map or search to drop a pin',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textLight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
  static Future<LocationPickResult?> show(
    BuildContext context, {
    LatLng? initialPosition,
    bool enforceDeliveryRadius = true,
    String title = 'Pin Your Location',
  }) {
    return Navigator.of(context).push<LocationPickResult>(
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
  String? _selectedAddress;
  bool _isResolvingAddress = false;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialPosition;
    if (_selectedLocation != null) {
      _resolveInitialAddress(_selectedLocation!);
    }
  }

  Future<void> _resolveInitialAddress(LatLng latLng) async {
    setState(() => _isResolvingAddress = true);
    final addr = await GeocodingService().reverseGeocode(latLng.latitude, latLng.longitude);
    if (!mounted) return;
    if (_selectedLocation == latLng) {
      setState(() {
        _selectedAddress = addr;
        _isResolvingAddress = false;
      });
    }
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
                setState(() {
                  _selectedLocation = null;
                  _selectedAddress = null;
                });
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
            _selectedAddress = null;
            if (latLng != null) {
              _isResolvingAddress = true;
            }
          });
        },
        onLocationWithAddressChanged: (latLng, address) {
          if (mounted && _selectedLocation == latLng) {
            setState(() {
              _selectedAddress = address;
              _isResolvingAddress = false;
            });
          }
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
                              ? 'Search or tap on the map to pin'
                              : isOutOfRange
                                  ? 'Outside delivery zone (maximum ${LocationConstants.deliveryRadiusKm.toInt()} km from shop)'
                                  : _isResolvingAddress
                                      ? 'Finding address name...'
                                      : (_selectedAddress ?? 'Selected Location'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _selectedLocation == null
                                ? AppTheme.textDark
                                : isOutOfRange
                                    ? AppTheme.errorRed
                                    : Colors.green.shade800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_selectedLocation != null)
                          Text(
                            '${LocationHelper.getFormattedDistance(_selectedLocation!)} from shop • (${_selectedLocation!.latitude.toStringAsFixed(5)}, ${_selectedLocation!.longitude.toStringAsFixed(5)})',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textLight,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                  onPressed: (_selectedLocation != null && (!widget.enforceDeliveryRadius || !isOutOfRange))
                      ? () => Navigator.of(context).pop(
                            LocationPickResult(
                              coordinates: _selectedLocation!,
                              address: _selectedAddress,
                            ),
                          )
                      : null,
                  child: Text(
                    isOutOfRange && widget.enforceDeliveryRadius
                        ? 'Outside Delivery Zone'
                        : 'Confirm Location',
                    style: const TextStyle(
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
