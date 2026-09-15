class MapConfig {
  // Leave this blank for now. Later replace it with your actual API key.
  static const String googleMapsApiKey = '';

  static bool get hasGoogleMapsApiKey => googleMapsApiKey.trim().isNotEmpty;

  static String get googleMapsApiKeyOrPlaceholder =>
      hasGoogleMapsApiKey ? googleMapsApiKey : 'ENTER_GOOGLE_MAPS_API_KEY';
}
