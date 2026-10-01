import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/routing_config.dart';
import 'api/api_guard.dart';
import 'cache/route_cache_service.dart';

/// Result of a routing request.
class RouteResult {
  final List<LatLng> points;
  final bool isFallback;
  final double distanceKm;
  final double durationMin;
  final String? error;

  const RouteResult({
    required this.points,
    this.isFallback = false,
    this.distanceKm = 0.0,
    this.durationMin = 0.0,
    this.error,
  });

  factory RouteResult.fallback(List<LatLng> waypoints, {String? error}) {
    return RouteResult(
      points: waypoints,
      isFallback: true,
      distanceKm: RoutingService.straightLineDistance(waypoints),
      durationMin: 0.0,
      error: error,
    );
  }
}

/// Road routing via OpenRouteService (when configured) with OSRM as backup.
class RoutingService {
  static const String _osrmBaseUrl =
      'https://router.project-osrm.org/route/v1/driving';
  static const Duration _timeout = Duration(seconds: 15);
  static const double _snapRadiusMeters = 5000;
  static const Map<String, String> _headers = {
    'User-Agent': 'InfinityWash/1.0 (com.infinitywash.app)',
    'Accept': 'application/json',
  };

  /// Shared outbound guard (throttle + retry + circuit breaker).
  static final ApiGuard _guard = ApiGuard();

  /// Convenience wrapper used by existing screens.
  Future<List<LatLng>> getRoute(List<LatLng> waypoints) async {
    final result = await getRouteResult(waypoints);
    return result.points;
  }

  /// Get route geometry plus whether it follows roads.
  Future<RouteResult> getRouteResult(List<LatLng> waypoints) async {
    if (waypoints.length < 2) {
      return RouteResult.fallback(waypoints, error: 'Not enough waypoints');
    }

    try {
      final cached = await RouteCacheService.getCachedRoute(waypoints);
      if (cached != null && cached.length > waypoints.length) {
        print('📦 Using cached route (${cached.length} points)');
        return RouteResult(
          points: cached,
          isFallback: false,
          distanceKm: straightLineDistance(cached),
        );
      }
    } catch (e) {
      print('⚠️ Cache read error: $e');
    }

    RouteResult? result;

    if (RoutingConfig.isConfigured) {
      result = await _fetchOpenRouteService(waypoints);
    }

    if (result == null || result.isFallback) {
      final osrm = await _fetchOsrm(waypoints);
      if (osrm != null && !osrm.isFallback) {
        result = osrm;
      } else {
        result ??= osrm;
      }
    }

    if (result == null || result.isFallback) {
      result = await _fetchPerLeg(waypoints) ?? result;
    }

    if (result == null || result.isFallback || result.points.length <= waypoints.length) {
      print('⚠️ Routing failed, using straight-line fallback');
      return RouteResult.fallback(
        waypoints,
        error: result?.error ?? 'No road route available',
      );
    }

    try {
      await RouteCacheService.cacheRoute(waypoints, result.points);
    } catch (e) {
      print('⚠️ Failed to cache route: $e');
    }

    return result;
  }

  Future<Map<String, dynamic>> getRouteWithMetadata(List<LatLng> waypoints) async {
    final result = await getRouteResult(waypoints);
    return {
      'points': result.points,
      'distance': result.distanceKm,
      'duration': result.durationMin,
      'isFallback': result.isFallback,
      'error': result.error,
    };
  }

