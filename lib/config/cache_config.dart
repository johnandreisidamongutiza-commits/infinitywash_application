/// Central configuration for the API cache layer and outbound API guard.
///
/// All knobs live here so tuning the caching behavior never requires
/// touching service code.
class CacheConfig {
  // ========================================
  // TTL durations (per data type)
  // ========================================

  /// Service catalog + addons (prices change rarely).
  static const Duration catalogTtl = Duration(hours: 24);

  /// Dispatch jobs (update often).
  static const Duration jobsTtl = Duration(seconds: 30);

  /// Calculated routes (road geometry is stable).
  /// Note: actual route caching stays in [RouteCacheService] (7 days);
  /// this value documents the policy for anything routed through ApiGate.
  static const Duration routeTtl = Duration(days: 7);

  // ========================================
  // Background refresh
  // ========================================

  /// Minimum age of a cached value before a background refresh is
  /// triggered on read (stale-while-revalidate throttle).
  /// Prevents "refresh on every cache hit" API spam.
  static const Duration backgroundRefreshMinAge = Duration(seconds: 30);

  // ========================================
  // Outbound API guard (ORS / OSRM)
  // ========================================

  /// Minimum interval between outbound routing requests (token bucket).
  /// 1 req/s keeps us polite to the free OSRM demo server and
  /// smooths bursts away from the ORS free-tier limit (5000/day).
  static const Duration outboundMinInterval = Duration(seconds: 1);

  /// Max retries for a failed outbound request.
  static const int outboundMaxRetries = 2;

  /// Base delay for exponential backoff between retries.
  /// Delay sequence: 1s, 2s (+ random jitter up to 25%).
  static const Duration outboundBackoffBase = Duration(seconds: 1);

  /// Upper bound for a single backoff delay.
  static const Duration outboundBackoffMax = Duration(seconds: 8);

  /// Consecutive failures before the circuit breaker opens for a provider.
  static const int breakerFailureThreshold = 5;

  /// How long an open breaker stays open before allowing a probe request.
  static const Duration breakerCooldown = Duration(seconds: 60);

  // ========================================
  // Hive box names
  // ========================================

  /// Box for generic ApiGate persistence (catalog etc.).
  static const String apiCacheBox = 'apiCache';
}
