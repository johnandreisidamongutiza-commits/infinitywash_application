import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Categories of user-facing errors. Used to pick icons/titles in the UI.
enum AppErrorType {
  network,
  timeout,
  auth,
  database,
  storage,
  validation,
  notFound,
  permission,
  server,
  unknown,
}

/// A user-presentable error. Thrown (or wrapped) by services after mapping
/// low-level exceptions so screens never have to display raw stack traces.
class AppError implements Exception {
  /// Friendly message safe to show to the user.
  final String message;

  final AppErrorType type;

  /// The original error, kept for logging only — never shown to users.
  final Object? originalError;

  final StackTrace? stackTrace;

  const AppError(
    this.message, {
    this.type = AppErrorType.unknown,
    this.originalError,
    this.stackTrace,
  });

  bool get isNetwork => type == AppErrorType.network || type == AppErrorType.timeout;

  @override
  String toString() => message;
}

/// Marker prefix thrown by [AuthService] when an account is deactivated.
/// Preserved as a signal (not shown verbatim to users); [mapErrorToMessage]
/// converts it to the friendly deactivation dialog text.
const String kAccountDeactivatedPrefix = 'ACCOUNT_DEACTIVATED:';

/// Convert any thrown error into a friendly, user-safe message.
///
/// Never leaks raw exception text (SQL, stack traces, URLs) to the UI.
String mapErrorToMessage(Object error) => mapError(error).message;

/// Convert any thrown error into a typed [AppError] with a friendly message.
AppError mapError(Object error, {StackTrace? stackTrace}) {
  // Already mapped — pass through.
  if (error is AppError) return error;

  final st = stackTrace;

  // ── Controlled app signals ────────────────────────────────────────────────
  final raw = error.toString();
  if (raw.contains(kAccountDeactivatedPrefix)) {
    final reason = raw.split(kAccountDeactivatedPrefix).last.trim();
    return AppError(
      'Your account has been deactivated.\n\nReason: $reason',
      type: AppErrorType.auth,
      originalError: error,
      stackTrace: st,
    );
  }

  // ── Supabase auth ─────────────────────────────────────────────────────────
  if (error is AuthApiException) {
    return AppError(_authMessage(error), type: AppErrorType.auth, originalError: error, stackTrace: st);
  }
  if (error is AuthException) {
    return AppError(
      _authMessage(error),
      type: AppErrorType.auth,
      originalError: error,
      stackTrace: st,
    );
  }

  // ── Supabase database ─────────────────────────────────────────────────────
  if (error is PostgrestException) {
    return AppError(_postgrestMessage(error), type: AppErrorType.database, originalError: error, stackTrace: st);
  }

  // ── Supabase storage ──────────────────────────────────────────────────────
  if (error is StorageException) {
    return AppError(
      _storageMessage(error),
      type: AppErrorType.storage,
      originalError: error,
      stackTrace: st,
    );
  }

  // ── Network / timeouts ────────────────────────────────────────────────────
  if (error is SocketException || error is http.ClientException) {
    return const AppError(
      'No internet connection. Please check your connection and try again.',
      type: AppErrorType.network,
    );
  }
  if (error is TimeoutException) {
    return const AppError(
      'The request timed out. Your connection may be slow — please try again.',
      type: AppErrorType.timeout,
    );
  }

  // ── Data / programming errors ─────────────────────────────────────────────
  // Typed errors are checked BEFORE the humanizer so that e.g. a
  // FormatException whose text happens to read cleanly still maps to the
  // data-format message rather than leaking the parse detail.
  if (error is FormatException) {
    return const AppError(
      'The server returned data in an unexpected format. Please try again.',
      type: AppErrorType.server,
    );
  }

  // ── Plain Exceptions with an app-authored message ─────────────────────────
  // Services throw Exception('Friendly message...') all over the codebase.
  // When the message looks human-authored, show it; when it looks like a raw
  // dump (SQL, stack frames, type names), fall back to the generic text.
  if (error is Exception && error is! AppError) {
    final friendly = _humanizeExceptionText(raw);
    if (friendly != null) {
      return AppError(friendly, type: _sniffType(raw), originalError: error, stackTrace: st);
    }
  }
  if (error is TypeError) {
    return const AppError(
      'Something did not load correctly. Please try again.',
      type: AppErrorType.server,
    );
  }
  if (error is ArgumentError) {
    return const AppError(
      'Some required information is missing or invalid. Please review your entries.',
      type: AppErrorType.validation,
    );
  }

  // ── String-sniffed fallbacks (wrapped exceptions from plugins/HTTP) ───────
  return AppError(_sniffMessage(raw), type: _sniffType(raw), originalError: error, stackTrace: st);
}

/// Returns the message inside `Exception: ...` when it looks intentionally
/// human-authored, otherwise null (caller falls back to generic text).
String? _humanizeExceptionText(String raw) {
  var text = raw;
  if (text.startsWith('Exception: ')) text = text.substring('Exception: '.length);
  text = text.trim();
  if (text.isEmpty || text.length > 200) return null;

  final lower = text.toLowerCase();
  const rawMarkers = [
    'postgrestexception', 'socketexception', 'clientexception', 'timeoutexception',
    'storageexception', 'functionexception', 'authapiexception', 'stacktrace',
    'instance of', 'type \'', 'bad state', 'sqlstate', 'at #', '{', '}',
  ];
  for (final marker in rawMarkers) {
    if (lower.contains(marker)) return null;
  }
  // Uppercase the first letter for presentation.
  return text[0].toUpperCase() + text.substring(1);
}

