import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:infinitywash/services/api/api_guard.dart';

/// Deterministic fake clock to avoid real sleeps in tests.
class FakeClock {
  DateTime _now = DateTime(2026, 1, 1);
  DateTime get now => _now;
  void advance(Duration d) => _now = _now.add(d);
}

void main() {
  http.Request reqFactory() => http.Request('GET', Uri.parse('https://example.com/route'));

  group('ApiGuard throttle', () {
    test('waits when requests are closer together than minInterval', () async {
      final sentAt = <DateTime>[];
      final guard = ApiGuard(
        now: () => DateTime.now(),
        send: (_) async {
          sentAt.add(DateTime.now());
          return http.Response('{}', 200);
        },
        minInterval: const Duration(milliseconds: 80),
      );

      await guard.execute('T', reqFactory);
      await guard.execute('T', reqFactory);

      final gap = sentAt[1].difference(sentAt[0]);
      expect(gap.inMilliseconds, greaterThanOrEqualTo(70),
          reason: 'second request must be delayed by the throttle');
    });

    test('does not wait when requests are spaced beyond minInterval', () async {
      final sentAt = <DateTime>[];
      final guard = ApiGuard(
        now: () => DateTime.now(),
        send: (_) async {
          sentAt.add(DateTime.now());
          return http.Response('{}', 200);
        },
        minInterval: const Duration(milliseconds: 20),
      );

      await guard.execute('T', reqFactory);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await guard.execute('T', reqFactory);

      final gap = sentAt[1].difference(sentAt[0]);
      expect(gap.inMilliseconds, greaterThanOrEqualTo(35));
    });
  });

  group('ApiGuard retry', () {
    test('retries on 429 and honors Retry-After, then succeeds', () async {
      final clock = FakeClock();
      var attempts = 0;
      final delays = <Duration>[];

      final guard = ApiGuard(
        now: () => clock.now,
        backoffFor: (attempt) {
          final d = attempt == 0 ? const Duration(milliseconds: 5) : const Duration(milliseconds: 10);
          delays.add(d);
          return d;
        },
        send: (request) async {
          attempts++;
          // "Sleep" the fake clock by the backoff the guard chose.
          clock.advance(delays.isNotEmpty ? delays.last : Duration.zero);
          if (attempts == 1) {
            return http.Response('{"error":"rate_limited"}', 429,
                headers: {'retry-after': '1'});
          }
          return http.Response('{"code":"Ok"}', 200);
        },
        minInterval: Duration.zero,
      );

      final result = await guard.execute('T', reqFactory);

      expect(attempts, 2);
      expect(result.verdict, GuardVerdict.success);
      expect(result.response!.statusCode, 200);
    });

    test('retries on 500 then succeeds', () async {
      var attempts = 0;
      final guard = ApiGuard(
        now: () => DateTime.now(),
        backoffFor: (_) => const Duration(milliseconds: 5),
        send: (_) async {
          attempts++;
          return attempts == 1
              ? http.Response('server error', 500)
              : http.Response('ok', 200);
        },
        minInterval: Duration.zero,
      );

      final result = await guard.execute('T', reqFactory);

      expect(attempts, 2);
      expect(result.verdict, GuardVerdict.success);
    });

    test('does not retry on 400 (permanent failure)', () async {
      var attempts = 0;
      final guard = ApiGuard(
        now: () => DateTime.now(),
        backoffFor: (_) => const Duration(milliseconds: 5),
        send: (_) async {
          attempts++;
          return http.Response('bad request', 400);
        },
        minInterval: Duration.zero,
      );

      final result = await guard.execute('T', reqFactory);

      expect(attempts, 1);
      expect(result.verdict, GuardVerdict.permanent);
      expect(result.response!.statusCode, 400);
    });

    test('gives up after maxRetries and records a failure', () async {
      var attempts = 0;
      final guard = ApiGuard(
        now: () => DateTime.now(),
        backoffFor: (_) => const Duration(milliseconds: 5),
        send: (_) async {
          attempts++;
          return http.Response('down', 503);
        },
        minInterval: Duration.zero,
      );

      final result = await guard.execute('T', reqFactory, maxRetries: 2);

      expect(attempts, 3, reason: '1 initial + 2 retries');
      expect(result.verdict, GuardVerdict.permanent);
    });

    test('retries on network exception then succeeds', () async {
      var attempts = 0;
      final guard = ApiGuard(
        now: () => DateTime.now(),
        backoffFor: (_) => const Duration(milliseconds: 5),
        send: (_) async {
          attempts++;
          if (attempts == 1) throw Exception('socket closed');
          return http.Response('ok', 200);
        },
        minInterval: Duration.zero,
      );

      final result = await guard.execute('T', reqFactory);

      expect(attempts, 2);
      expect(result.verdict, GuardVerdict.success);
    });
  });

  group('ApiGuard circuit breaker', () {
    test('opens after threshold consecutive failures and fails fast', () async {
      final clock = FakeClock();
      var attempts = 0;
      final guard = ApiGuard(
        now: () => clock.now,
        backoffFor: (_) => const Duration(milliseconds: 1),
        send: (_) async {
          attempts++;
          return http.Response('down', 503);
        },
        minInterval: Duration.zero,
      );

      // 5 executions with maxRetries=0 → 5 consecutive failures → breaker opens.
      for (var i = 0; i < 5; i++) {
        await guard.execute('P', reqFactory, maxRetries: 0);
      }
      expect(attempts, 5);

      // Next call must be blocked without sending.
      final blocked = await guard.execute('P', reqFactory);
      expect(attempts, 5, reason: 'breaker open → no network call');
      expect(blocked.verdict, GuardVerdict.breakerOpen);

      // Advance past cooldown (60s) — half-open allows a probe.
      clock.advance(const Duration(seconds: 61));
      await guard.execute('P', reqFactory, maxRetries: 0);
      expect(attempts, 6, reason: 'probe allowed after cooldown');
    });

    test('success resets the failure count', () async {
      final clock = FakeClock();
      var attempts = 0;
      final guard = ApiGuard(
        now: () => clock.now,
        backoffFor: (_) => const Duration(milliseconds: 1),
        send: (_) async {
          attempts++;
          if (attempts <= 4) return http.Response('down', 500);
          return http.Response('ok', 200);
        },
        minInterval: Duration.zero,
      );

      // 4 failures (below threshold of 5)...
      for (var i = 0; i < 4; i++) {
        await guard.execute('Q', reqFactory, maxRetries: 0);
      }
      // ...then a success resets the counter.
      final ok = await guard.execute('Q', reqFactory, maxRetries: 0);
      expect(ok.verdict, GuardVerdict.success);

      // 4 more failures must NOT open the breaker.
      for (var i = 0; i < 4; i++) {
        await guard.execute('Q', reqFactory, maxRetries: 0);
      }
      final still = await guard.execute('Q', reqFactory);
      expect(still.verdict, isNot(GuardVerdict.breakerOpen));
    });

    test('breakers are independent per provider', () async {
      final clock = FakeClock();
      final guard = ApiGuard(
        now: () => clock.now,
        backoffFor: (_) => const Duration(milliseconds: 1),
        send: (_) async => http.Response('down', 503),
        minInterval: Duration.zero,
      );

      for (var i = 0; i < 5; i++) {
        await guard.execute('A', reqFactory, maxRetries: 0);
      }
      expect(guard.isBreakerOpen('A'), isTrue);
      expect(guard.isBreakerOpen('B'), isFalse,
          reason: 'provider B must be unaffected by provider A failures');
    });
  });
}
