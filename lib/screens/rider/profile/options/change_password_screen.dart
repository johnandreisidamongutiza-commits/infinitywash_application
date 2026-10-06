import 'package:flutter/material.dart';

import '../../../../widgets/change_password_view.dart';

/// Rider-facing entry point for the shared Change Password screen.
class RiderChangePasswordScreen extends StatelessWidget {
  const RiderChangePasswordScreen({super.key});

  @override
  Widget build(BuildContext context) => const ChangePasswordView(
        safetyMessage: 'Choose a strong password to keep your deliveries and '
            'account details safe.',
      );
}
