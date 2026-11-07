import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A standardized header widget used across Customer, Rider, and Staff home screens.
/// 
/// Layout structure:
/// [Avatar (Left)] ── [Greeting & Subtitle (Middle)] ── [Notification Bell (Right)]
class HomeHeader extends StatelessWidget {
  /// Primary headline text (e.g., 'Hello, Customer!', 'Hi, Staff!', 'Hi, Rider!').
  final String title;

  /// Optional subtitle string (e.g., 'Your laundry is our priority. 🫧').
  final String? subtitle;

  /// Optional custom widget for subtitle (overrides [subtitle] if provided).
  final Widget? subtitleWidget;

  /// Unread notifications count. When > 0, an alert badge is displayed.
  final int unreadCount;

  /// Callback triggered when the notification bell is tapped.
  final VoidCallback onNotificationTap;

  /// Optional callback triggered when the avatar is tapped.
  final VoidCallback? onAvatarTap;

  /// Optional network avatar URL.
  final String? avatarUrl;

  /// Optional local avatar file path.
  final String? localAvatarPath;

  /// Asset path used as default or fallback avatar image.
  final String avatarAsset;

  /// Diameter of the circular avatar.
  final double avatarSize;

  /// Optional custom title style.
  final TextStyle? titleStyle;

  /// Optional custom subtitle style.
  final TextStyle? subtitleStyle;

  const HomeHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    required this.unreadCount,
    required this.onNotificationTap,
    this.onAvatarTap,
    this.avatarUrl,
    this.localAvatarPath,
    this.avatarAsset = 'assets/images/logo.png',
    this.avatarSize = 48.0,
    this.titleStyle,
    this.subtitleStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── 1. Avatar (Left) ──
        _buildAvatar(context),

        const SizedBox(width: 14),

        // ── 2. Greeting & Subtitle (Middle) ──
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: titleStyle ??
                    AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ) ??
                    const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              if (subtitleWidget != null)
                subtitleWidget!
              else if (subtitle != null)
                Text(
                  subtitle!,
                  style: subtitleStyle ??
                      AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        color: AppTheme.textLight,
                      ) ??
                      const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textLight,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),

        const SizedBox(width: 12),

        // ── 3. Notification Button (Right) ──
        _buildNotificationButton(context),
      ],
    );
  }

  Widget _buildAvatar(BuildContext context) {
    Widget imageWidget;
    final hasLocal = localAvatarPath != null &&
        localAvatarPath!.trim().isNotEmpty &&
        File(localAvatarPath!).existsSync();
    final hasRemote = avatarUrl != null && avatarUrl!.trim().isNotEmpty;

    if (hasLocal) {
      imageWidget = Image.file(
        File(localAvatarPath!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Image.asset(
          avatarAsset,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.person, color: AppTheme.textDark),
        ),
      );
    } else if (hasRemote) {
      imageWidget = CachedNetworkImage(
        imageUrl: avatarUrl!,
        fit: BoxFit.cover,
        placeholder: (context, url) => const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (context, url, error) => Image.asset(
          avatarAsset,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.person, color: AppTheme.textDark),
        ),
      );
    } else {
      imageWidget = Image.asset(
        avatarAsset,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.person, color: AppTheme.textDark),
      );
    }

    Widget avatarWidget = Container(
      width: avatarSize,
      height: avatarSize,
      decoration: BoxDecoration(
        color: AppTheme.softGray,
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.borderGray.withValues(alpha: 0.6),
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.all(2),
      child: ClipOval(child: imageWidget),
    );

    if (onAvatarTap != null) {
      return GestureDetector(
        onTap: onAvatarTap,
        child: avatarWidget,
      );
    }

    return avatarWidget;
  }

  Widget _buildNotificationButton(BuildContext context) {
    return InkWell(
      onTap: onNotificationTap,
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.softGray,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.borderGray.withValues(alpha: 0.6),
                width: 1.0,
              ),
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              color: unreadCount > 0 ? AppTheme.accentBlue : AppTheme.textDark,
              size: 24,
            ),
          ),
          if (unreadCount > 0)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
