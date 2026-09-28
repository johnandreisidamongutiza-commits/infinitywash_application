/// Routing API Configuration
/// 
/// This project uses OpenRouteService for route calculations.
/// Free tier: 5000 requests/day
/// 
/// To get your API key:
/// 1. Sign up at https://openrouteservice.org/dev/#/signup
/// 2. Go to https://openrouteservice.org/dev/#/api-key
/// 3. Copy your API key and paste it below

class RoutingConfig {
  /// OpenRouteService API Key
  /// Get yours at: https://openrouteservice.org/dev/#/signup
  static const String openRouteServiceApiKey = 'YOUR_API_KEY_HERE';
  
  /// API Base URL
  static const String openRouteServiceBaseUrl = 'https://api.openrouteservice.org/v2/directions/driving-car';
  
  /// Check if routing is configured
  static bool get isConfigured => openRouteServiceApiKey != 'YOUR_API_KEY_HERE';
  
  /// Get status message
  static String get statusMessage {
    if (isConfigured) {
      return 'Routing service is configured and ready.';
    }
    return 'Routing service not configured. Add your OpenRouteService API key in lib/config/routing_config.dart';
  }
}
