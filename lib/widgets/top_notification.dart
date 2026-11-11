import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

void showTopNotification(
  BuildContext context, {
  required String message,
  IconData icon = Icons.check_circle,
  Color backgroundColor = Colors.green,
  Duration duration = const Duration(seconds: 3),
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  late OverlayEntry overlayEntry;

  overlayEntry = OverlayEntry(
    builder: (context) => _TopNotificationBanner(
      message: message,
      icon: icon,
      backgroundColor: backgroundColor,
      onDismiss: () {
        if (overlayEntry.mounted) {
          overlayEntry.remove();
        }
      },
    ),
  );

  overlay.insert(overlayEntry);

  Future.delayed(duration, () {
    if (overlayEntry.mounted) {
      overlayEntry.remove();
    }
  });
}

class _TopNotificationBanner extends StatefulWidget {
  final String message;
  final IconData icon;
  final Color backgroundColor;
  final VoidCallback onDismiss;

  const _TopNotificationBanner({
    required this.message,
    required this.icon,
    required this.backgroundColor,
    required this.onDismiss,
  });

  @override
  State<_TopNotificationBanner> createState() => _TopNotificationBannerState();
}

class _TopNotificationBannerState extends State<_TopNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      reverseDuration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 10,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _offsetAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: widget.backgroundColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, color: Colors.white, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _dismiss,
                      child: const Icon(
                        Icons.close,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rich banner specifically designed for incoming service requests with staff action.
void showNewRequestNotification(
  BuildContext context, {
  required String orderNumber,
  String? customerName,
  required VoidCallback onReview,
  Duration duration = const Duration(seconds: 7),
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  late OverlayEntry overlayEntry;

  overlayEntry = OverlayEntry(
    builder: (context) => _NewRequestTopBanner(
      orderNumber: orderNumber,
      customerName: customerName,
      onReview: () {
        if (overlayEntry.mounted) {
          overlayEntry.remove();
        }
        onReview();
      },
      onDismiss: () {
        if (overlayEntry.mounted) {
          overlayEntry.remove();
        }
      },
    ),
  );

  overlay.insert(overlayEntry);

  Future.delayed(duration, () {
    if (overlayEntry.mounted) {
      overlayEntry.remove();
    }
  });
}

class _NewRequestTopBanner extends StatefulWidget {
  final String orderNumber;
  final String? customerName;
  final VoidCallback onReview;
  final VoidCallback onDismiss;

  const _NewRequestTopBanner({
    required this.orderNumber,
    this.customerName,
    required this.onReview,
    required this.onDismiss,
  });

  @override
  State<_NewRequestTopBanner> createState() => _NewRequestTopBannerState();
}

class _NewRequestTopBannerState extends State<_NewRequestTopBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      reverseDuration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismiss();
  }

  Future<void> _handleReview() async {
    if (!mounted) return;
    await _controller.reverse();
    widget.onReview();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 10,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _offsetAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: GestureDetector(
              onTap: _handleReview,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.accentBlue.withValues(alpha: 0.45),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.accentBlue.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.accentBlue.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.assignment_late_rounded,
                        color: Color(0xFF38BDF8),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF38BDF8),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'NEW REQUEST',
                                style: GoogleFonts.lexend(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFFBAE6FD),
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.orderNumber.startsWith('Order')
                                ? widget.orderNumber
                                : 'Order #${widget.orderNumber}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.lexend(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          if (widget.customerName != null &&
                              widget.customerName!.trim().isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              widget.customerName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.lexend(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _handleReview,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Review',
                        style: GoogleFonts.lexend(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white60, size: 18),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: _dismiss,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