AppErrorType _sniffType(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('connection timed out') ||
      lower.contains('network is unreachable') ||
      lower.contains('xmlhttprequest error') ||
      lower.contains('no internet') ||
      lower.contains('offline')) {
    return AppErrorType.network;
  }
  if (lower.contains('timeoutexception') || lower.contains('timed out') || lower.contains('deadline exceeded')) {
    return AppErrorType.timeout;
  }
  if (lower.contains('unauthorized') || lower.contains('forbidden') || lower.contains('401') || lower.contains('403')) {
    return AppErrorType.permission;
  }
  if (lower.contains('500') || lower.contains('502') || lower.contains('503') || lower.contains('server error')) {
    return AppErrorType.server;
  }
  return AppErrorType.unknown;
}

String _sniffMessage(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('connection timed out') ||
      lower.contains('network is unreachable') ||
      lower.contains('xmlhttprequest error')) {
    return 'No internet connection. Please check your connection and try again.';
  }
  if (lower.contains('timeoutexception') || lower.contains('timed out') || lower.contains('deadline exceeded')) {
    return 'The request timed out. Please try again.';
  }
  if (lower.contains('unauthorized') || lower.contains('401') || lower.contains('jwt expired')) {
    return 'Your session has expired. Please sign in again.';
  }
  if (lower.contains('forbidden') || lower.contains('403')) {
    return 'You do not have permission to do that.';
  }
  if (lower.contains('500') || lower.contains('502') || lower.contains('503') || lower.contains('internal server error')) {
    return 'The server is having trouble right now. Please try again in a moment.';
  }
  if (lower.contains('not found') || lower.contains('404')) {
    return 'We could not find what you were looking for. It may have been removed.';
  }
  return 'Something went wrong. Please try again.';
}

String _authMessage(AuthException error) {
  final code = (error is AuthApiException) ? (error.code ?? '') : '';
  switch (code) {
    case 'invalid_credentials':
      return 'Incorrect email or password. Please try again.';
    case 'email_not_confirmed':
      return 'Your email is not confirmed yet. Please check your inbox for the confirmation link.';
    case 'user_not_found':
      return 'No account found with that email address.';
    case 'user_banned':
      return 'This account has been suspended. Please contact support.';
    case 'email_exists':
    case 'user_already_exists':
      return 'An account with this email already exists. Try signing in instead.';
    case 'weak_password':
      return 'That password is too weak. Please use at least 6 characters with a mix of letters and numbers.';
    case 'same_password':
      return 'Your new password must be different from the old one.';
    case 'over_request_rate_limit':
    case 'over_email_send_rate_limit':
      return 'Too many attempts. Please wait a minute and try again.';
    case 'otp_expired':
    case 'token_expired':
      return 'That link or code has expired. Please request a new one.';
    case 'refresh_token_not_found':
    case 'bad_jwt':
      return 'Your session has expired. Please sign in again.';
    case 'phone_not_confirmed':
      return 'Your phone number is not confirmed yet.';
    case 'validation_failed':
      return 'Please check the information you entered and try again.';
  }

  final msg = error.message.toLowerCase();
  if (msg.contains('invalid login credentials')) {
    return 'Incorrect email or password. Please try again.';
  }
  if (msg.contains('email not confirmed')) {
    return 'Your email is not confirmed yet. Please check your inbox for the confirmation link.';
  }
  if (msg.contains('rate limit')) {
    return 'Too many attempts. Please wait a minute and try again.';
  }
  if (msg.contains('password')) {
    return 'Please check your password and try again. New passwords must be at least 6 characters.';
  }
  if (msg.contains('session') || msg.contains('token')) {
    return 'Your session has expired. Please sign in again.';
  }
  return 'Sign-in failed. Please check your details and try again.';
}

String _postgrestMessage(PostgrestException error) {
  switch (error.code) {
    case '23505':
      return 'That record already exists. Please check for duplicates and try again.';
    case '23503':
      return 'This action refers to a record that no longer exists. Please refresh and try again.';
    case '23502':
      return 'Some required information is missing. Please complete all required fields.';
    case '23514':
      return 'One of the values entered is not allowed. Please review your entries.';
    case '22P02':
      return 'One of the values entered is not valid. Please review your entries.';
    case '42501':
      return 'You do not have permission to do that.';
    case '42P01':
      return 'Part of the service is unavailable right now. Please try again later.';
    case '42703':
      return 'Part of the service is unavailable right now. Please update the app and try again.';
    case 'PGRST116':
      return 'We could not find that record. It may have been removed.';
    case 'PGRST301':
    case 'PGRST302':
      return 'Your session has expired. Please sign in again.';
  }

  final msg = error.message.toLowerCase();
  if (msg.contains('duplicate key')) {
    return 'That record already exists.';
  }
  if (msg.contains('row-level security') || msg.contains('permission denied')) {
    return 'You do not have permission to do that.';
  }
  if (msg.contains('jwt') || msg.contains('expired')) {
    return 'Your session has expired. Please sign in again.';
  }
  if (msg.contains('violates') || msg.contains('constraint')) {
    return 'One of the values entered is not allowed. Please review your entries.';
  }
  return 'The server could not complete that request. Please try again in a moment.';
}

String _storageMessage(StorageException error) {
  final status = error.statusCode ?? '';
  if (status == '404') {
    return 'The file could not be found on the server.';
  }
  if (status == '413') {
    return 'That file is too large. Please choose a smaller file.';
  }
  final msg = error.message.toLowerCase();
  if (msg.contains('payload too large') || msg.contains('too large')) {
    return 'That file is too large. Please choose a smaller file.';
  }
  if (msg.contains('not found') || status == '400') {
    return 'The file could not be uploaded. Please try a different file.';
  }
  return 'The file could not be uploaded right now. Please check your connection and try again.';
}
