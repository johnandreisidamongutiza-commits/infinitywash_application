import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../widgets/top_notification.dart';

/// Centralized utility for opening the native phone dialer with a phone number pre-filled,
/// with automatic clipboard copy as a fallback and instant backup.
class PhoneHelper {
  PhoneHelper._();

  /// Opens the native phone app/dialer with [phone] pre-filled in the keypad.
  /// Also copies [phone] to clipboard so the user has it ready in any external app.
  static Future<void> openDialer(
    BuildContext context, {
    required String? phone,
    String? contactName,
  }) async {
    if (phone == null || phone.trim().isEmpty) {
      final name = (contactName != null && contactName.trim().isNotEmpty) ? contactName : 'Contact';
      showTopNotification(
        context,
        message: '$name does not have a phone number on file.',
        icon: Icons.phone_disabled,
        backgroundColor: Colors.orange.shade700,
      );
      return;
    }

    final trimmedPhone = phone.trim();
    // Always copy to clipboard so it's ready in external calling apps as well
    await Clipboard.setData(ClipboardData(text: trimmedPhone));

    // Strip formatting characters except digits and optional leading +
    final cleanDigits = trimmedPhone.replaceAll(RegExp(r'[^\d+]'), '');
    final Uri telUri = Uri(scheme: 'tel', path: cleanDigits);

    try {
      if (await canLaunchUrl(telUri)) {
        await launchUrl(telUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {
      // Fall through to show clipboard notification
    }

    if (!context.mounted) return;
    showTopNotification(
      context,
      message: 'Phone number $trimmedPhone copied to clipboard.',
      icon: Icons.copy,
      backgroundColor: AppTheme.accentBlue,
    );
  }
}

