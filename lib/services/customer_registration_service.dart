import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_error.dart';
import 'supabase_service.dart';

class CustomerRegistrationService {
  SupabaseClient get _client => SupabaseService.client;

  Future<Map<String, dynamic>> checkEmail(String email) async {
    return _invoke({'action': 'check', 'email': email});
  }

  /// Returns `true` if the given phone number is already registered
  /// by another user in `profiles` or `customers`.
  Future<bool> isPhoneTaken(String normalizedPhone, {String? excludeUserId}) async {
    try {
      final digits = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
      final variants = <String>{normalizedPhone};
      if (digits.startsWith('09') && digits.length == 11) {
        variants.add('+63${digits.substring(1)}');
        variants.add('63${digits.substring(1)}');
        variants.add(digits.substring(1));
      } else if (digits.startsWith('639') && digits.length == 12) {
        variants.add('0${digits.substring(2)}');
        variants.add('+63${digits.substring(2)}');
        variants.add(digits.substring(2));
      } else if (digits.startsWith('9') && digits.length == 10) {
        variants.add('0$digits');
        variants.add('+63$digits');
        variants.add('63$digits');
      }

      var profileQuery = _client
          .from('profiles')
          .select('id, supabase_user_id')
          .inFilter('phone', variants.toList());
      if (excludeUserId != null) {
        profileQuery = profileQuery.neq('supabase_user_id', excludeUserId);
      }
      final profileResult = await profileQuery.limit(1);
      if ((profileResult as List).isNotEmpty) return true;

      final customerResult = await _client
          .from('customers')
          .select('id')
          .inFilter('phone', variants.toList())
          .limit(1);
      return (customerResult as List).isNotEmpty;
    } catch (_) {
      // On error, don't block the user — let server-side validation catch it.
      return false;
    }
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
