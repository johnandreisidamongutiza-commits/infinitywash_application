import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

/// Service to manage rate limiting for OTP resend requests
class RateLimitService {
  static const _storage = FlutterSecureStorage();
  static const String _rateLimitKey = 'otp_rate_limit';
  static const int maxAttemptsPerEmail = 3; // Max 3 resend attempts
  static const Duration resetDuration = Duration(hours: 1); // Reset after 1 hour

  /// Check if user can send OTP (not rate limited)
  static Future<RateLimitResult> canSendOtp(String email) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final dataJson = await _storage.read(key: _rateLimitKey);
      
      if (dataJson == null) {
        // No rate limit data exists
        return RateLimitResult(canSend: true, attemptsLeft: maxAttemptsPerEmail);
      }

      final Map<String, dynamic> allData = json.decode(dataJson);
      
      if (!allData.containsKey(normalizedEmail)) {
        // No data for this email
        return RateLimitResult(canSend: true, attemptsLeft: maxAttemptsPerEmail);
      }

      final emailData = allData[normalizedEmail] as Map<String, dynamic>;
      final attempts = emailData['attempts'] as int;
      final lastAttemptTime = DateTime.parse(emailData['lastAttempt'] as String);
      
      // Check if rate limit period has expired
      final timeSinceLastAttempt = DateTime.now().difference(lastAttemptTime);
      if (timeSinceLastAttempt >= resetDuration) {
        // Reset the counter
        await _resetRateLimit(normalizedEmail);
        return RateLimitResult(canSend: true, attemptsLeft: maxAttemptsPerEmail);
      }
      
      // Check if user has exceeded max attempts
      if (attempts >= maxAttemptsPerEmail) {
        final remainingTime = resetDuration - timeSinceLastAttempt;
        return RateLimitResult(
          canSend: false,
          attemptsLeft: 0,
          remainingTime: remainingTime,
          message: 'Too many attempts. Please try again in ${_formatDuration(remainingTime)}.',
        );
      }
      
      return RateLimitResult(
        canSend: true,
        attemptsLeft: maxAttemptsPerEmail - attempts,
      );
    } catch (e) {
      print('⚠️ Rate limit check error: $e');
      // On error, allow the request but log it
      return RateLimitResult(canSend: true, attemptsLeft: maxAttemptsPerEmail);
    }
  }

  /// Record an OTP send attempt
  static Future<void> recordAttempt(String email) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final dataJson = await _storage.read(key: _rateLimitKey);
      
      Map<String, dynamic> allData = {};
      if (dataJson != null) {
        allData = json.decode(dataJson);
      }

      final currentData = allData[normalizedEmail] as Map<String, dynamic>?;
      
      if (currentData == null) {
        // First attempt
        allData[normalizedEmail] = {
          'attempts': 1,
          'lastAttempt': DateTime.now().toIso8601String(),
        };
      } else {
        // Increment attempts
        final attempts = currentData['attempts'] as int;
        final lastAttemptTime = DateTime.parse(currentData['lastAttempt'] as String);
        final timeSinceLastAttempt = DateTime.now().difference(lastAttemptTime);
        
        // If more than resetDuration has passed, reset counter
        if (timeSinceLastAttempt >= resetDuration) {
          allData[normalizedEmail] = {
            'attempts': 1,
            'lastAttempt': DateTime.now().toIso8601String(),
          };
        } else {
          allData[normalizedEmail] = {
            'attempts': attempts + 1,
            'lastAttempt': DateTime.now().toIso8601String(),
          };
        }
      }

      await _storage.write(key: _rateLimitKey, value: json.encode(allData));
      print('📊 Rate limit recorded for $normalizedEmail: ${allData[normalizedEmail]['attempts']} attempts');
    } catch (e) {
      print('⚠️ Failed to record rate limit: $e');
    }
  }

  /// Reset rate limit for a specific email
  static Future<void> _resetRateLimit(String email) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final dataJson = await _storage.read(key: _rateLimitKey);
      
      if (dataJson == null) return;

      final Map<String, dynamic> allData = json.decode(dataJson);
      allData.remove(normalizedEmail);
      
      await _storage.write(key: _rateLimitKey, value: json.encode(allData));
      print('🔄 Rate limit reset for $normalizedEmail');
    } catch (e) {
      print('⚠️ Failed to reset rate limit: $e');
    }
  }

  /// Clear all rate limit data (for testing/debugging)
  static Future<void> clearAll() async {
    try {
      await _storage.delete(key: _rateLimitKey);
      print('🗑️ All rate limit data cleared');
    } catch (e) {
      print('⚠️ Failed to clear rate limit data: $e');
    }
  }

  /// Get current rate limit status for an email
  static Future<Map<String, dynamic>> getStatus(String email) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final dataJson = await _storage.read(key: _rateLimitKey);
      
      if (dataJson == null) {
        return {
          'attempts': 0,
          'maxAttempts': maxAttemptsPerEmail,
          'attemptsLeft': maxAttemptsPerEmail,
          'canSend': true,
        };
      }

      final Map<String, dynamic> allData = json.decode(dataJson);
      
      if (!allData.containsKey(normalizedEmail)) {
        return {
          'attempts': 0,
          'maxAttempts': maxAttemptsPerEmail,
          'attemptsLeft': maxAttemptsPerEmail,
          'canSend': true,
        };
      }

      final emailData = allData[normalizedEmail] as Map<String, dynamic>;
      final attempts = emailData['attempts'] as int;
      final lastAttemptTime = DateTime.parse(emailData['lastAttempt'] as String);
      final timeSinceLastAttempt = DateTime.now().difference(lastAttemptTime);
      
      if (timeSinceLastAttempt >= resetDuration) {
        return {
          'attempts': 0,
          'maxAttempts': maxAttemptsPerEmail,
          'attemptsLeft': maxAttemptsPerEmail,
          'canSend': true,
        };
      }

      return {
        'attempts': attempts,
        'maxAttempts': maxAttemptsPerEmail,
        'attemptsLeft': maxAttemptsPerEmail - attempts,
        'canSend': attempts < maxAttemptsPerEmail,
        'lastAttempt': lastAttemptTime.toIso8601String(),
        'resetIn': resetDuration - timeSinceLastAttempt,
      };
    } catch (e) {
      print('⚠️ Failed to get rate limit status: $e');
      return {
        'attempts': 0,
        'maxAttempts': maxAttemptsPerEmail,
        'attemptsLeft': maxAttemptsPerEmail,
        'canSend': true,
      };
    }
  }

  /// Format duration for user display
  static String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      final minutes = duration.inMinutes.remainder(60);
      return '${duration.inHours}h ${minutes}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes} minute${duration.inMinutes > 1 ? 's' : ''}';
    } else {
      return '${duration.inSeconds} seconds';
    }
  }
}

/// Result of rate limit check
class RateLimitResult {
  final bool canSend;
  final int attemptsLeft;
  final Duration? remainingTime;
  final String? message;

  RateLimitResult({
    required this.canSend,
    required this.attemptsLeft,
    this.remainingTime,
    this.message,
  });

  @override
  String toString() {
    return 'RateLimitResult(canSend: $canSend, attemptsLeft: $attemptsLeft, message: $message)';
  }
}
