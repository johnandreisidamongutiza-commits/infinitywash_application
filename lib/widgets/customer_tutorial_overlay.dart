import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Represents a single step in the interactive onboarding tutorial.
class TutorialStep {
  final GlobalKey targetKey;
  final String title;
  final String description;
  final BorderRadius borderRadius;
  final EdgeInsets padding;

  const TutorialStep({
    required this.targetKey,
    required this.title,
    required this.description,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.padding = const EdgeInsets.all(6),
  });
}

/// An interactive spotlight walkthrough overlay designed to guide customers
/// through key app features (such as how to order laundry).
///
/// Features:
/// - Dimmed background overlay with a cutout spotlight around the target widget.
/// - Glowing/subtle border around the highlighted element.
/// - Dark floating tooltip bubble with a triangular arrow pointing to the target.
/// - Step progress dots (active elongated pill, inactive dots).
/// - Skip and Next buttons on each step, switching to "Finish" on the final step.
class CustomerTutorialOverlay extends StatefulWidget {
  final List<TutorialStep> steps;
  final VoidCallback onFinish;
  final VoidCallback onSkip;
  final Future<void> Function(GlobalKey key)? onBeforeStep;

  const CustomerTutorialOverlay({
    super.key,
    required this.steps,
    required this.onFinish,
    required this.onSkip,
    this.onBeforeStep,
  });

  @override
  State<CustomerTutorialOverlay> createState() => _CustomerTutorialOverlayState();
}

