import 'package:hive_flutter/hive_flutter.dart';
import 'package:latlong2/latlong.dart';

/// Cache service for storing calculated routes
/// Reduces API calls to routing service by caching route calculations
/// 
/// Cache Strategy:
/// - Key: "origin_lat,lon_destination_lat,lon"
/// - Value: Route points + metadata
/// - Expiry: 7 days (routes may change due to road conditions)
class RouteCacheService {
  static const String _boxName = 'routeCache';
  static Box? _box;

  /// Initialize Hive and open the route cache box
  static Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
    
    print('✅ Route cache initialized');
  }

  /// Generate cache key from every waypoint so multi-stop routes do not collide.
  static String _generateKey(List<LatLng> waypoints) {
    if (waypoints.isEmpty) return '';

    return waypoints
        .map((p) =>
            '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}')
        .join('|');
  }

  /// Get cached route if available and not expired
  static Future<List<LatLng>?> getCachedRoute(List<LatLng> waypoints) async {
    await init();
    
    final key = _generateKey(waypoints);
    if (key.isEmpty) return null;

    final cached = _box!.get(key);
    if (cached == null) {
      print('⚠️ Route cache miss for: $key');
      return null;
    }

    // Check expiry
    final cachedData = Map<String, dynamic>.from(cached);
    final cachedAt = DateTime.parse(cachedData['cached_at'] as String);
    final age = DateTime.now().difference(cachedAt);

    if (age.inDays > 7) {
      print('⚠️ Route cache expired (${age.inDays} days old)');
      await _box!.delete(key);
      return null;
    }

    // Parse route points
    final pointsList = List<Map<String, dynamic>>.from(cachedData['points']);
    final points = pointsList.map((p) => LatLng(p['lat'] as double, p['lon'] as double)).toList();

    if (points.length <= waypoints.length) {
      print('⚠️ Ignoring cached straight-line route');
      await _box!.delete(key);
      return null;
    }

    print('✅ Route cache hit! ${points.length} points (${age.inHours}h old)');
    return points;
  }

  /// Cache a calculated route. Straight-line fallbacks are never stored.
  static Future<void> cacheRoute(List<LatLng> waypoints, List<LatLng> routePoints) async {
    await init();
    
    final key = _generateKey(waypoints);
    if (key.isEmpty) return;

    if (routePoints.length <= waypoints.length) {
      print('⚠️ Skipping cache of fallback/straight-line route');
      return;
    }

    final data = {
      'points': routePoints.map((p) => {'lat': p.latitude, 'lon': p.longitude}).toList(),
      'cached_at': DateTime.now().toIso8601String(),
      'waypoint_count': waypoints.length,
      'point_count': routePoints.length,
    };

    await _box!.put(key, data);
    print('✅ Route cached: $key (${routePoints.length} points)');
  }

  /// Get cache statistics
  static Future<Map<String, dynamic>> getCacheStats() async {
    await init();

    final keys = _box!.keys.toList();
    int totalPoints = 0;
    int expiredCount = 0;
    final now = DateTime.now();

    for (var key in keys) {
      final cached = _box!.get(key);
      if (cached != null) {
        final cachedData = Map<String, dynamic>.from(cached);
        totalPoints += cachedData['point_count'] as int;
        
        final cachedAt = DateTime.parse(cachedData['cached_at'] as String);
        if (now.difference(cachedAt).inDays > 7) {
          expiredCount++;
        }
      }
    }

    return {
      'routeCount': keys.length,
      'totalPoints': totalPoints,
      'expiredRoutes': expiredCount,
      'estimatedSizeKB': (totalPoints * 16 / 1024).toStringAsFixed(2), // ~16 bytes per point
    };
  }

  /// Clear all cached routes
  static Future<void> clearCache() async {
    await init();
    await _box!.clear();
    print('🗑️ Route cache cleared');
  }

  /// Remove expired routes (older than 7 days)
  static Future<int> cleanExpiredRoutes() async {
    await init();
    
    final keys = _box!.keys.toList();
    int removedCount = 0;
    final now = DateTime.now();

    for (var key in keys) {
      final cached = _box!.get(key);
      if (cached != null) {
        final cachedData = Map<String, dynamic>.from(cached);
        final cachedAt = DateTime.parse(cachedData['cached_at'] as String);
        
        if (now.difference(cachedAt).inDays > 7) {
          await _box!.delete(key);
          removedCount++;
        }
      }
    }

    if (removedCount > 0) {
      print('🗑️ Removed $removedCount expired routes');
    }
    return removedCount;
  }
}
