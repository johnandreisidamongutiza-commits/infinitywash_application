import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Stores the active session securely for automatic sign-in on this device.
/// Passwords are deliberately not persisted by the app.
Future<void> offerSaveAccount(BuildContext _, AuthService authService) async {
  await authService.rememberCurrentSession();
}
