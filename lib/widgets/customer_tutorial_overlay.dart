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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateTargetRect();
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    _updateTargetRect();
  }

  @override
  void didUpdateWidget(covariant CustomerTutorialOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.steps != widget.steps) {
      _updateTargetRect();
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _updateTargetRect() async {
    if (!mounted || widget.steps.isEmpty) return;
    final step = widget.steps[_currentIndex];

    if (widget.onBeforeStep != null) {
      await widget.onBeforeStep!(step.targetKey);
      // Allow scroll animation to finish and layout to settle
      await Future.delayed(const Duration(milliseconds: 280));
    } else {
      await Future.delayed(const Duration(milliseconds: 50));
    }
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
      if (mounted) {
        setState(() {
          _targetRect = Rect.fromLTRB(
            rawRect.left - step.padding.left,
            rawRect.top - step.padding.top,
            rawRect.right + step.padding.right,
            rawRect.bottom + step.padding.bottom,
          );
        });
      }
    } else if (mounted) {
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

  void _prevStep() async {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      await _updateTargetRect();
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
      child: Material(
        color: Colors.transparent,
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

              // 2. Gesture detector covering background: tapping advances to next step
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _nextStep,
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity != null) {
                      if (details.primaryVelocity! < -150) {
                        _nextStep();
                      } else if (details.primaryVelocity! > 150) {
                        _prevStep();
                      }
                    }
                  },
                  child: const SizedBox.expand(),
                ),
              ),

              // 2b. Tap listener directly on the highlighted target rect to advance
              if (_targetRect != null)
                Positioned(
                  left: _targetRect!.left,
                  top: _targetRect!.top,
                  width: _targetRect!.width,
                  height: _targetRect!.height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _nextStep,
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
    const double horizontalMargin = 16.0;
    final double maxBubbleWidth = screenSize.width - (horizontalMargin * 2);

    // Determine vertical placement: above or below target
    bool isBelowTarget = true;
    double? top;
    double? bottom;
    double arrowX = screenSize.width / 2;

    final safeTop = mediaQuery.padding.top + 16;
    final safeBottom = mediaQuery.padding.bottom + 16;

    if (_targetRect != null) {
      arrowX = _targetRect!.center.dx.clamp(
        horizontalMargin + 32,
        screenSize.width - horizontalMargin - 32,
      );

      final spaceBelow = screenSize.height - _targetRect!.bottom - safeBottom;
      final spaceAbove = _targetRect!.top - safeTop;

      // If more space above or target is low on screen, place bubble above it
      if (spaceAbove >= spaceBelow || _targetRect!.center.dy > screenSize.height * 0.48) {
        isBelowTarget = false;
        final rawBottom = (screenSize.height - _targetRect!.top) + 12;
        final maxAllowedBottom = math.max(safeBottom, screenSize.height - safeTop - 240);
        bottom = rawBottom.clamp(safeBottom, maxAllowedBottom);
      } else {
        isBelowTarget = true;
        final rawTop = _targetRect!.bottom + 12;
        final maxAllowedTop = math.max(safeTop, screenSize.height - safeBottom - 240);
        top = rawTop.clamp(safeTop, maxAllowedTop);
      }
    } else {
      // Fallback centered
      top = screenSize.height * 0.35;
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
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: Container(
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
                // Top row: Step badge "STEP 1 OF 5" and close button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'STEP ${_currentIndex + 1} OF ${widget.steps.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: _skip,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Step title
                if (step.title.isNotEmpty) ...[
                  Text(
                    step.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16.5,
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

                // Controls Row: Left action, Center dots, Right Next/Finish
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left action: Back button (if > 0) or Skip button
                    _currentIndex > 0
                        ? TextButton.icon(
                            onPressed: _prevStep,
                            icon: const Icon(Icons.arrow_back_rounded, size: 14),
                            label: const Text(
                              'Back',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white.withValues(alpha: 0.8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                        : TextButton(
                            onPressed: _skip,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white.withValues(alpha: 0.65),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text(
                              'Skip',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),

                    // Center: Indicator dots
                    Row(
                      children: List.generate(widget.steps.length, (index) {
                        final isActive = index == _currentIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: isActive ? 18 : 6,
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

                    // Right action: Next or Finish
                    ElevatedButton(
                      onPressed: _nextStep,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1E1F2E),
                        elevation: 0,
                        minimumSize: const Size(76, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isLast ? 'Finish' : 'Next',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E1F2E),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                            size: 15,
                            color: const Color(0xFF1E1F2E),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
