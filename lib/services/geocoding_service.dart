import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/location_constants.dart';

/// Represents an address search match returned by Nominatim / OpenStreetMap.
class GeocodingResult {
  final String displayName;
  final String title;
  final String subtitle;
  final double latitude;
  final double longitude;

  GeocodingResult({
    required this.displayName,
    required this.title,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
  });

  factory GeocodingResult.fromJson(Map<String, dynamic> json) {
    final rawName = (json['display_name'] as String? ?? '').trim();
    final parts = rawName.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    final title = parts.isNotEmpty ? parts.first : rawName;
    final subtitle = parts.length > 1 ? parts.sublist(1).join(', ') : '';

    return GeocodingResult(
      displayName: rawName,
      title: title,
      subtitle: subtitle,
      latitude: double.tryParse(json['lat']?.toString() ?? '') ?? 0.0,
      longitude: double.tryParse(json['lon']?.toString() ?? '') ?? 0.0,
    );
  }
}

/// Service to search addresses, landmarks, and reverse geocode coordinates.
class GeocodingService {
  static final GeocodingService _instance = GeocodingService._internal();
  factory GeocodingService() => _instance;
  GeocodingService._internal();

  final http.Client _client = http.Client();
  final Map<String, String> _reverseCache = {};

  /// Search for places matching [query].
  /// When [boundedToServiceArea] is true, results are strictly scoped to the
  /// Infinity Wash operational region in Laguna.
  Future<List<GeocodingResult>> search(
    String query, {
    bool boundedToServiceArea = true,
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return [];

    try {
      final queryParams = <String, String>{
        'q': trimmed,
        'format': 'json',
        'addressdetails': '1',
        'limit': '5',
        'countrycodes': 'ph',
      };

      if (boundedToServiceArea) {
        // ~15km bounding box around Sta Cruz, Laguna shop
        final shop = LocationConstants.shopLocation;
        final minLat = shop.latitude - 0.14;
        final maxLat = shop.latitude + 0.14;
        final minLon = shop.longitude - 0.14;
        final maxLon = shop.longitude + 0.14;

        queryParams['viewbox'] = '$minLon,$maxLat,$maxLon,$minLat';
        queryParams['bounded'] = '1';
      }

      final uri = Uri.https('nominatim.openstreetmap.org', '/search', queryParams);

      final response = await _client.get(
        uri,
        headers: {
          'User-Agent': 'InfinityWashApp/1.0 (com.infinitywash.app)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        return data
            .map((item) => GeocodingResult.fromJson(item as Map<String, dynamic>))
            .where((r) => r.latitude != 0.0 && r.longitude != 0.0)
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Reverse geocode coordinates to a clean, human-readable address.
  /// Example return: "Bubukal, Santa Cruz, Laguna"
  Future<String?> reverseGeocode(double lat, double lon) async {
    final cacheKey = '${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}';
    if (_reverseCache.containsKey(cacheKey)) {
      return _reverseCache[cacheKey];
    }

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': lat.toString(),
        'lon': lon.toString(),
        'format': 'json',
        'addressdetails': '1',
      });

      final response = await _client.get(
        uri,
        headers: {
          'User-Agent': 'InfinityWashApp/1.0 (com.infinitywash.app)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;

        String result;
        if (address != null) {
          // Construct clean, compact address
          final road = address['road'] ?? address['pedestrian'] ?? address['building'] ?? address['amenity'];
          final barangay = address['quarter'] ?? address['suburb'] ?? address['neighbourhood'] ?? address['village'];
          final town = address['town'] ?? address['city'] ?? address['municipality'];

          final parts = [road, barangay, town]
              .where((p) => p != null && p.toString().trim().isNotEmpty)
              .map((p) => p.toString().trim())
              .toList();

          if (parts.isNotEmpty) {
            result = parts.join(', ');
          } else {
            result = (data['display_name'] as String? ?? '').split(',').take(3).join(', ').trim();
          }
        } else {
          result = (data['display_name'] as String? ?? '').split(',').take(3).join(', ').trim();
        }

        if (result.isNotEmpty) {
          _reverseCache[cacheKey] = result;
          return result;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
