import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infinitywash/utils/app_error.dart';

void main() {
  group('mapErrorToMessage — network errors', () {
    test('SocketException → offline message', () {
      const err = SocketException('Failed host lookup');
      expect(mapErrorToMessage(err), contains('No internet connection'));
    });

    test('http.ClientException → offline message', () {
      final err = http.ClientException('Connection closed');
      expect(mapErrorToMessage(err), contains('No internet connection'));
    });

    test('TimeoutException → timeout message', () {
      final err = TimeoutException('Operation timed out');
      final msg = mapErrorToMessage(err);
      expect(msg, contains('timed out'));
      expect(msg.toLowerCase(), isNot(contains('exception')));
    });

    test('wrapped socket failure string → offline message', () {
      final msg = mapErrorToMessage(
        Exception('SocketException: Failed host lookup (errno = 7)'),
      );
      expect(msg, contains('No internet connection'));
    });
  });

  group('mapErrorToMessage — auth errors', () {
    test('invalid_credentials code → wrong password message', () {
      final err = AuthApiException(
        'Invalid login credentials',
        code: 'invalid_credentials',
      );
      final msg = mapErrorToMessage(err);
      expect(msg, contains('Incorrect email or password'));
    });

    test('email_not_confirmed code → confirmation message', () {
      final err = AuthApiException('Email not confirmed', code: 'email_not_confirmed');
      expect(mapErrorToMessage(err), contains('not confirmed'));
    });

    test('email_exists code → account exists message', () {
      final err = AuthApiException('User already registered', code: 'email_exists');
      final msg = mapErrorToMessage(err);
      expect(msg, contains('already exists'));
    });

    test('over_request_rate_limit → rate limit message', () {
      final err = AuthApiException(
        'Too many requests',
        code: 'over_request_rate_limit',
      );
      expect(mapErrorToMessage(err), contains('Too many attempts'));
    });

    test('message sniff fallback for generic AuthException', () {
      final err = AuthException('Invalid login credentials', statusCode: '400');
      expect(mapErrorToMessage(err), contains('Incorrect email or password'));
    });
  });

  group('mapErrorToMessage — database errors', () {
    test('duplicate key (23505) → duplicate message', () {
      final err = PostgrestException(code: '23505', message: 'duplicate key value violates unique constraint "orders_order_number_key"', details: null, hint: null);
      final msg = mapErrorToMessage(err);
      expect(msg, contains('already exists'));
      // Must NOT leak the constraint name.
      expect(msg, isNot(contains('orders_order_number_key')));
    });

    test('permission denied (42501) → permission message', () {
      final err = PostgrestException(code: '42501', message: 'new row violates row-level security policy', details: null, hint: null);
      final msg = mapErrorToMessage(err);
      expect(msg, contains('permission'));
      expect(msg, isNot(contains('row-level')));
    });

    test('bad input (22P02) → validation message', () {
      final err = PostgrestException(code: '22P02', message: 'invalid input syntax for type uuid', details: null, hint: null);
      expect(mapErrorToMessage(err), contains('not valid'));
    });

    test('no rows (PGRST116) → not-found message', () {
      final err = PostgrestException(code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned', details: null, hint: null);
      expect(mapErrorToMessage(err), contains('could not find'));
    });

    test('unknown DB error → generic server message without raw SQL', () {
      final err = PostgrestException(code: 'XX000', message: 'internal error: some internal detail users should never see', details: null, hint: null);
      final msg = mapErrorToMessage(err);
      expect(msg, isNot(contains('users should never see')));
    });
  });

  group('mapErrorToMessage — app-specific signals', () {
    test('ACCOUNT_DEACTIVATED with reason → deactivation message with reason', () {
      final msg = mapErrorToMessage(
        Exception('ACCOUNT_DEACTIVATED:Violated service terms'),
      );
      expect(msg, contains('deactivated'));
      expect(msg, contains('Violated service terms'));
    });

    test('human-authored Exception message is preserved', () {
      final msg = mapErrorToMessage(
        Exception('You have already submitted feedback for this order.'),
      );
      expect(msg, contains('already submitted feedback'));
    });

    test('raw exception dump falls back to a generic message', () {
      final msg = mapErrorToMessage(
        Exception(
          'PostgrestException(message: duplicate key value violates unique constraint, code: 23505)',
        ),
      );
      // Raw marker → humanizer rejects → friendly generic message.
      expect(msg, isNot(contains('PostgrestException')));
    });
  });

  group('mapErrorToMessage — data errors', () {
    test('FormatException → data-format message', () {
      const err = FormatException('Unexpected character');
      final msg = mapErrorToMessage(err);
      expect(msg, contains('unexpected format'));
      expect(msg, isNot(contains('Unexpected character')));
    });

    test('TypeError → generic load message', () {
      final msg = mapErrorToMessage(
        _typeError(),
      );
      expect(msg, contains('did not load correctly'));
    });

    test('unknown Error → generic message', () {
      final msg = mapErrorToMessage(StateError('Bad state: no element'));
      expect(msg, isNot(contains('Bad state')));
      expect(msg, contains('Something went wrong'));
    });
  });

  group('mapError — AppError passthrough and typing', () {
    test('already-mapped AppError is returned unchanged', () {
      const original = AppError('Custom message', type: AppErrorType.validation);
      final result = mapError(original);
      expect(identical(original, result), isTrue);
    });

    test('network errors are flagged via isNetwork', () {
      final result = mapError(const SocketException('offline'));
      expect(result.isNetwork, isTrue);
      expect(result.type, AppErrorType.network);
    });

    test('timeout errors are flagged via isNetwork', () {
      final result = mapError(TimeoutException('t'));
      expect(result.isNetwork, isTrue);
      expect(result.type, AppErrorType.timeout);
    });

    test('auth errors carry the auth type', () {
      final result = mapError(
        AuthApiException('Invalid login credentials', code: 'invalid_credentials'),
      );
      expect(result.type, AppErrorType.auth);
    });
  });
}

TypeError _typeError() {
  try {
    // Trigger a genuine TypeError.
    final list = <int>[];
    (list as dynamic).add('not an int');
    // The line above throws; silence the analyzer about unreachable code.
    throw UnsupportedError('unreachable');
  } on TypeError catch (e) {
    return e;
  }
}
