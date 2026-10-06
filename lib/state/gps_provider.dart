import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:latlong2/latlong.dart';
import '../utils/app_error.dart';
import '../utils/permission_manager.dart';
import '../services/location_service.dart';

/// Provider for managing GPS location state
/// Handles permission requests, location updates, and error states
class GpsProvider with ChangeNotifier {
  final LocationService _locationService = LocationService();

  LatLng? _currentLocation;
  bool _isTracking = false;
  String? _errorMessage;
  bool _hasPermission = false;
  bool _isServiceEnabled = false;

  // Getters
  LatLng? get currentLocation => _currentLocation;
  bool get isTracking => _isTracking;
  String? get errorMessage => _errorMessage;
  bool get hasPermission => _hasPermission;
  bool get isServiceEnabled => _isServiceEnabled;
  bool get isReady => _hasPermission && _isServiceEnabled && _currentLocation != null;
  
  /// Stream of location updates
  Stream<LocationData> get locationStream => _locationService.locationStream;

  /// BuildContext used to show the purpose-explanation and denial dialogs.
  /// Optional: when null, permission requests fall back to a bare OS prompt.
  BuildContext? _uiContext;
  void attachDialogContext(BuildContext context) => _uiContext = context;

  /// Initialize GPS service and check permissions
  Future<void> initialize() async {
    try {
      _errorMessage = null;
      
      // Check if location service is enabled
      _isServiceEnabled = await _locationService.isServiceEnabled();
      if (!_isServiceEnabled) {
        _errorMessage = 'Location service is disabled. Please enable it in settings.';
        notifyListeners();
        return;
      }

      // Check and request permission — with a purpose explanation before
      // the OS dialog and denial guidance (incl. Settings deep link) after.
      _hasPermission = await _locationService.hasPermission();
      if (!_hasPermission && _uiContext != null) {
        _hasPermission = await PermissionManager.ensure(
          _uiContext!,
          AppPermission.location,
          check: () => _locationService.hasPermission(),
          request: _locationService.requestPermissionDetailed,
        );
      } else if (!_hasPermission) {
        // No UI context available: fall back to a bare OS request.
        _hasPermission = await _locationService.requestPermission();
      }
      if (!_hasPermission) {
        _errorMessage = 'Location permission denied. Please enable it in app settings.';
        notifyListeners();
        return;
      }

      // Get initial location
      final initialLocation = await _locationService.getCurrentLocation();
      if (initialLocation != null) {
        _currentLocation = LatLng(initialLocation.latitude!, initialLocation.longitude!);
      }

      notifyListeners();
    } catch (e) {
      _errorMessage = mapErrorToMessage(e);
      notifyListeners();
    }
  }

  /// Start tracking location updates
  Future<void> startTracking() async {
    if (_isTracking) return;

    try {
      _isTracking = true;
      _errorMessage = null;
      notifyListeners();

      await _locationService.startLocationUpdates((locationData) {
        if (locationData.latitude != null && locationData.longitude != null) {
          _currentLocation = LatLng(locationData.latitude!, locationData.longitude!);
          notifyListeners();
        }
      });
    } catch (e) {
      _isTracking = false;
      _errorMessage = mapErrorToMessage(e);
      notifyListeners();
    }
  }

  /// Stop tracking location updates
  void stopTracking() {
    if (!_isTracking) return;

    _locationService.stopLocationUpdates();
    _isTracking = false;
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}
