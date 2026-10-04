import 'package:latlong2/latlong.dart';

/// Location Constants for Infinity Wash
/// 
/// This file contains all fixed location coordinates used in the app.

class LocationConstants {
  /// Main Infinity Wash Shop/Hub Location
  /// Bubukal, Sta Cruz, Laguna, Philippines
  static const LatLng infinityWashShop = LatLng(14.2499596, 121.4027956);

  /// Alias for consistency with other parts of the codebase
  static LatLng get shopLocation => infinityWashShop;
  
  /// Delivery radius in meters (for map circles)
  static double get deliveryRadiusMeters => deliveryRadiusKm * 1000;
  
  /// Shop Address (for display purposes)
  static const String shopAddress = 'Infinity Wash Laundry Shop\nBubukal, Sta Cruz, Laguna, Philippines';
  
  /// Shop Name
  static const String shopName = 'Infinity Wash';
  
  /// Shop Contact
  static const String shopPhone = '+63 XXX XXX XXXX'; // Update with actual number
  
  // Additional shop locations can be added here if there are multiple branches
  // Example:
  // static const LatLng infinityWashBranch2 = LatLng(14.xxxx, 121.xxxx);
  
  /// Default map zoom level for shop view
  static const double defaultZoom = 15.0;
  
  /// Zoom level for route overview (to see both shop and destination)
  static const double routeOverviewZoom = 13.0;
  
  /// Delivery service radius in kilometers
  static const double deliveryRadiusKm = 10.0;

  /// Customer & rider meeting area radius in meters around the pinned location
  static const double customerMeetingRadiusMeters = 20.0;
  
  // ========================================
  // TEST DATA (Phase 4)
  // Remove these after Phase 9 when using real dispatch_jobs data
  // ========================================
  
  /// Hardcoded test pickup location (5km north of shop)
  static const LatLng testPickupLocation = LatLng(14.2950, 121.4027);
  
  /// Hardcoded test delivery location (8km south of shop)
  static const LatLng testDeliveryLocation = LatLng(14.2100, 121.4027);
  
  /// Test customer address for display
  static const String testPickupAddress = 'Test Street, Sta Cruz, Laguna';
  
  /// Test delivery address for display
  static const String testDeliveryAddress = 'Sample Ave, Sta Cruz, Laguna';
}

/// Helper class to work with locations
class LocationHelper {
  /// Check if a coordinate is within delivery range
  static bool isWithinDeliveryRange(LatLng location) {
    const Distance distance = Distance();
    final distanceKm = distance.as(
      LengthUnit.Kilometer,
      LocationConstants.infinityWashShop,
      location,
    );
    return distanceKm <= LocationConstants.deliveryRadiusKm;
  }
  
  /// Calculate distance from shop to a location
  static double getDistanceFromShop(LatLng location) {
    const Distance distance = Distance();
    return distance.as(
      LengthUnit.Kilometer,
      LocationConstants.infinityWashShop,
      location,
    );
  }
  
  /// Get formatted distance string
  static String getFormattedDistance(LatLng location) {
    final distanceKm = getDistanceFromShop(location);
    if (distanceKm < 1) {
      return '${(distanceKm * 1000).toStringAsFixed(0)} m';
    }
    return '${distanceKm.toStringAsFixed(1)} km';
  }
}
