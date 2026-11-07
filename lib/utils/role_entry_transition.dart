import 'package:flutter/material.dart';

/// Consistent entrance motion for authenticated destinations.
class RoleEntryTransition {
  const RoleEntryTransition._();

  static PageRouteBuilder<void> route(Widget destination) {
    return PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) => destination,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final eased = CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOutCubic,
          reverseCurve: Curves.easeInOutCubic,
        );
        return FadeTransition(opacity: eased, child: child);
      },
    );
  }
}
