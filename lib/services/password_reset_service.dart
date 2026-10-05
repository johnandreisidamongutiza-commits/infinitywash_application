import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_error.dart';
import 'supabase_service.dart';

/// Result of a successful "request" call.
class ResetRequestResult {
  final String email;
  final int attemptsLeft;

  const ResetRequestResult({required this.email, required this.attemptsLeft});
}

/// Client for the server-side password reset flow.
///
/// All security-sensitive work (code generation, hashing, attempt counting,
/// rate limiting, SMTP delivery and the actual auth password update) happens
/// inside the `password-reset` Edge Function using the service role key.
/// This client only relays user input and surfaces server messages, so no
/// secret and no decision authority lives in the app.
class PasswordResetService {
  static const _functionName = 'password-reset';

  SupabaseClient get _client => SupabaseService.client;

  /// Ask the server to generate a reset code and email it to [email].
  ///
  /// Throws with a user-facing message when the account is unknown, inactive
  /// or rate limited.
  Future<ResetRequestResult> requestPasswordReset(String email) async {
    final data = await _invoke({'action': 'request', 'email': email});
    return ResetRequestResult(
      email: (data['email'] as String?) ?? email,
      attemptsLeft: (data['attempts_left'] as num?)?.toInt() ?? 0,
    );
  }

  /// Verify a reset code. Throws with a user-facing message on failure.
  Future<void> verifyResetCode(String email, String code) async {
    await _invoke({'action': 'verify', 'email': email, 'code': code});
  }

  /// Reset the password. The server re-verifies [code] before applying
  /// [newPassword]; a stale or wrong code is rejected here.
  Future<void> resetPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    await _invoke({
      'action': 'reset',
      'email': email,
      'code': code,
      'new_password': newPassword,
    });
  }

  /// Verify the code and reset the password in one server round-trip.
  Future<void> verifyAndResetPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    await resetPassword(email, code, newPassword);
  }

  /// Resend is the same operation as request (the server invalidates the old
  /// code and enforces the hourly limit).
  Future<ResetRequestResult> resendResetCode(String email) async {
    return requestPasswordReset(email);
  }

  /// Invoke the Edge Function and return its JSON payload.
  ///
  /// Function errors arrive as [FunctionException] whose detail holds the
  /// JSON body the function returned, e.g. {"error": "Invalid code. 4
  /// attempts remaining."}. Surface that message so the UI shows exactly
  /// what the server decided.
  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions.invoke(
        _functionName,
        body: body,
      );
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      return {};
    } on FunctionException catch (e) {
      throw AppError(
        _extractMessage(e),
        type: AppErrorType.server,
        originalError: e,
        stackTrace: StackTrace.current,
      );
    } on AppError {
      rethrow;
    } catch (e) {
      // Network or unexpected failure — keep it generic but actionable.
      throw AppError(
        'Could not reach the password reset service. '
        'Check your connection and try again.',
        type: AppErrorType.network,
        originalError: e,
        stackTrace: StackTrace.current,
      );
    }
  }

  String _extractMessage(FunctionException e) {
    final detail = e.details;

    // detail can already be a decoded map, a JSON string, or a plain string.
    if (detail is Map) {
      final message = detail['error'];
      if (message is String && message.isNotEmpty) return message;
    } else if (detail is String && detail.isNotEmpty) {
      try {
        final decoded = jsonDecode(detail);
        if (decoded is Map) {
          final message = decoded['error'];
          if (message is String && message.isNotEmpty) return message;
        }
      } catch (_) {
        // Not JSON — fall through to the raw text.
      }
      return detail;
    }

    return e.reasonPhrase ?? 'Password reset request failed.';
  }
}
