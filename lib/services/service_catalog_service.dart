import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class ServiceCatalogService {
  final SupabaseClient _client = SupabaseService.client;

  // Cache for service and addons to reduce database queries
  Map<String, dynamic>? _cachedService;
  final Map<String, Map<String, dynamic>> _cachedAddons = {};

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
  /// Returns service details including base_price
  Future<Map<String, dynamic>> getFullService() async {
    try {
      // Return cached service if available
      if (_cachedService != null) {
        print('✅ Returning cached service: ${_cachedService!['service_name']}');
        return _cachedService!;
      }

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

      // Cache the service
      _cachedService = response;

      print('✅ Loaded service: ${response['service_name']} - ₱${response['base_price']}');
      return response;
    } catch (e) {
      print('❌ Error loading service: $e');
      print('❌ Error type: ${e.runtimeType}');
      rethrow;
    }
  }

  /// Get addon by name (e.g., "Extra Fab Con", "Extra Detergent")
  /// Returns addon details including price
  Future<Map<String, dynamic>> getAddonByName(String addonName) async {
    try {
      // Return cached addon if available
      if (_cachedAddons.containsKey(addonName)) {
        return _cachedAddons[addonName]!;
      }

      // Query addon by name
      final response = await _client
          .from('service_addons')
          .select()
          .eq('addon_name', addonName)
          .eq('status', 'active')
          .maybeSingle();

      if (response == null) {
        throw Exception('Addon "$addonName" not found in service_addons');
      }

      // Cache the addon
      _cachedAddons[addonName] = response;

      print('✅ Loaded addon: ${response['addon_name']} - ₱${response['price']}');
      return response;
    } catch (e) {
      print('❌ Error loading addon "$addonName": $e');
      rethrow;
    }
  }

  /// Get addon by code (e.g., "extra-fabric-conditioner", "extra-detergent")
  /// Returns addon details including price
  Future<Map<String, dynamic>> getAddonByCode(String addonCode) async {
    try {
      // Return cached addon if available
      if (_cachedAddons.containsKey(addonCode)) {
        return _cachedAddons[addonCode]!;
      }

      // Query addon by code
      final response = await _client
          .from('service_addons')
          .select()
          .eq('addon_code', addonCode)
          .eq('status', 'active')
          .maybeSingle();

      if (response == null) {
        throw Exception('Addon "$addonCode" not found in service_addons');
      }

      // Cache the addon
      _cachedAddons[addonCode] = response;

      print('✅ Loaded addon: ${response['addon_name']} - ₱${response['price']}');
      return response;
    } catch (e) {
      print('❌ Error loading addon "$addonCode": $e');
      rethrow;
    }
  }

  /// Get all active addons
  Future<List<Map<String, dynamic>>> getAllAddons() async {
    try {
      final response = await _client
          .from('service_addons')
          .select()
          .eq('status', 'active')
          .order('addon_name');

      final addons = List<Map<String, dynamic>>.from(response);

      // Cache all addons
      for (var addon in addons) {
        _cachedAddons[addon['addon_name'] as String] = addon;
      }

      print('✅ Loaded ${addons.length} active addons');
      return addons;
    } catch (e) {
      print('❌ Error loading addons: $e');
      rethrow;
    }
  }

  /// Clear cache (useful for testing or when data changes)
  void clearCache() {
    _cachedService = null;
    _cachedAddons.clear();
    print('🔄 Service catalog cache cleared');
  }

  /// Reload service and addons from database
  Future<void> refreshCache() async {
    clearCache();
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
}
