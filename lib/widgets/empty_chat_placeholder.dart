import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A friendly placeholder displayed when a chat conversation has no messages yet.
///
/// Automatically disappears once messages are sent or received.
class EmptyChatPlaceholder extends StatelessWidget {
  final String recipientName;
  final String? recipientRole;
  final IconData icon;
  final String? customMessage;
  final String? tipText;

  const EmptyChatPlaceholder({
    super.key,
    required this.recipientName,
    this.recipientRole,
    this.icon = Icons.chat_bubble_outline,
    this.customMessage,
    this.tipText,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon badge with soft background
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.accentBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 34,
                color: AppTheme.accentBlue,
              ),
            ),
            const SizedBox(height: 18),

            // Main greeting / title
            Text(
              'Start the conversation',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 6),

            // Role / Recipient context
            if (recipientName.isNotEmpty) ...[
              Text(
                recipientRole != null && recipientRole!.isNotEmpty
                    ? '$recipientName • $recipientRole'
                    : recipientName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accentBlue,
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Contextual message
            Text(
              customMessage ??
                  'No messages here yet. Send a message to get started.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppTheme.textLight,
              ),
            ),
            const SizedBox(height: 16),

            // Tip container
            if (tipText != null && tipText!.isNotEmpty) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.softGray,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.borderGray.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lightbulb_outline,
                      size: 16,
                      color: AppTheme.accentBlue,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        tipText!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Security / privacy note
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(
                  Icons.lock_outline,
                  size: 13,
                  color: AppTheme.textLight,
                ),
                SizedBox(width: 6),
                Text(
                  'Messages are direct and private',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textLight,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

