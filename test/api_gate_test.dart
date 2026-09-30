import 'package:flutter_test/flutter_test.dart';
import 'package:infinitywash/services/api/api_gate.dart';

void main() {
  setUp(() async {
    await ApiGate.instance.clearAll();
  });

  group('ApiGate deduplication', () {
    test('concurrent calls with same key share one task', () async {
      var calls = 0;
      Future<int> task() async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return 42;
      }

      final results = await Future.wait([
        ApiGate.instance.run('k1', task),
        ApiGate.instance.run('k1', task),
        ApiGate.instance.run('k1', task),
      ]);

      expect(calls, 1, reason: 'dedup should collapse 3 concurrent calls into 1');
      expect(results, everyElement(42));
    });

    test('different keys do not dedupe', () async {
      var calls = 0;
      Future<int> task() async {
        calls++;
        return calls;
      }

      await Future.wait([
        ApiGate.instance.run('a', task),
        ApiGate.instance.run('b', task),
      ]);

      expect(calls, 2);
    });

    test('sequential calls after completion each run the task', () async {
      var calls = 0;
      Future<int> task() async {
        calls++;
        return calls;
      }

      await ApiGate.instance.run('seq', task);
      await ApiGate.instance.run('seq', task);

      expect(calls, 2);
    });

    test('failed task removes in-flight entry so retry is possible', () async {
      var calls = 0;
      Future<int> task() async {
        calls++;
        throw StateError('boom $calls');
      }

      await expectLater(ApiGate.instance.run('f', task), throwsStateError);
      await expectLater(ApiGate.instance.run('f', task), throwsStateError);
      expect(calls, 2);
    });
  });

  group('ApiGate runCached', () {
    test('second call within TTL hits memory cache without running task',
        () async {
      var calls = 0;

      final first = await ApiGate.instance.runCached<String>(
        'mem',
        const Duration(minutes: 5),
        () async {
          calls++;
          return 'fresh';
        },
      );
      final second = await ApiGate.instance.runCached<String>(
        'mem',
        const Duration(minutes: 5),
        () async {
          calls++;
          return 'should-not-run';
        },
      );

      expect(first.fromCache, isFalse);
      expect(second.fromCache, isTrue);
      expect(calls, 1);
      expect(second.value, 'fresh');
    });

    test('expired memory entry re-runs the task', () async {
      var calls = 0;

      await ApiGate.instance.runCached<String>(
        'ttl',
        const Duration(milliseconds: 10),
        () async {
          calls++;
          return 'v1';
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final after = await ApiGate.instance.runCached<String>(
        'ttl',
        const Duration(milliseconds: 10),
        () async {
          calls++;
          return 'v2';
        },
      );

      expect(calls, 2);
      expect(after.value, 'v2');
      expect(after.fromCache, isFalse);
    });

    test('invalidate forces a refetch', () async {
      var calls = 0;

      await ApiGate.instance.runCached<String>('inv', const Duration(hours: 1),
          () async {
        calls++;
        return 'old';
      });
      await ApiGate.instance.invalidate('inv');
      final after = await ApiGate.instance.runCached<String>(
          'inv', const Duration(hours: 1), () async {
        calls++;
        return 'new';
      });

      expect(calls, 2);
      expect(after.value, 'new');
      expect(after.fromCache, isFalse);
    });

    test('invalidatePrefix clears matching keys only', () async {
      await ApiGate.instance.runCached<String>(
          'catalog:a', const Duration(hours: 1), () async => 'a');
      await ApiGate.instance.runCached<String>(
          'catalog:b', const Duration(hours: 1), () async => 'b');
      await ApiGate.instance.runCached<String>(
          'other:c', const Duration(hours: 1), () async => 'c');

      await ApiGate.instance.invalidatePrefix('catalog:');

      final a = await ApiGate.instance.runCached<String>('catalog:a',
          const Duration(hours: 1), () async => 'a2');
      final c = await ApiGate.instance.runCached<String>('other:c',
          const Duration(hours: 1), () async => 'c');

      expect(a.value, 'a2', reason: 'catalog:a was invalidated');
      expect(c.value, 'c', reason: 'other:c must survive prefix invalidation');
    });

    test('runCached deduplicates concurrent misses', () async {
      var calls = 0;

      final futures = List.generate(3, (_) {
        return ApiGate.instance.runCached<String>('dedup', const Duration(hours: 1),
            () async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return 'once';
        });
      });

      final results = await Future.wait(futures);
      expect(calls, 1);
      expect(results.map((r) => r.value), everyElement('once'));
    });
  });
}