class _CustomerTutorialOverlayState extends State<CustomerTutorialOverlay>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  Rect? _targetRect;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    _fadeController.forward();
    _updateTargetRect();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _updateTargetRect() async {
    if (widget.steps.isEmpty) return;
    final step = widget.steps[_currentIndex];

    if (widget.onBeforeStep != null) {
      await widget.onBeforeStep!(step.targetKey);
    }

    // Wait a frame for any scroll or layout animations to stabilize
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final renderBox =
        step.targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize && renderBox.attached) {
      final position = renderBox.localToGlobal(Offset.zero);
      final rawRect = Rect.fromLTWH(
        position.dx,
        position.dy,
        renderBox.size.width,
        renderBox.size.height,
      );
      // Inflate with custom padding
      setState(() {
        _targetRect = Rect.fromLTRB(
          rawRect.left - step.padding.left,
          rawRect.top - step.padding.top,
          rawRect.right + step.padding.right,
          rawRect.bottom + step.padding.bottom,
        );
      });
    } else {
      setState(() {
        _targetRect = null;
      });
    }
  }

  void _nextStep() async {
    if (_currentIndex < widget.steps.length - 1) {
      setState(() {
        _currentIndex++;
      });
      await _updateTargetRect();
    } else {
      widget.onFinish();
    }
  }

  void _skip() {
    widget.onSkip();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) return const SizedBox.shrink();

    final step = widget.steps[_currentIndex];
    final isLast = _currentIndex == widget.steps.length - 1;
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _skip();
      },
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          children: [
            // 1. Dark scrim with cutout hole for target element
            CustomPaint(
              size: screenSize,
              painter: _SpotlightPainter(
                targetRect: _targetRect,
                borderRadius: step.borderRadius,
                overlayColor: Colors.black.withValues(alpha: 0.72),
                highlightBorderColor: Colors.white.withValues(alpha: 0.45),
              ),
            ),

            // 2. Absorb pointers on the background to prevent accidental clicks
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  // Keep focus on the tutorial buttons
                },
                child: const SizedBox.expand(),
              ),
            ),

            // 3. Tooltip Bubble with arrow
            _buildTooltipBubble(
              context: context,
              step: step,
              isLast: isLast,
              screenSize: screenSize,
              mediaQuery: mediaQuery,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTooltipBubble({
    required BuildContext context,
    required TutorialStep step,
    required bool isLast,
    required Size screenSize,
    required MediaQueryData mediaQuery,
  }) {
    const double horizontalMargin = 20.0;
    final double maxBubbleWidth = screenSize.width - (horizontalMargin * 2);

    // Determine vertical placement: above or below target
    bool isBelowTarget = true;
    double? top;
    double? bottom;
    double arrowX = screenSize.width / 2;

    if (_targetRect != null) {
      arrowX = _targetRect!.center.dx.clamp(
        horizontalMargin + 32,
        screenSize.width - horizontalMargin - 32,
      );

      // If target is in the bottom half of the screen, place bubble above it
      if (_targetRect!.center.dy > screenSize.height * 0.52) {
        isBelowTarget = false;
        bottom = (screenSize.height - _targetRect!.top) + 14;
        bottom = math.max(bottom, mediaQuery.padding.bottom + 16);
      } else {
        isBelowTarget = true;
        top = _targetRect!.bottom + 14;
        top = math.max(top, mediaQuery.padding.top + 16);
      }
    } else {
      // Fallback centered
      top = screenSize.height * 0.4;
    }

    return Positioned(
      left: horizontalMargin,
      right: horizontalMargin,
      top: top,
      bottom: bottom,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Arrow pointing UP if bubble is below target
          if (_targetRect != null && isBelowTarget)
            Align(
              alignment: Alignment(
                ((arrowX - horizontalMargin) / (maxBubbleWidth / 2)) - 1.0,
                0,
              ),
              child: CustomPaint(
                size: const Size(18, 10),
                painter: _TrianglePainter(
                  color: const Color(0xFF1E1F2E),
                  pointingUp: true,
                ),
              ),
            ),

          // Main Card Container
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1F2E),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Step title
                if (step.title.isNotEmpty) ...[
                  Text(
                    step.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Step descriptive text
                Text(
                  step.description,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 13.5,
                    height: 1.45,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 20),

                // Controls Row: Indicator dots on left, Skip & Next/Finish on right
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Step indicators (dash for current, dots for others)
                    Row(
                      children: List.generate(widget.steps.length, (index) {
                        final isActive = index == _currentIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.only(right: 6),
                          width: isActive ? 20 : 6,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),

                    // Buttons: Skip & Next / Finish
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Skip Button
                        TextButton(
                          onPressed: _skip,
                          style: TextButton.styleFrom(
                            foregroundColor:
                                Colors.white.withValues(alpha: 0.75),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text(
                            'Skip',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Next or Finish Button
                        isLast
                            ? ElevatedButton(
                                onPressed: _nextStep,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF1E1F2E),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Finish',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1E1F2E),
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(
                                      Icons.check_rounded,
                                      size: 16,
                                      color: Color(0xFF1E1F2E),
                                    ),
                                  ],
                                ),
                              )
                            : ElevatedButton(
                                onPressed: _nextStep,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF1E1F2E),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Next',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1E1F2E),
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 16,
                                      color: Color(0xFF1E1F2E),
                                    ),
                                  ],
                                ),
                              ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Arrow pointing DOWN if bubble is above target
          if (_targetRect != null && !isBelowTarget)
            Align(
              alignment: Alignment(
                ((arrowX - horizontalMargin) / (maxBubbleWidth / 2)) - 1.0,
                0,
              ),
              child: CustomPaint(
                size: const Size(18, 10),
                painter: _TrianglePainter(
                  color: const Color(0xFF1E1F2E),
                  pointingUp: false,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Custom painter that creates a semi-transparent dark mask with a rounded
/// cutout hole over the highlighted target widget.
class _SpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  final BorderRadius borderRadius;
  final Color overlayColor;
  final Color highlightBorderColor;

  _SpotlightPainter({
    required this.targetRect,
    required this.borderRadius,
    required this.overlayColor,
    required this.highlightBorderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final screenRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final overlayPaint = Paint()..color = overlayColor;

    if (targetRect == null) {
      canvas.drawRect(screenRect, overlayPaint);
      return;
    }

    final targetRRect = borderRadius.toRRect(targetRect!);

    // Draw dark mask with cutout using Even-Odd rule
    final path = Path()
      ..addRect(screenRect)
      ..addRRect(targetRRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, overlayPaint);

    // Draw glowing subtle highlight border around the target
    final borderPaint = Paint()
      ..color = highlightBorderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawRRect(targetRRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.overlayColor != overlayColor ||
        oldDelegate.highlightBorderColor != highlightBorderColor;
  }
}

/// Custom painter for the triangular pointer arrow pointing UP or DOWN.
class _TrianglePainter extends CustomPainter {
  final Color color;
  final bool pointingUp;

  _TrianglePainter({required this.color, required this.pointingUp});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    if (pointingUp) {
      path.moveTo(0, size.height);
      path.lineTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
      path.close();
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width / 2, size.height);
      path.lineTo(size.width, 0);
      path.close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.pointingUp != pointingUp;
  }
}
