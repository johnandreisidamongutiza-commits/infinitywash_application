import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/dispatch_job.dart';

/// Cache service for dispatch jobs
/// Provides offline access to job data when network is unavailable
/// 
/// Safety Features:
/// - READ-ONLY cache (no direct writes)
/// - Auto-refresh from Supabase
/// - Timestamp tracking for staleness detection
/// - No database conflicts (Supabase is source of truth)
class JobCacheService {
  static const String _boxName = 'jobCache';
  static Box? _box;

  /// Initialize Hive and open the job cache box
  static Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
    
    print('✅ Job cache initialized');
  }

  /// Cache jobs for a specific rider
  /// Called after fetching from Supabase
  static Future<void> cacheJobs(String riderId, List<DispatchJob> jobs) async {
    await init();
    
    final data = {
      'rider_id': riderId,
      'jobs': jobs.map((job) => job.toJson()).toList(),
      'cached_at': DateTime.now().toIso8601String(),
      'job_count': jobs.length,
    };

    await _box!.put('rider_$riderId', data);
    print('✅ Cached ${jobs.length} jobs for rider $riderId');
  }

  /// Get cached jobs for a rider
  /// Returns null if cache is stale (>5 minutes old) or doesn't exist
  static Future<List<DispatchJob>?> getCachedJobs(String riderId) async {
    await init();
    
    final cached = _box!.get('rider_$riderId');
    if (cached == null) {
      print('⚠️ No cached jobs for rider $riderId');
      return null;
    }

    final cachedData = Map<String, dynamic>.from(cached);
    final cachedAt = DateTime.parse(cachedData['cached_at'] as String);
    final age = DateTime.now().difference(cachedAt);

    // Cache is only valid for 5 minutes (jobs update frequently)
    if (age.inMinutes > 5) {
      print('⚠️ Job cache expired (${age.inMinutes} minutes old)');
      return null;
    }

    // Parse jobs
    final jobsList = List<Map<String, dynamic>>.from(cachedData['jobs']);
    final jobs = jobsList.map((json) => DispatchJob.fromJson(json)).toList();

    print('✅ Loaded ${jobs.length} cached jobs (${age.inSeconds}s old)');
    return jobs;
  }

  /// Check if cache exists and is fresh
  static Future<bool> hasFreshCache(String riderId) async {
    await init();
    
    final cached = _box!.get('rider_$riderId');
    if (cached == null) return false;

    final cachedData = Map<String, dynamic>.from(cached);
    final cachedAt = DateTime.parse(cachedData['cached_at'] as String);
    final age = DateTime.now().difference(cachedAt);

    return age.inMinutes <= 5;
  }

  /// Get cache age in seconds
  static Future<int?> getCacheAge(String riderId) async {
    await init();
    
    final cached = _box!.get('rider_$riderId');
    if (cached == null) return null;

    final cachedData = Map<String, dynamic>.from(cached);
    final cachedAt = DateTime.parse(cachedData['cached_at'] as String);
    return DateTime.now().difference(cachedAt).inSeconds;
  }

  /// Clear cache for a specific rider
  static Future<void> clearRiderCache(String riderId) async {
    await init();
    await _box!.delete('rider_$riderId');
    print('🗑️ Cleared cache for rider $riderId');
  }

  /// Clear all cached jobs
  static Future<void> clearAllCache() async {
    await init();
    await _box!.clear();
    print('🗑️ All job cache cleared');
  }

  /// Get cache statistics
  static Future<Map<String, dynamic>> getCacheStats() async {
    await init();

    final keys = _box!.keys.toList();
    int totalJobs = 0;
    int freshCacheCount = 0;
    int staleCacheCount = 0;
    final now = DateTime.now();

    for (var key in keys) {
      final cached = _box!.get(key);
      if (cached != null) {
        final cachedData = Map<String, dynamic>.from(cached);
        totalJobs += cachedData['job_count'] as int;
        
        final cachedAt = DateTime.parse(cachedData['cached_at'] as String);
        final age = now.difference(cachedAt);
        
        if (age.inMinutes <= 5) {
          freshCacheCount++;
        } else {
          staleCacheCount++;
        }
      }
    }

    return {
      'riderCount': keys.length,
      'totalJobs': totalJobs,
      'freshCaches': freshCacheCount,
      'staleCaches': staleCacheCount,
      'maxAgeMinutes': 5,
    };
  }

  /// Clean stale caches (older than 1 hour)
  static Future<int> cleanStaleCache() async {
    await init();
    
    final keys = _box!.keys.toList();
    int removedCount = 0;
    final now = DateTime.now();

    for (var key in keys) {
      final cached = _box!.get(key);
      if (cached != null) {
        final cachedData = Map<String, dynamic>.from(cached);
        final cachedAt = DateTime.parse(cachedData['cached_at'] as String);
        
        if (now.difference(cachedAt).inHours > 1) {
          await _box!.delete(key);
          removedCount++;
        }
      }
    }

    if (removedCount > 0) {
      print('🗑️ Removed $removedCount stale job caches');
    }
    return removedCount;
  }
}
