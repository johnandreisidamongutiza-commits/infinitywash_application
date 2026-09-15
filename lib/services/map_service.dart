/// Placeholder map service for future rider navigation integration.
///
/// This file is intentionally kept blank-safe so the project can compile
/// without a real API key while you prepare the map credentials later.
class MapService {
  const MapService();

  bool get isConfigured => false;

  String get statusMessage =>
      'Map service is not configured yet. Add your API key in lib/config/map_config.dart.';
}
