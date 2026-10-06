import 'package:flutter/material.dart';

import '../../../../widgets/change_password_view.dart';

/// Customer-facing entry point for the shared Change Password screen.
class CustomerChangePasswordScreen extends StatelessWidget {
  const CustomerChangePasswordScreen({super.key});

  @override
  Widget build(BuildContext context) => const ChangePasswordView(
        safetyMessage: 'Choose a strong password to keep your laundry orders '
            'and account details safe.',
      );
}