  Future<RouteResult?> _fetchOpenRouteService(List<LatLng> waypoints) async {
    try {
      final url = Uri.parse('${RoutingConfig.openRouteServiceBaseUrl}/geojson');
      http.Request requestFactory() => http.Request('POST', url)
        ..headers.addAll({
          ..._headers,
          'Authorization': RoutingConfig.openRouteServiceApiKey,
          'Content-Type': 'application/json',
        })
        ..body = json.encode({
          'coordinates': [
            for (final p in waypoints) [p.longitude, p.latitude],
          ],
          'radiuses': List<double>.filled(waypoints.length, _snapRadiusMeters),
        });

      final guarded = await _guard.execute(
        ApiGuard.providerOrs,
        requestFactory,
        timeout: _timeout,
      );

      if (guarded.verdict != GuardVerdict.success || guarded.response == null) {
        print('⚠️ ORS failed: ${guarded.error}');
        return RouteResult.fallback(waypoints, error: guarded.error);
      }

      final response = guarded.response!;
      final data = json.decode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) {
        return RouteResult.fallback(waypoints, error: 'ORS empty geometry');
      }

      final geometry = features[0]['geometry'] as Map<String, dynamic>?;
      final coordinates = geometry?['coordinates'] as List?;
      if (coordinates == null || coordinates.isEmpty) {
        return RouteResult.fallback(waypoints, error: 'ORS missing coordinates');
      }

      final points = _coordsToLatLng(coordinates);
      final summary = (features[0]['properties'] as Map?)?['summary'] as Map?;
      final distanceM = (summary?['distance'] as num?)?.toDouble() ?? 0;
      final durationS = (summary?['duration'] as num?)?.toDouble() ?? 0;

      print('✅ ORS route with ${points.length} points');
      return RouteResult(
        points: points,
        distanceKm: distanceM / 1000,
        durationMin: durationS / 60,
      );
    } catch (e) {
      print('❌ ORS error: $e');
      return RouteResult.fallback(waypoints, error: e.toString());
    }
  }

  Future<RouteResult?> _fetchOsrm(List<LatLng> waypoints) async {
    try {
      final coordinates = waypoints
          .map((point) => '${point.longitude},${point.latitude}')
          .join(';');
      final radiuses = List.filled(waypoints.length, _snapRadiusMeters.toInt()).join(';');
      final url = Uri.parse(
        '$_osrmBaseUrl/$coordinates?overview=full&geometries=geojson&radiuses=$radiuses',
      );

      http.Request requestFactory() => http.Request('GET', url)..headers.addAll(_headers);

      final guarded = await _guard.execute(
        ApiGuard.providerOsrm,
        requestFactory,
        timeout: _timeout,
      );

      if (guarded.verdict != GuardVerdict.success || guarded.response == null) {
        print('⚠️ OSRM failed: ${guarded.error}');
        return RouteResult.fallback(waypoints, error: guarded.error);
      }

      final response = guarded.response!;
      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok' || data['routes'] == null || (data['routes'] as List).isEmpty) {
        print('⚠️ OSRM code: ${data['code']}');
        return RouteResult.fallback(
          waypoints,
          error: 'OSRM ${data['code'] ?? 'unknown'}',
        );
      }

      final route = data['routes'][0] as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>?;
      final coordinatesList = geometry?['coordinates'] as List?;
      if (coordinatesList == null || coordinatesList.isEmpty) {
        return RouteResult.fallback(waypoints, error: 'OSRM missing geometry');
      }

      final points = _coordsToLatLng(coordinatesList);
      print('✅ OSRM route with ${points.length} points');
      return RouteResult(
        points: points,
        distanceKm: ((route['distance'] as num?)?.toDouble() ?? 0) / 1000,
        durationMin: ((route['duration'] as num?)?.toDouble() ?? 0) / 60,
      );
    } catch (e) {
      print('❌ OSRM error: $e');
      return RouteResult.fallback(waypoints, error: e.toString());
    }
  }

  /// If the full multi-stop request fails, route each pair of consecutive stops.
  Future<RouteResult?> _fetchPerLeg(List<LatLng> waypoints) async {
    print('🔵 Retrying routing per leg (${waypoints.length - 1} legs)');
    final combined = <LatLng>[];
    double distanceKm = 0;
    double durationMin = 0;

    for (int i = 0; i < waypoints.length - 1; i++) {
      final pair = [waypoints[i], waypoints[i + 1]];
      RouteResult? leg;

      if (RoutingConfig.isConfigured) {
        leg = await _fetchOpenRouteService(pair);
      }
      if (leg == null || leg.isFallback || leg.points.length <= 2) {
        leg = await _fetchOsrm(pair);
      }

      if (leg == null || leg.isFallback || leg.points.length <= 2) {
        print('⚠️ Leg ${i + 1} failed');
        return null;
      }

      if (combined.isEmpty) {
        combined.addAll(leg.points);
      } else {
        combined.addAll(leg.points.skip(1));
      }
      distanceKm += leg.distanceKm;
      durationMin += leg.durationMin;
    }

    if (combined.length <= waypoints.length) return null;

    print('✅ Combined per-leg route with ${combined.length} points');
    return RouteResult(
      points: combined,
      distanceKm: distanceKm,
      durationMin: durationMin,
    );
  }

  List<LatLng> _coordsToLatLng(List coordinates) {
    return coordinates.map((coord) {
      return LatLng(
        (coord[1] as num).toDouble(),
        (coord[0] as num).toDouble(),
      );
    }).toList();
  }

  static double straightLineDistance(List<LatLng> waypoints) {
    if (waypoints.length < 2) return 0.0;

    double totalDistance = 0.0;
    const distance = Distance();

    for (int i = 0; i < waypoints.length - 1; i++) {
      totalDistance += distance.as(
        LengthUnit.Kilometer,
        waypoints[i],
        waypoints[i + 1],
      );
    }

    return totalDistance;
  }
}
