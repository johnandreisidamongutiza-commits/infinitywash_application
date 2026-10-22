import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_error.dart';
import 'supabase_service.dart';

class CustomerRegistrationService {
  SupabaseClient get _client => SupabaseService.client;

  Future<Map<String, dynamic>> checkEmail(String email) async {
    return _invoke({'action': 'check', 'email': email});
  }

  Future<void> requestCode({
    required String email,
    Map<String, dynamic>? registrationData,
    bool resend = false,
  }) async {
    await _invoke({
      'action': resend ? 'resend' : 'start',
      'email': email,
      if (registrationData != null) 'registration_data': registrationData,
    });
  }

  Future<void> verifyAndCreate({
    required String email,
    required String code,
    required String password,
  }) async {
    await _invoke({
      'action': 'verify',
      'email': email,
      'code': code,
      'password': password,
    });
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final result = await _client.functions.invoke(
        'customer-registration-otp',
        body: body,
      );
      return result.data is Map<String, dynamic>
          ? result.data as Map<String, dynamic>
          : <String, dynamic>{};
    } on FunctionException catch (error) {
      final detail = error.details;
      var message = error.reasonPhrase ?? 'Registration could not be completed.';
      if (detail is Map && detail['error'] is String) {
        message = detail['error'] as String;
      } else if (detail is String) {
        try {
          final parsed = jsonDecode(detail);
          if (parsed is Map && parsed['error'] is String) {
            message = parsed['error'] as String;
          } else {
            message = detail;
          }
        } catch (_) {
          message = detail;
        }
      }
      throw AppError(message, type: AppErrorType.server, originalError: error);
    } on AppError {
      rethrow;
    } catch (error) {
      throw AppError(
        'Could not reach the registration service. Check your connection and try again.',
        type: AppErrorType.network,
        originalError: error,
      );
    }
  }
}
