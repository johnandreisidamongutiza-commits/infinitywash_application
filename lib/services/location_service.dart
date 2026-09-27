import 'package:location/location.dart';
import 'dart:async';

/// GPS Location Service
/// 
/// Handles all GPS/location functionality with proper error handling:
/// - Permission requests
/// - Service enabled checks
/// - Location updates
/// - Error recovery
/// 
/// Supports both Android and iOS
class LocationService {
  final Location _location = Location();
  StreamSubscription<LocationData>? _locationSubscription;

  /// Check if location service is enabled on the device
  Future<bool> isServiceEnabled() async {
    try {
      return await _location.serviceEnabled();
    } catch (e) {
      print('❌ Error checking service status: $e');
      return false;
    }
  }

  /// Request to enable location service
  /// Returns true if enabled, false if user declined
  Future<bool> requestService() async {
    try {
      return await _location.requestService();
    } catch (e) {
      print('❌ Error requesting service: $e');
      return false;
    }
  }

  /// Check if app has location permission
  Future<bool> hasPermission() async {
    try {
      final permission = await _location.hasPermission();
      return permission == PermissionStatus.granted;
    } catch (e) {
      print('❌ Error checking permission: $e');
      return false;
    }
  }

  /// Request location permission from user
  /// Returns true if granted, false if denied
  Future<bool> requestPermission() async {
    try {
      final permission = await _location.requestPermission();
      return permission == PermissionStatus.granted;
    } catch (e) {
      print('❌ Error requesting permission: $e');
      return false;
    }
  }

  /// Get current location once
  /// Returns null if location cannot be obtained
  Future<LocationData?> getCurrentLocation() async {
    try {
      // Check if service is enabled
      bool serviceEnabled = await isServiceEnabled();
      if (!serviceEnabled) {
        print('⚠️ Location service is disabled');
        serviceEnabled = await requestService();
        if (!serviceEnabled) {
          print('❌ User declined to enable location service');
          return null;
        }
      }

      // Check permission
      bool hasPermission = await this.hasPermission();
      if (!hasPermission) {
        print('⚠️ Location permission not granted');
        hasPermission = await requestPermission();
        if (!hasPermission) {
          print('❌ User declined location permission');
          return null;
        }
      }

      // Get location with timeout
      print('📍 Getting current location...');
      final location = await _location.getLocation().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          print('⏱️ Location request timed out');
          throw TimeoutException('Location request timed out');
        },
      );

      print('✅ Got location: ${location.latitude}, ${location.longitude}');
      return location;
    } on TimeoutException catch (e) {
      print('❌ Timeout getting location: $e');
      return null;
    } catch (e) {
      print('❌ Error getting current location: $e');
      return null;
    }
  }

  /// Start receiving location updates
  /// Calls the callback function with each new location
  /// 
  /// Configure update intervals:
  /// - Android: ~5 seconds / 10 meters by default
  /// - iOS: Best accuracy available
  Future<void> startLocationUpdates(
    Function(LocationData) onLocationUpdate, {
    int? intervalMillis,
    double? distanceFilterMeters,
  }) async {
    try {
      // Stop any existing subscription
      await stopLocationUpdates();

      // Check prerequisites
      final serviceEnabled = await isServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location service is not enabled');
      }

      final hasPermission = await this.hasPermission();
      if (!hasPermission) {
        throw Exception('Location permission not granted');
      }

      // Configure location settings
      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: intervalMillis ?? 5000, // 5 seconds default
        distanceFilter: distanceFilterMeters ?? 10, // 10 meters default
      );

      print('📡 Starting location updates (interval: ${intervalMillis ?? 5000}ms, distance: ${distanceFilterMeters ?? 10}m)');

      // Start listening to location updates
      _locationSubscription = _location.onLocationChanged.listen(
        (LocationData locationData) {
          if (locationData.latitude != null && locationData.longitude != null) {
            print('📍 Location update: ${locationData.latitude}, ${locationData.longitude}');
            onLocationUpdate(locationData);
          }
        },
        onError: (error) {
          print('❌ Location update error: $error');
        },
        cancelOnError: false,
      );

      print('✅ Location updates started successfully');
    } catch (e) {
      print('❌ Error starting location updates: $e');
      rethrow;
    }
  }

  /// Stop receiving location updates
  Future<void> stopLocationUpdates() async {
    if (_locationSubscription != null) {
      print('🛑 Stopping location updates');
      await _locationSubscription?.cancel();
      _locationSubscription = null;
    }
  }

  /// Check if currently tracking location
  bool get isTracking => _locationSubscription != null;
  
  /// Stream of location updates
  Stream<LocationData> get locationStream => _location.onLocationChanged;

  /// Clean up resources
  void dispose() {
    stopLocationUpdates();
  }
}

/// Location service error types
enum LocationErrorType {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  timeout,
  unknown,
}

/// Location service exception
class LocationServiceException implements Exception {
  final LocationErrorType type;
  final String message;

  LocationServiceException(this.type, this.message);

  @override
  String toString() => 'LocationServiceException: $message';

  /// Get user-friendly error message
  String get userMessage {
    switch (type) {
      case LocationErrorType.serviceDisabled:
        return 'Location service is disabled. Please enable it in your device settings.';
      case LocationErrorType.permissionDenied:
        return 'Location permission denied. Please grant permission to use this feature.';
      case LocationErrorType.permissionDeniedForever:
        return 'Location permission permanently denied. Please enable it in app settings.';
      case LocationErrorType.timeout:
        return 'Could not get your location. Please check your GPS signal and try again.';
      case LocationErrorType.unknown:
        return 'An error occurred while accessing your location. Please try again.';
    }
  }
}
