import 'dart:async';
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../../config/cache_config.dart';

/// Result wrapper for [ApiGate.runCached].
class GateResult<T> {
  /// The value (from memory, Hive or a fresh fetch).
  final T value;

  /// True when the value came from cache (memory or Hive), not a live fetch.
  final bool fromCache;

  /// Age of the value if it came from Hive (null for memory/fresh).
  final Duration? hiveAge;

  const GateResult({required this.value, required this.fromCache, this.hiveAge});
}

/// A timestamped envelope persisted to Hive.
class _Envelope {
  final dynamic data;
  final DateTime cachedAt;

  _Envelope(this.data, this.cachedAt);

  Map<String, dynamic> toJson() => {
        'data': data,
        'cached_at': cachedAt.toIso8601String(),
      };

  static _Envelope fromJson(Map<dynamic, dynamic> json) => _Envelope(
        json['data'],
        DateTime.parse(json['cached_at'] as String),
      );
}

/// Generic API gate providing:
///
/// 1. **Request deduplication** — concurrent identical calls share one Future.
/// 2. **Memory TTL cache** — instant reads within the TTL window.
/// 3. **Hive persistence** — selected keys survive app restarts (offline-first).
/// 4. **Write-through invalidation** — call [invalidate] after successful writes.
///
/// All failures are non-fatal: if Hive is unavailable the gate degrades to
/// memory-only caching, and if a cached read fails the fetcher runs.
class ApiGate {
  ApiGate._();
  static final ApiGate instance = ApiGate._();

  static const String _boxName = CacheConfig.apiCacheBox;

  Box? _box;
  bool _hiveAvailable = false;

  // key -> (value, expiry)
  final Map<String, _MemoryEntry<dynamic>> _memory = {};
  // key -> in-flight future (deduplication)
  final Map<String, Future<dynamic>> _inFlight = {};

  bool _initStarted = false;

  /// Initialize Hive persistence. Safe to call multiple times and safe to
  /// skip entirely — the gate works memory-only when Hive is unavailable.
  Future<void> init() async {
    if (_initStarted) return;
    _initStarted = true;
    try {
      _box = await Hive.openBox(_boxName);
      _hiveAvailable = true;
    } catch (e) {
      _hiveAvailable = false;
      // ignore: avoid_print
      print('⚠️ ApiGate Hive unavailable, memory-only mode: $e');
    }
  }

  /// Run [task] with deduplication. Concurrent calls with the same [key]
  /// share a single in-flight Future (one network call).
  Future<T> run<T>(String key, Future<T> Function() task) {
    final existing = _inFlight[key];
    if (existing != null) {
      return existing.then((v) => v as T);
    }
    final future = task().whenComplete(() {
      // Block body: must NOT return the removed future (Map.remove returns
      // the stored Future), otherwise whenComplete would await itself and
      // deadlock.
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  /// Run [task] behind a TTL cache:
  /// - fresh memory entry → returned immediately (no fetch);
  /// - fresh Hive entry (when [persist]) → returned immediately;
  /// - otherwise → single deduplicated fetch, stored in memory (+ Hive).
  Future<GateResult<T>> runCached<T>(
    String key,
    Duration ttl,
    Future<T> Function() task, {
    bool persist = false,
    T Function(dynamic raw)? decode,
    dynamic Function(T value)? encode,
  }) async {
    // 1. Memory hit.
    final mem = _memory[key];
    if (mem != null && !mem.isExpired) {
      return GateResult(value: mem.value as T, fromCache: true);
    }
    if (mem != null && mem.isExpired) {
      _memory.remove(key);
    }

    // 2. Hive hit (only when persistence requested and box available).
    if (persist && _hiveAvailable) {
      try {
        final raw = _box!.get(key);
        if (raw != null) {
          final envelope = _Envelope.fromJson(Map<dynamic, dynamic>.from(raw));
          final age = DateTime.now().difference(envelope.cachedAt);
          if (age <= ttl) {
            final value = decode != null ? decode(envelope.data) : envelope.data as T;
            // Promote to memory for instant subsequent reads.
            _memory[key] = _MemoryEntry(value, DateTime.now().add(ttl));
            return GateResult(value: value, fromCache: true, hiveAge: age);
          }
        }
      } catch (e) {
        // Corrupt/missing entry — fall through to fetch.
        // ignore: avoid_print
        print('⚠️ ApiGate Hive read failed for $key: $e');
      }
    }

    // 3. Fetch (deduplicated).
    final value = await run<T>(key, task);

    // 4. Store.
    _memory[key] = _MemoryEntry(value, DateTime.now().add(ttl));
    if (persist && _hiveAvailable) {
      try {
        await _box!.put(
          key,
          _Envelope(encode != null ? encode(value) : value, DateTime.now())
              .toJson(),
        );
      } catch (e) {
        // ignore: avoid_print
        print('⚠️ ApiGate Hive write failed for $key: $e');
      }
    }

    return GateResult(value: value, fromCache: false);
  }

  /// True when a persisted Hive entry exists and is within [ttl].
  /// Used for stale-while-revalidate decisions without decoding the value.
  Future<Duration?> hiveAgeOf(String key) async {
    if (!_hiveAvailable) return null;
    try {
      final raw = _box!.get(key);
      if (raw == null) return null;
      final envelope = _Envelope.fromJson(Map<dynamic, dynamic>.from(raw));
      return DateTime.now().difference(envelope.cachedAt);
    } catch (_) {
      return null;
    }
  }

  /// Invalidate one key (memory + Hive).
  Future<void> invalidate(String key) async {
    _memory.remove(key);
    if (_hiveAvailable) {
      try {
        await _box!.delete(key);
      } catch (_) {}
    }
  }

  /// Invalidate every key starting with [prefix] (e.g. 'catalog:').
  Future<void> invalidatePrefix(String prefix) async {
    _memory.removeWhere((k, _) => k.startsWith(prefix));
    if (_hiveAvailable) {
      try {
        final keys = _box!.keys.where((k) => (k as String).startsWith(prefix)).toList();
        await _box!.deleteAll(keys);
      } catch (_) {}
    }
  }

  /// Clear everything (debug/testing).
  Future<void> clearAll() async {
    _memory.clear();
    if (_hiveAvailable) {
      try {
        await _box!.clear();
      } catch (_) {}
    }
  }
}

class _MemoryEntry<T> {
  final T value;
  final DateTime expiry;
  _MemoryEntry(this.value, this.expiry);
  bool get isExpired => DateTime.now().isAfter(expiry);
}

/// JSON helpers for Hive-persisted complex values.
class GateJson {
  static dynamic encodeJson(Object? value) => json.encode(value);
  static dynamic decodeJson(String raw) => json.decode(raw);
}
