import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Offers a saved, secure sign-in session after a successful sign-in.
/// Passwords are deliberately not persisted by the app.
Future<void> offerSaveAccount(BuildContext context, AuthService authService) async {
  final user = authService.getCurrentUser();
  if (user == null) return;

  // The user already opted in on this device. Refresh the saved tokens without
  // prompting again so account selection keeps working after token rotation.
  if (await authService.isAccountSaved(user.id)) {
    await authService.rememberCurrentSession();
    return;
  }
  if (!context.mounted) return;

  final save = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Save this account?'),
      content: Text(
        'Save ${user.email ?? 'this account'} on this device for quick sign-in next time? '
        'Your sign-in session is stored securely. Your password is not saved.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Not now'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Save account'),
        ),
      ],
    ),
  );

  if (save == true && context.mounted) {
    await authService.rememberCurrentSession();
  }
}
