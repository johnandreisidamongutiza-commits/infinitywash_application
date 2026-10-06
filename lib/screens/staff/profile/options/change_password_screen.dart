import 'package:flutter/material.dart';

import '../../../../widgets/change_password_view.dart';

/// Staff-facing entry point for the shared Change Password screen.
class ChangePasswordScreen extends StatelessWidget {
  const ChangePasswordScreen({super.key});

  @override
  Widget build(BuildContext context) => const ChangePasswordView(
        safetyMessage: 'Choose a strong password to keep the customer orders, '
            'payments and records you handle safe.',
      );
}
