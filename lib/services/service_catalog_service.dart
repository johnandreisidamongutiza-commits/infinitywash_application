import 'package:supabase_flutter/supabase_flutter.dart';
import 'api/api_gate.dart';
import 'supabase_service.dart';
import '../config/cache_config.dart';

class ServiceCatalogService {
  final SupabaseClient _client = SupabaseService.client;

  // In-memory lookups backed by ApiGate (Hive-persisted, 24h TTL)
  final Map<String, Map<String, dynamic>> _cachedAddonsByName = {};
  final Map<String, Map<String, dynamic>> _cachedAddonsByCode = {};

  static const String _serviceKey = 'catalog:service';
  static const String _addonsKey = 'catalog:addons';

  /// Test Supabase connection (debugging method)
  Future<void> testConnection() async {
    try {
      print('🔍 Testing Supabase connection...');
      
      // Try a simple query to test connection
      final response = await _client
          .from('service_catalog')
          .select()
          .limit(1);
          
      print('✅ Connection test successful. Found ${response.length} records');
    } catch (e) {
      print('❌ Connection test failed: $e');
      print('❌ Error type: ${e.runtimeType}');
    }
  }

  /// Get the full service (there's only one service: Full Service)
  /// Returns service details including base_price.
  ///
  /// Cached in memory + Hive (24h TTL). Deduplicated: concurrent callers
  /// share one query.
  Future<Map<String, dynamic>> getFullService() async {
    try {
      await ApiGate.instance.init();
      final result = await ApiGate.instance.runCached<Map<String, dynamic>>(
        _serviceKey,
        CacheConfig.catalogTtl,
        _fetchServiceFromDb,
        persist: true,
        decode: (raw) => Map<String, dynamic>.from(raw as Map),
      );
      if (result.fromCache) {
        print('✅ Returning cached service (age: ${result.hiveAge?.inMinutes ?? 0} min): ${result.value['service_name']}');
      }
      return result.value;
    } catch (e) {
      print('❌ Error loading service: $e');
      print('❌ Error type: ${e.runtimeType}');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _fetchServiceFromDb() async {
    print('🔍 Querying service_catalog for active service...');

    // Query for the single active service
    final response = await _client
        .from('service_catalog')
        .select()
        .eq('status', 'active')
        .maybeSingle();

    print('📊 Query response: $response');

    if (response == null) {
      print('❌ No response from service_catalog query');

      // Let's try a broader query for debugging
      print('🔍 Trying to get ALL services for debugging...');
      final allServices = await _client
          .from('service_catalog')
          .select();
      print('📊 All services in table: $allServices');

      throw Exception('No active service found in service_catalog');
    }

    print('✅ Loaded service: ${response['service_name']} - ₱${response['base_price']}');
    return Map<String, dynamic>.from(response);
  }

  /// Get addon by name (e.g., "Extra Fab Con", "Extra Detergent")
  /// Returns addon details including price.
  ///
  /// Resolved locally from the cached addon list when possible —
  /// at most one query instead of one per lookup.
  Future<Map<String, dynamic>> getAddonByName(String addonName) async {
    try {
      final cached = _cachedAddonsByName[addonName];
      if (cached != null) return cached;

      // Try resolving from the cached full list first (0-1 queries total).
      try {
        final addons = await getAllAddons();
        for (final addon in addons) {
          if (addon['addon_name'] == addonName) {
            _cachedAddonsByName[addonName] = addon;
            return addon;
          }
        }
      } catch (_) {
        // List fetch failed — fall through to direct lookup.
      }

      // Direct lookup fallback.
      final response = await _client
          .from('service_addons')
          .select()
          .eq('addon_name', addonName)
          .eq('status', 'active')
          .maybeSingle();

      if (response == null) {
        throw Exception('Addon "$addonName" not found in service_addons');
      }

      final addon = Map<String, dynamic>.from(response);
      _cachedAddonsByName[addonName] = addon;

      print('✅ Loaded addon: ${addon['addon_name']} - ₱${addon['price']}');
      return addon;
    } catch (e) {
      print('❌ Error loading addon "$addonName": $e');
      rethrow;
    }
  }

  /// Get addon by code (e.g., "extra-fabric-conditioner", "extra-detergent")
  /// Returns addon details including price.
  /// Resolved locally from the cached addon list when possible.
  Future<Map<String, dynamic>> getAddonByCode(String addonCode) async {
    try {
      final cached = _cachedAddonsByCode[addonCode];
      if (cached != null) return cached;

      // Try resolving from the cached full list first.
      try {
        final addons = await getAllAddons();
        for (final addon in addons) {
          if (addon['addon_code'] == addonCode) {
            _cachedAddonsByCode[addonCode] = addon;
            return addon;
          }
        }
      } catch (_) {
        // List fetch failed — fall through to direct lookup.
      }

      // Direct lookup fallback.
      final response = await _client
          .from('service_addons')
          .select()
          .eq('addon_code', addonCode)
          .eq('status', 'active')
          .maybeSingle();

      if (response == null) {
        throw Exception('Addon "$addonCode" not found in service_addons');
      }

      final addon = Map<String, dynamic>.from(response);
      _cachedAddonsByCode[addonCode] = addon;

      print('✅ Loaded addon: ${addon['addon_name']} - ₱${addon['price']}');
      return addon;
    } catch (e) {
      print('❌ Error loading addon "$addonCode": $e');
      rethrow;
    }
  }

  /// Get all active addons.
  /// Cached in memory + Hive (24h TTL), deduplicated across concurrent callers.
  Future<List<Map<String, dynamic>>> getAllAddons() async {
    try {
      await ApiGate.instance.init();
      final result = await ApiGate.instance.runCached<List<Map<String, dynamic>>>(
        _addonsKey,
        CacheConfig.catalogTtl,
        _fetchAddonsFromDb,
        persist: true,
        decode: (raw) => (raw as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );

      // Index by name and code for fast local lookups.
      for (var addon in result.value) {
        final name = addon['addon_name'] as String?;
        final code = addon['addon_code'] as String?;
        if (name != null) _cachedAddonsByName[name] = addon;
        if (code != null) _cachedAddonsByCode[code] = addon;
      }

      if (!result.fromCache) {
        print('✅ Loaded ${result.value.length} active addons');
      }
      return result.value;
    } catch (e) {
      print('❌ Error loading addons: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAddonsFromDb() async {
    final response = await _client
        .from('service_addons')
        .select()
        .eq('status', 'active')
        .order('addon_name');
    return List<Map<String, dynamic>>.from(response);
  }

  /// Resolve multiple addon codes to addon rows using the cached list.
  /// Returns a map of code → addon row (only codes that exist are included).
  /// One cached [getAllAddons] call replaces N per-addon queries.
  Future<Map<String, Map<String, dynamic>>> resolveAddonsByCode(
    List<String> codes,
  ) async {
    final resolved = <String, Map<String, dynamic>>{};
    if (codes.isEmpty) return resolved;

    final missing = <String>[];
    for (final code in codes) {
      final cached = _cachedAddonsByCode[code];
      if (cached != null) {
        resolved[code] = cached;
      } else {
        missing.add(code);
      }
    }

    if (missing.isNotEmpty) {
      await getAllAddons();
      for (final code in missing) {
        final addon = _cachedAddonsByCode[code];
        if (addon != null) resolved[code] = addon;
      }
    }

    return resolved;
  }

  /// Clear cache (useful for testing or when data changes)
  Future<void> clearCache() async {
    _cachedAddonsByName.clear();
    _cachedAddonsByCode.clear();
    await ApiGate.instance.invalidate(_serviceKey);
    await ApiGate.instance.invalidate(_addonsKey);
    print('🔄 Service catalog cache cleared');
  }

  /// Reload service and addons from database
  Future<void> refreshCache() async {
    await clearCache();
    await getFullService();
    await getAllAddons();
  }

  /// Get base price per load (convenience method)
  Future<double> getBasePricePerLoad() async {
    final service = await getFullService();
    return (service['base_price'] as num).toDouble();
  }

  /// Get addon price by name (convenience method)
  Future<double> getAddonPrice(String addonName) async {
    final addon = await getAddonByName(addonName);
    return (addon['price'] as num).toDouble();
  }

  /// Calculate total price for an order
  Future<Map<String, double>> calculateOrderTotal({
    required int loadsCount,
    List<String> addonNames = const [],
  }) async {
    try {
      // Get base price
      final basePrice = await getBasePricePerLoad();
      final subtotal = basePrice * loadsCount;

      // Calculate addons total
      double addonsTotal = 0.0;
      for (var addonName in addonNames) {
        final addon = await getAddonByName(addonName);
        addonsTotal += (addon['price'] as num).toDouble();
      }

      // Delivery is always free
      const deliveryFee = 0.0;

      final total = subtotal + addonsTotal + deliveryFee;

      return {
        'base_price': basePrice,
        'subtotal': subtotal,
        'addons_total': addonsTotal,
        'delivery_fee': deliveryFee,
        'total': total,
      };
    } catch (e) {
      print('❌ Error calculating order total: $e');
      rethrow;
    }
  }

  /// Get category limits per load from database if available
  Future<Map<String, double>> getCategoryLimits() async {
    try {
      final response = await _client
          .from('laundry_types')
          .select('laundry_type_name, limit_per_load')
          .eq('status', 'active');
      final Map<String, double> limits = {};
      for (final row in response) {
        final name = row['laundry_type_name'] as String?;
        final limit = (row['limit_per_load'] as num?)?.toDouble();
        if (name != null && limit != null) {
          limits[name] = limit;
        }
      }
      if (limits.isNotEmpty) return limits;
    } catch (e) {
      print('ℹ️ Using default category limits (laundry_types table query skipped: $e)');
    }
    return {};
  }
}
