import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static final SecureStorageService instance = SecureStorageService._init();
  
  // Initialize Flutter Secure Storage with Android-specific options
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  SecureStorageService._init();

  /// Expose the underlying FlutterSecureStorage instance for direct operations (e.g. debugging/testing)
  FlutterSecureStorage get storage => _storage;

  // Keys for storage
  static const String _accessTokenPrefix = 'access_token_';
  static const String _refreshTokenPrefix = 'refresh_token_';
  static const String _tokenExpiryPrefix = 'token_expiry_';
  static const String _lastAutoLoginKey = 'last_auto_login';
  static const String _permissionRationalePrefix = 'permission_rationale_';

  /// Whether this account has already accepted a permission explanation.
  Future<bool> hasAcceptedPermissionRationale({
    required String userId,
    required String permission,
  }) async {
    try {
      return await _storage.read(
            key: '$_permissionRationalePrefix${permission}_$userId',
          ) ==
          'true';
    } catch (_) {
      return false;
    }
  }

  /// Stores acceptance separately for each account on this device.
  Future<void> savePermissionRationaleAcceptance({
    required String userId,
    required String permission,
  }) async {
    await _storage.write(
      key: '$_permissionRationalePrefix${permission}_$userId',
      value: 'true',
    );
  }

  // Save authentication tokens for a user
  Future<void> saveAuthTokens({
    required String userId,
    required String accessToken,
    String? refreshToken,
    DateTime? expiresAt,
  }) async {
    try {
      // Save access token
      await _storage.write(
        key: '$_accessTokenPrefix$userId',
        value: accessToken,
      );

      // Save refresh token if provided
      if (refreshToken != null) {
        await _storage.write(
          key: '$_refreshTokenPrefix$userId',
          value: refreshToken,
        );
      }

      // Save expiry date if provided
      if (expiresAt != null) {
        await _storage.write(
          key: '$_tokenExpiryPrefix$userId',
          value: expiresAt.toIso8601String(),
        );
      }
    } catch (e) {
      throw Exception('Failed to save authentication tokens: $e');
    }
  }

  // Get access token for a user
  Future<String?> getAccessToken(String userId) async {
    try {
      return await _storage.read(key: '$_accessTokenPrefix$userId');
    } catch (e) {
      throw Exception('Failed to retrieve access token: $e');
    }
  }

  // Get refresh token for a user
  Future<String?> getRefreshToken(String userId) async {
    try {
      return await _storage.read(key: '$_refreshTokenPrefix$userId');
    } catch (e) {
      throw Exception('Failed to retrieve refresh token: $e');
    }
  }

  // Get token expiry date for a user
  Future<DateTime?> getTokenExpiry(String userId) async {
    try {
      final expiryString = await _storage.read(key: '$_tokenExpiryPrefix$userId');
      if (expiryString == null) return null;
      return DateTime.parse(expiryString);
    } catch (e) {
      throw Exception('Failed to retrieve token expiry: $e');
    }
  }

  // Check if token is valid (not expired)
  Future<bool> isTokenValid(String userId) async {
    try {
      final token = await getAccessToken(userId);
      if (token == null) return false;

      final expiry = await getTokenExpiry(userId);
      if (expiry == null) return true; // No expiry set, assume valid

      return DateTime.now().isBefore(expiry);
    } catch (e) {
      return false;
    }
  }

  // Delete tokens for a specific user
  Future<void> deleteUserTokens(String userId) async {
    try {
      await _storage.delete(key: '$_accessTokenPrefix$userId');
      await _storage.delete(key: '$_refreshTokenPrefix$userId');
      await _storage.delete(key: '$_tokenExpiryPrefix$userId');
    } catch (e) {
      throw Exception('Failed to delete user tokens: $e');
    }
  }

  // Clear all stored tokens
  Future<void> clearAllTokens() async {
    try {
      // Get all keys
      final allKeys = await _storage.readAll();
      
      // Delete all token-related keys
      for (final key in allKeys.keys) {
        if (key.startsWith(_accessTokenPrefix) ||
            key.startsWith(_refreshTokenPrefix) ||
            key.startsWith(_tokenExpiryPrefix)) {
          await _storage.delete(key: key);
        }
      }
    } catch (e) {
      throw Exception('Failed to clear all tokens: $e');
    }
  }

  // Get all user IDs that have stored tokens
  Future<List<String>> getAllUserIdsWithTokens() async {
    try {
      final allKeys = await _storage.readAll();
      final userIds = <String>{};

      for (final key in allKeys.keys) {
        if (key.startsWith(_accessTokenPrefix)) {
          final userId = key.replaceFirst(_accessTokenPrefix, '');
          userIds.add(userId);
        }
      }

      return userIds.toList();
    } catch (e) {
      throw Exception('Failed to retrieve user IDs: $e');
    }
  }

  // Save last auto-login user ID
  Future<void> saveLastAutoLoginUser(String userId) async {
    try {
      await _storage.write(key: _lastAutoLoginKey, value: userId);
    } catch (e) {
      throw Exception('Failed to save last auto-login user: $e');
    }
  }

  // Get last auto-login user ID
  Future<String?> getLastAutoLoginUser() async {
    try {
      return await _storage.read(key: _lastAutoLoginKey);
    } catch (e) {
      throw Exception('Failed to retrieve last auto-login user: $e');
    }
  }

  // Clear last auto-login user
  Future<void> clearLastAutoLoginUser() async {
    try {
      await _storage.delete(key: _lastAutoLoginKey);
    } catch (e) {
      throw Exception('Failed to clear last auto-login user: $e');
    }
  }

  // Check if user has valid saved session
  Future<bool> hasValidSession(String userId) async {
    try {
      final token = await getAccessToken(userId);
      if (token == null) return false;
      
      return await isTokenValid(userId);
    } catch (e) {
      return false;
    }
  }

  // Get all stored data (for debugging - use carefully)
  Future<Map<String, String>> getAllStoredData() async {
    try {
      return await _storage.readAll();
    } catch (e) {
      throw Exception('Failed to read all data: $e');
    }
  }

  // Delete all data from secure storage (nuclear option)
  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      throw Exception('Failed to delete all data: $e');
    }
  }
}
