import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Native Google account picker followed by a Supabase ID-token exchange.
class GoogleSignInService {
  GoogleSignInService._();

  static final GoogleSignIn _google = GoogleSignIn.instance;
  static Future<void>? _initialization;

  // Web OAuth client ID from android/app/google-services.json (client_type 3).
  // It must also be the Web client ID configured in Supabase Auth > Google.
  static const String _webClientId =
      '1048960336599-78af8f5j2qpmsfmol1d465k3t6if34kg.apps.googleusercontent.com';

  static Future<void> _initialize() {
    return _initialization ??= _google.initialize(
      serverClientId: _webClientId,
    );
  }

  /// Opens Google's native account flow and exchanges its ID token with Supabase.
  static Future<void> signIn() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'com.example.infinitywash://login-callback/',
      );
      return;
    }

    await _initialize();
    final account = await _google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError(
        'Google did not return an ID token. Check the Android and Web OAuth client setup.',
      );
    }

    await Supabase.instance.client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
  }

  static bool isCancelled(Object error) =>
      error is GoogleSignInException &&
      error.code == GoogleSignInExceptionCode.canceled;

  static String errorMessage(Object error) {
    if (error is GoogleSignInException) {
      switch (error.code) {
        case GoogleSignInExceptionCode.canceled:
          return 'Google sign-in was canceled.';
        case GoogleSignInExceptionCode.clientConfigurationError:
          return 'Google sign-in is not configured for this Android app. Check the package name and SHA-1 certificate in Google Cloud/Firebase.';
        case GoogleSignInExceptionCode.providerConfigurationError:
          return 'Google sign-in is unavailable. Check the Google Sign-In setup and try again.';
        default:
          return error.description ?? 'Google sign-in could not be completed. Please try again.';
      }
    }
    if (error is AuthException) {
      return 'Google verified your account, but Supabase could not sign you in. Confirm the same Web client ID is configured in Supabase Auth > Google.';
    }
    if (error is StateError) {
      return error.toString().replaceFirst('Bad state: ', '');
    }
    return 'Google sign-in could not be completed. Please check your connection and configuration, then try again.';
  }
}
