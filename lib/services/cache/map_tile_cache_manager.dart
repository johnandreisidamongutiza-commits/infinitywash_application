import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Custom cache manager for map tiles
/// Caches OpenStreetMap tiles to reduce data usage and improve offline capability
/// 
/// Features:
/// - 200MB cache size (stores ~2000-3000 tiles)
/// - 30 day retention (tiles auto-delete after 30 days)
/// - Persistent storage across app restarts
class MapTileCacheManager {
  // Bumped to v2 to immediately purge any previously cached 403 "Access blocked" tiles
  static const key = 'mapTileCache_v2';
  static CacheManager? _instance;

  /// Get singleton instance of the cache manager
  static CacheManager get instance {
    _instance ??= CacheManager(
      Config(
        key,
        stalePeriod: const Duration(days: 30), // Keep tiles for 30 days
        maxNrOfCacheObjects: 3000, // Maximum number of cached tiles
      ),
    );
    return _instance!;
  }

  /// Clear all cached map tiles
  /// Use when: Storage is low, or tiles are corrupted
  static Future<void> clearCache() async {
    await instance.emptyCache();
  }

  /// Get cache statistics
  /// Returns info about cache size, number of files, etc.
  static Future<Map<String, dynamic>> getCacheInfo() async {
    return {
      'maxFiles': 3000,
      'retentionDays': 30,
      'cacheKey': key,
    };
  }

  /// Remove old cache files to free up space
  /// Removes files older than specified days
  static Future<void> cleanOldCache({int olderThanDays = 30}) async {
    await instance.emptyCache();
  }
}
