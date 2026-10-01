import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../config/cache_config.dart';

/// Outcome classification for an outbound HTTP attempt.
enum GuardVerdict { success, retryable, permanent, breakerOpen }

/// Result of a guarded HTTP request.
class GuardedResponse {
  final http.Response? response;
  final GuardVerdict verdict;
  final String? error;

  const GuardedResponse({this.response, required this.verdict, this.error});
}

/// Outbound API protection for third-party HTTP APIs (OpenRouteService, OSRM):
///
/// 1. **Token-bucket throttle** — min interval between requests.
/// 2. **Retry with exponential backoff + jitter** on 429/5xx only,
///    honoring the `Retry-After` header.
/// 3. **Per-provider circuit breaker** — after [CacheConfig.breakerFailureThreshold]
///    consecutive failures, requests fail fast for [CacheConfig.breakerCooldown]
///    instead of hammering a dead or rate-limited API.
///
/// Fully injectable: pass a custom `send` function or fake clock in tests.
class ApiGuard {
  ApiGuard({
    this._send,
    this._backoffFor,
    DateTime Function()? now,
    this._minInterval = CacheConfig.outboundMinInterval,
  })  : _now = now ?? DateTime.now;

  final Future<http.Response> Function(http.BaseRequest request)? _send;
  final Duration Function(int attempt)? _backoffFor;
  final DateTime Function() _now;
  final Duration _minInterval;

  // ---------------- Throttle state ----------------
  DateTime? _lastRequestAt;

  // ---------------- Breaker state (per provider key) ----------------
  final Map<String, int> _consecutiveFailures = {};
  final Map<String, DateTime?> _openUntil = {};

  /// Provider labels for logging/metrics.
  static const String providerOrs = 'ORS';
  static const String providerOsrm = 'OSRM';

  /// Minimum interval enforced between two outbound requests.
  Duration get minInterval => _minInterval;

  /// Execute [requestFactory] through throttle + retry + breaker.
  ///
  /// [requestFactory] must return a fresh [http.Request] each call (a
  /// consumed request cannot be resent).
  Future<GuardedResponse> execute(
    String provider,
    http.Request Function() requestFactory, {
    int maxRetries = CacheConfig.outboundMaxRetries,
    Duration? timeout,
  }) async {
    // 1. Circuit breaker check.
    if (isBreakerOpen(provider)) {
      return GuardedResponse(
        verdict: GuardVerdict.breakerOpen,
        error: 'Circuit breaker open for $provider',
      );
    }

    // 2. Throttle.
    await _waitForSlot();

    // 3. Attempt loop with backoff.
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final sendFuture = _sendRequest(requestFactory());
        final response =
            timeout != null ? await sendFuture.timeout(timeout) : await sendFuture;

        if (response.statusCode >= 200 && response.statusCode < 300) {
          _recordSuccess(provider);
          return GuardedResponse(response: response, verdict: GuardVerdict.success);
        }

        final retryable = response.statusCode == 429 || response.statusCode >= 500;
        if (retryable && attempt < maxRetries) {
          final delay = _retryDelay(attempt, response.headers['retry-after']);
          // ignore: avoid_print
          print(
              '⏳ $provider HTTP ${response.statusCode}, retrying in ${delay.inMilliseconds}ms '
              '(attempt ${attempt + 1}/$maxRetries)');
          await Future<void>.delayed(delay);
          continue;
        }

        // Non-retryable status (or retries exhausted).
        if (retryable) {
          _recordFailure(provider);
        }
        return GuardedResponse(
          response: response,
          verdict: GuardVerdict.permanent,
          error: '$provider HTTP ${response.statusCode}',
        );
      } catch (e) {
        // Network error / TimeoutException — treated as retryable.
        if (attempt < maxRetries) {
          final delay = _retryDelay(attempt, null);
          // ignore: avoid_print
          print('⏳ $provider error ($e), retrying in ${delay.inMilliseconds}ms');
          await Future<void>.delayed(delay);
          continue;
        }
        _recordFailure(provider);
        return GuardedResponse(verdict: GuardVerdict.permanent, error: e.toString());
      }
    }

    // Unreachable, but keeps the analyzer happy.
    return const GuardedResponse(verdict: GuardVerdict.permanent, error: 'exhausted');
  }

  /// Whether the breaker for [provider] currently blocks new requests.
  bool isBreakerOpen(String provider) {
    final openUntil = _openUntil[provider];
    if (openUntil == null) return false;
    if (_now().isBefore(openUntil)) return true;
    // Cooldown elapsed — half-open: clear and allow a probe request.
    _openUntil[provider] = null;
    _consecutiveFailures[provider] = 0;
    return false;
  }

  void _recordSuccess(String provider) {
    _consecutiveFailures[provider] = 0;
    _openUntil[provider] = null;
  }

  void _recordFailure(String provider) {
    final failures = (_consecutiveFailures[provider] ?? 0) + 1;
    _consecutiveFailures[provider] = failures;
    if (failures >= CacheConfig.breakerFailureThreshold) {
      _openUntil[provider] = _now().add(CacheConfig.breakerCooldown);
      // ignore: avoid_print
      print('⛔ Circuit breaker OPEN for $provider for ${CacheConfig.breakerCooldown.inSeconds}s');
    }
  }

  /// Compute the delay before the retry for [attempt] (0-based).
  Duration _retryDelay(int attempt, String? retryAfterHeader) {
    if (_backoffFor != null) {
      return _backoffFor(attempt);
    }
    // Honor Retry-After (seconds) when present.
    final retryAfterSeconds = int.tryParse(retryAfterHeader ?? '');
    if (retryAfterSeconds != null && retryAfterSeconds > 0) {
      return Duration(seconds: retryAfterSeconds);
    }
    // Exponential backoff: 1s, 2s, 4s... capped, plus up to 25% jitter.
    final exponential = CacheConfig.outboundBackoffBase * (1 << attempt);
    final capped = exponential > CacheConfig.outboundBackoffMax
        ? CacheConfig.outboundBackoffMax
        : exponential;
    final jitterMs = Random().nextInt((capped.inMilliseconds / 4).ceil() + 1);
    return capped + Duration(milliseconds: jitterMs);
  }

  Future<void> _waitForSlot() async {
    while (true) {
      final last = _lastRequestAt;
      if (last == null) break;
      final elapsed = _now().difference(last);
      if (elapsed >= minInterval) break;
      final waitNeeded = minInterval - elapsed;
      // ignore: avoid_print
      print('🚦 Throttling outbound request by ${waitNeeded.inMilliseconds}ms');
      await Future<void>.delayed(waitNeeded);
    }
    _lastRequestAt = _now();
  }

  Future<http.Response> _sendRequest(http.BaseRequest request) async {
    final sender = _send;
    if (sender != null) {
      return sender(request);
    }
    return http.Response.fromStream(await request.send());
  }

  /// Reset all state (testing).
  void reset() {
    _consecutiveFailures.clear();
    _openUntil.clear();
    _lastRequestAt = null;
  }
}
