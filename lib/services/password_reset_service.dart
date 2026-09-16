import 'dart:math';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'supabase_service.dart';

class PasswordResetService {
  final _client = SupabaseService.client;
  
  /// Check if an account exists with the given email (case-insensitive)
  Future<Map<String, dynamic>?> _findAccountByEmail(String email) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      
      // Try exact match first
      final exactProfile = await _client
          .from('profiles')
          .select('email, supabase_user_id, first_name, last_name, role, status')
          .eq('email', email.trim())
          .maybeSingle();
      
      if (exactProfile != null) {
        return exactProfile;
      }
      
      // Try case-insensitive search
      final profiles = await _client
          .from('profiles')
          .select('email, supabase_user_id, first_name, last_name, role, status')
          .ilike('email', normalizedEmail)
          .limit(1);
      
      if (profiles.isNotEmpty) {
        return profiles.first;
      }
      
      return null;
    } catch (e) {
      print('⚠️ Error searching for account: $e');
      return null;
    }
  }
  
  // Generate a 6-character code: 3 random letters (upper/lower) + 3 random numbers
  String _generateResetCode() {
    final random = Random.secure();
    final letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    final numbers = '0123456789';
    
    // Generate 3 random letters
    String code = '';
    for (int i = 0; i < 3; i++) {
      code += letters[random.nextInt(letters.length)];
    }
    
    // Generate 3 random numbers
    for (int i = 0; i < 3; i++) {
      code += numbers[random.nextInt(numbers.length)];
    }
    
    return code;
  }
  
  // Hash the code for secure storage
  String _hashCode(String code) {
    final bytes = utf8.encode(code);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  /// Request a password reset - generates code and sends email
  /// Returns the reset token ID and email
  Future<Map<String, String>> requestPasswordReset(String email) async {
    try {
      // 1. Find the account in profiles table
      final profile = await _findAccountByEmail(email);
      
      if (profile == null) {
        throw Exception('No account found with this email address. Please check your email or sign up.');
      }
      
      final userEmail = profile['email'] as String;
      final userId = profile['supabase_user_id'] as String?;
      final firstName = profile['first_name'] as String?;
      final lastName = profile['last_name'] as String?;
      final role = profile['role'] as String?;
      final status = profile['status'] as String?;
      
      // 2. Check if account is active
      if (status != null && status.toLowerCase() != 'active') {
        throw Exception('This account is not active. Please contact support.');
      }
      
      // 3. Invalidate any existing unused tokens for this email
      await _client
          .from('password_reset_tokens')
          .update({'used': true})
          .eq('email', userEmail)
          .eq('used', false);
      
      // 4. Generate new reset code
      final code = _generateResetCode();
      final codeHash = _hashCode(code);
      final now = DateTime.now().toUtc();
      final expiresAt = now.add(const Duration(minutes: 15));
      
      // 5. Insert new reset token
      final response = await _client
          .from('password_reset_tokens')
          .insert({
            'email': userEmail,
            'code_hash': codeHash,
            'expires_at': expiresAt.toIso8601String(),
            'sent_at': now.toIso8601String(),
            'attempts': 0,
            'used': false,
            'created_at': now.toIso8601String(),
          })
          .select('id')
          .single();
      
      final tokenId = response['id'] as String;
      
      // 6. TODO: Send email with the code via SMTP
      // For production, integrate with your email service (SendGrid, Resend, etc.)
      print('📧 Password reset code sent to: $userEmail');
      
      return {
        'token_id': tokenId,
        'email': userEmail,
        'first_name': firstName ?? '',
        'last_name': lastName ?? '',
        'role': role ?? '',
      };
    } catch (e) {
      print('❌ Password reset request failed: $e');
      rethrow;
    }
  }
  
  /// Verify the reset code
  Future<String?> verifyResetCode(String email, String code) async {
    try {
      // 1. Get the most recent non-used token for this email
      final token = await _client
          .from('password_reset_tokens')
          .select('id, code_hash, expires_at, attempts, used')
          .eq('email', email)
          .eq('used', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      
      if (token == null) {
        throw Exception('No valid reset request found. Please request a new code.');
      }
      
      // 2. Check if token has expired
      final expiresAt = DateTime.parse(token['expires_at'] as String);
      if (DateTime.now().toUtc().isAfter(expiresAt)) {
        throw Exception('Reset code has expired. Please request a new code.');
      }
      
      // 3. Check attempt limit (max 5 attempts)
      final attempts = token['attempts'] as int;
      if (attempts >= 5) {
        // Mark as used to prevent further attempts
        await _client
            .from('password_reset_tokens')
            .update({'used': true})
            .eq('id', token['id']);
        throw Exception('Too many failed attempts. Please request a new code.');
      }
      
      // 4. Verify the code
      final codeHash = _hashCode(code);
      final storedHash = token['code_hash'] as String;
      
      if (codeHash != storedHash) {
        // Increment attempts
        await _client
            .from('password_reset_tokens')
            .update({'attempts': attempts + 1})
            .eq('id', token['id']);
        
        final remainingAttempts = 5 - (attempts + 1);
        throw Exception('Invalid code. $remainingAttempts attempts remaining.');
      }
      
      // 5. Code is valid - return the token ID for the next step
      return token['id'] as String;
    } catch (e) {
      print('❌ Code verification failed: $e');
      rethrow;
    }
  }
  
  /// Reset the password using verified token
  Future<void> resetPassword(String tokenId, String newPassword) async {
    try {
      // 1. Get the token to find the email
      final token = await _client
          .from('password_reset_tokens')
          .select('email, expires_at, used')
          .eq('id', tokenId)
          .single();

      if (token['used'] == true) {
        throw Exception('This reset link has already been used.');
      }

      final expiresAt = DateTime.parse(token['expires_at'] as String);
      if (DateTime.now().toUtc().isAfter(expiresAt)) {
        throw Exception('Reset link has expired. Please request a new code.');
      }

      final email = token['email'] as String;
      
      print('🔐 Resetting password for: $email');

      // 2. Call the database function to reset password
      final result = await _client.rpc(
        'reset_user_password',
        params: {
          'user_email': email,
          'new_password': newPassword,
          'reset_token_id': tokenId,
        },
      );

      print('📝 Result: $result');

      // Check if successful
      if (result is Map && result['success'] == true) {
        print('✅ Password reset successful');
        return;
      } else {
        final error = result is Map ? result['error'] : 'Unknown error';
        throw Exception(error);
      }

    } catch (e) {
      print('❌ Password reset failed: $e');
      
      // Provide helpful error messages
      if (e.toString().contains('function reset_user_password') ||
          e.toString().contains('does not exist')) {
        throw Exception(
          'Password reset database function not found. '
          'Please run the SQL setup script in your Supabase dashboard. '
          'See FIX_MISSING_PROFILE.md for instructions.'
        );
      }
      
      rethrow;
    }
  }
  
  /// Combined method: Verify code and reset password in one step
  Future<void> verifyAndResetPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    // Step 1: Verify the code
    final tokenId = await verifyResetCode(email, code);
    
    if (tokenId == null) {
      throw Exception('Code verification failed');
    }
    
    // Step 2: Reset the password
    await resetPassword(tokenId, newPassword);
  }
  
  /// Resend a new code (invalidates the old one)
  Future<Map<String, String>> resendResetCode(String email) async {
    return await requestPasswordReset(email);
  }
  
  /// Clean up expired tokens (should be run periodically)
  Future<void> cleanupExpiredTokens() async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _client
          .from('password_reset_tokens')
          .delete()
          .lt('expires_at', now);
      
      print('✅ Expired tokens cleaned up');
    } catch (e) {
      print('❌ Token cleanup failed: $e');
    }
  }
}
