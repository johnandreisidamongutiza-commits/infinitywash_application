import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/app_error.dart';

/// A reusable error view for failed loads and failed actions.
///
/// Shows a friendly message (never a raw exception) with an optional Retry
/// button wired to the screen's reload logic. Works full-page, inline in a
/// list, or inside a dialog-sized container.
class ErrorStateWidget extends StatelessWidget {
  final Object? error;

  /// Optional pre-mapped, user-safe message. Takes precedence over [error].
  final String? message;

  final VoidCallback? onRetry;

  /// `true` when shown inside a small area (card/list tile) — tighter padding.
  final bool compact;

  const ErrorStateWidget({
    super.key,
    this.error,
    this.message,
    this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final String text = message ?? mapErrorToMessage(error ?? 'Something went wrong.');
    final AppError mapped = mapError(error ?? 'Something went wrong.');
    final bool isNetwork = mapped.isNetwork;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(compact ? 16 : 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isNetwork ? Icons.wifi_off : Icons.error_outline,
              size: compact ? 40 : 64,
              color: isNetwork ? AppTheme.textLight : AppTheme.errorRed,
            ),
            SizedBox(height: compact ? 8 : 16),
            Text(
              isNetwork ? 'Connection problem' : 'Something went wrong',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 15 : 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 12 : 14,
                color: AppTheme.textLight,
              ),
            ),
            if (onRetry != null) ...[
              SizedBox(height: compact ? 12 : 20),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small inline banner-style error for forms and dialog contents.
class InlineErrorBanner extends StatelessWidget {
  final Object? error;
  final String? message;

  const InlineErrorBanner({super.key, this.error, this.message});

  @override
  Widget build(BuildContext context) {
    final String text = message ?? mapErrorToMessage(error ?? 'Something went wrong.');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.errorRed.withValues(alpha: 0.08),
        border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.errorRed, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a friendly error snackbar from any context.
void showErrorSnackBar(BuildContext context, Object error, {String? fallbackMessage}) {
  final text = fallbackMessage ?? mapErrorToMessage(error);
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white))),
        ],
      ),
      backgroundColor: AppTheme.errorRed,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'OK',
        textColor: Colors.white,
        onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
      ),
    ),
  );
}

/// Shows a friendly success/info snackbar.
void showSuccessSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
        ],
      ),
      backgroundColor: Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ),
  );
}

/// Shows a friendly info snackbar (neutral color).
void showInfoSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ),
  );
}
