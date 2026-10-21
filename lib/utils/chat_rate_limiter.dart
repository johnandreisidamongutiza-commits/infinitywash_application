import 'dart:async';
import 'package:flutter/foundation.dart';

/// Reusable rate limiter to prevent spamming premade messages / quick replies.
/// Supports both general cooldown and same-message duplicate cooldowns.
class ChatRateLimiter {
  final Duration cooldownDuration;
  final Duration sameMessageCooldownDuration;

  DateTime? _lastSentTime;
  String? _lastSentText;
  Timer? _cooldownTimer;
  int _remainingCooldownSeconds = 0;
  VoidCallback? _onTick;

  ChatRateLimiter({
    this.cooldownDuration = const Duration(seconds: 5),
    this.sameMessageCooldownDuration = const Duration(seconds: 25),
  });

  void setTickListener(VoidCallback onTick) {
    _onTick = onTick;
  }

  bool get isInCooldown => _remainingCooldownSeconds > 0;
  int get remainingSeconds => _remainingCooldownSeconds;

  /// Validates whether a premade message can be sent.
  /// If blocked, calls [onBlocked] with a user-friendly error message.
  bool canSend(String text, {void Function(String reason)? onBlocked}) {
    final now = DateTime.now();

    // 1. Check general cooldown window
    if (_lastSentTime != null) {
      final elapsed = now.difference(_lastSentTime!);
      if (elapsed < cooldownDuration) {
        final waitSec =
            (cooldownDuration.inSeconds - elapsed.inSeconds).clamp(1, 60);
        onBlocked?.call(
            'Please wait $waitSec second${waitSec > 1 ? 's' : ''} before sending another quick reply.');
        return false;
      }
    }

    // 2. Check identical message spam window
    if (_lastSentText == text.trim() && _lastSentTime != null) {
      final elapsed = now.difference(_lastSentTime!);
      if (elapsed < sameMessageCooldownDuration) {
        final waitSec =
            (sameMessageCooldownDuration.inSeconds - elapsed.inSeconds)
                .clamp(1, 60);
        onBlocked?.call(
            'You already sent this message. Please wait ${waitSec}s to send it again.');
        return false;
      }
    }

    return true;
  }

  /// Records a successful send and initiates the countdown
  void recordSent(String text) {
    _lastSentTime = DateTime.now();
    _lastSentText = text.trim();
    _startCountdown(cooldownDuration.inSeconds);
  }

  void _startCountdown(int seconds) {
    _cooldownTimer?.cancel();
    _remainingCooldownSeconds = seconds;
    _onTick?.call();

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _remainingCooldownSeconds--;
      if (_remainingCooldownSeconds <= 0) {
        _remainingCooldownSeconds = 0;
        timer.cancel();
      }
      _onTick?.call();
    });
  }

  void dispose() {
    _cooldownTimer?.cancel();
    _onTick = null;
  }
}
