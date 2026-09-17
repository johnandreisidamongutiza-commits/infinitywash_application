import 'dart:math';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'supabase_service.dart';
import 'smtp_service.dart';
import 'rate_limit_service.dart';

class PasswordResetService {
  final _client = SupabaseService.client;
  final _smtpService = SmtpService();
  
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
      print('🔐 Password reset requested for: $email');
      
      // 1. Check rate limit
      final rateLimitCheck = await RateLimitService.canSendOtp(email);
      if (!rateLimitCheck.canSend) {
        throw Exception(rateLimitCheck.message ?? 'Too many attempts. Please try again later.');
      }
      
      print('✅ Rate limit check passed. Attempts left: ${rateLimitCheck.attemptsLeft}');
      
      // 2. Find the account in profiles table
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
      
      print('👤 Account found: $userEmail (Status: $status)');
      
      // 3. Check if account is active
      if (status != null && status.toLowerCase() != 'active') {
        throw Exception('This account is not active. Please contact support.');
      }
      
      // 4. Invalidate any existing unused tokens for this email
      print('🔄 Invalidating old tokens...');
      await _client
          .from('password_reset_tokens')
          .update({'used': true})
          .eq('email', userEmail)
          .eq('used', false);
      
      // 5. Generate new reset code
      print('🎲 Generating reset code...');
      final code = _generateResetCode();
      final codeHash = _hashCode(code);
      final now = DateTime.now().toUtc();
      final expiresAt = now.add(const Duration(minutes: 15));
      
      print('💾 Saving reset token to database...');
      
      // 6. Insert new reset token
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
      print('✅ Token saved with ID: $tokenId');
      
      // 7. Send email with the reset code
      print('📧 Sending reset email...');
      await _sendResetEmail(userEmail, code, firstName ?? '');
      
      // 8. Record rate limit attempt
      await RateLimitService.recordAttempt(email);
      print('📊 Rate limit recorded');
      
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
  /// This uses Supabase RPC function to update password with admin privileges
  Future<void> resetPassword(String tokenId, String newPassword) async {
    try {
      print('🔐 Attempting to reset password with token: $tokenId');

      // 1. Get the token details to find the user
      final tokenData = await _client
          .from('password_reset_tokens')
          .select('email, used, expires_at')
          .eq('id', tokenId)
          .single();

      print('📧 Token found for email: ${tokenData['email']}');

      // 2. Verify token is still valid
      if (tokenData['used'] == true) {
        throw Exception('This reset code has already been used. Please request a new one.');
      }

      final expiresAt = DateTime.parse(tokenData['expires_at'] as String);
      if (DateTime.now().toUtc().isAfter(expiresAt)) {
        throw Exception('This reset code has expired. Please request a new one.');
      }

      final userEmail = tokenData['email'] as String;

      // 3. Get the user's Supabase user ID from profiles
      final profile = await _client
          .from('profiles')
          .select('supabase_user_id')
          .eq('email', userEmail)
          .single();

      final userId = profile['supabase_user_id'] as String?;
      
      if (userId == null) {
        throw Exception('User account not found');
      }

      print('👤 Found user ID: $userId');

      // 4. Call the database function to reset password
      // This function must be created in Supabase with SECURITY DEFINER
      try {
        print('🔧 Calling RPC function: reset_user_password');
        print('📝 Parameters: user_id=$userId, reset_token_id=$tokenId');
        
        final response = await _client.rpc('reset_user_password', params: {
          'user_id': userId,
          'new_password': newPassword,
          'reset_token_id': tokenId,
        });

        print('✅ RPC Response: $response');
        print('✅ Password reset successful');

        // 5. Mark token as used (if not already marked by function)
        await _client
            .from('password_reset_tokens')
            .update({
              'used': true,
            })
            .eq('id', tokenId);

        print('✅ Token marked as used');

      } catch (rpcError) {
        print('❌ RPC Error Details: ${rpcError.toString()}');
        print('❌ Error Type: ${rpcError.runtimeType}');
        
        final errorMessage = rpcError.toString().toLowerCase();
        
        if (errorMessage.contains('user not found')) {
          throw Exception('User account not found in Auth system. Please contact support or check if the user was deleted.');
        }

        if (errorMessage.contains('reset_user_password') && 
            (errorMessage.contains('not found') || errorMessage.contains('does not exist'))) {
          throw Exception(
            'Password reset database function not found. '
            'Please run the SQL setup script in Supabase.'
          );
        }
        
        // Re-throw with more context
        throw Exception('Password reset failed: ${rpcError.toString()}');
      }

    } catch (e) {
      print('❌ Password reset failed: $e');
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
  /// This also enforces rate limiting
  Future<Map<String, String>> resendResetCode(String email) async {
    print('🔁 Resend OTP requested for: $email');
    
    // Rate limiting is handled inside requestPasswordReset
    return await requestPasswordReset(email);
  }
  
  /// Get rate limit status for an email
  Future<Map<String, dynamic>> getRateLimitStatus(String email) async {
    return await RateLimitService.getStatus(email);
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

  /// Send password reset email with code using SMTP
  /// 
  /// Setup required:
  /// 1. Update SMTP credentials in smtp_service.dart
  /// 2. For Gmail: Enable 2FA and create an App Password
  /// 3. For other providers: Use their SMTP settings
  Future<void> _sendResetEmail(String email, String code, String name) async {
    try {
      print('📧 Sending reset email via SMTP to: $email');
      
      final success = await _smtpService.sendPasswordResetEmail(
        recipientEmail: email,
        recipientName: name,
        resetCode: code,
      );
      
      if (success) {
        print('✅ Password reset email sent successfully via SMTP');
      } else {
        print('⚠️ Email may not have been sent via SMTP');
        // Don't throw - allow the reset flow to continue
        // The code is still valid in the database
      }
    } catch (e) {
      print('⚠️ SMTP email sending failed: $e');
      // Log error but don't throw - the reset token is still valid
      // User might be able to get the code another way (support, logs, etc.)
    }
  }
}
