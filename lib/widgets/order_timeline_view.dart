import 'package:flutter/material.dart';
import '../models/order.dart';
import '../theme/app_theme.dart';

enum TimelineStepState {
  completed,
  active,
  upcoming,
}

class TimelineStepData {
  final String title;
  final String subtitle;
  final IconData icon;
  final TimelineStepState state;
  final DateTime? timestamp;

  const TimelineStepData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.state,
    this.timestamp,
  });
}

/// Unified, responsive vertical order timeline widget for Customer, Staff, and Rider roles.
///
/// Automatically caters to the 4 system order flows:
/// 1. Walk-in + Shop Pickup
/// 2. Walk-in + Home Delivery
/// 3. Online Request + Home Delivery (Rider Pickup + Delivery)
/// 4. Online Request + Shop Pickup (Rider Pickup + Shop Pickup)
class OrderTimelineView extends StatelessWidget {
  final LaundryOrder order;
  final bool showHeader;

  const OrderTimelineView({
    super.key,
    required this.order,
    this.showHeader = true,
  });

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes <= 1) return 'Just now';
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    }

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year}';
  }

  String _getOrderTypeLabel() {
    final isWalkIn = order.channel == OrderChannel.walkIn;
    final isDelivery = order.returnMethod == ReturnMethod.delivery;

    if (isWalkIn) {
      return isDelivery ? 'Walk-in • Delivery' : 'Walk-in • Shop Pickup';
    } else {
      return isDelivery ? 'Online • Delivery' : 'Online • Shop Pickup';
    }
  }

  List<TimelineStepData> _calculateSteps() {
    final isWalkIn = order.channel == OrderChannel.walkIn;
    final isDelivery = order.returnMethod == ReturnMethod.delivery;
    final status = order.status;
    final needsCheckIn = order.needsCheckIn;
    final isCompleted = status == OrderStatus.completed;

    if (isWalkIn) {
      if (!isDelivery) {
        // Flow 1: Walk-In + Shop Pickup (4 Steps)
        return [
          TimelineStepData(
            title: 'Order Placed',
            subtitle: 'Logged and weighed at the counter',
            icon: Icons.storefront_outlined,
            state: TimelineStepState.completed,
            timestamp: order.createdAt,
          ),
          TimelineStepData(
            title: 'Processing',
            subtitle: 'Washing, drying & folding laundry',
            icon: Icons.local_laundry_service_outlined,
            state: (status == OrderStatus.ready || isCompleted)
                ? TimelineStepState.completed
                : (status == OrderStatus.processing
                    ? TimelineStepState.active
                    : TimelineStepState.upcoming),
            timestamp: order.processingAt,
          ),
          TimelineStepData(
            title: 'Ready for Pickup',
            subtitle: 'Clean and packed, ready for claim at the shop',
            icon: Icons.shopping_bag_outlined,
            state: isCompleted
                ? TimelineStepState.completed
                : (status == OrderStatus.ready
                    ? TimelineStepState.active
                    : TimelineStepState.upcoming),
          ),
          TimelineStepData(
            title: 'Completed',
            subtitle: 'Claimed by customer',
            icon: Icons.check_circle_outline,
            state: isCompleted
                ? TimelineStepState.completed
                : TimelineStepState.upcoming,
          ),
        ];
      } else {
        // Flow 2: Walk-In + Home Delivery (5 Steps)
        return [
          TimelineStepData(
            title: 'Order Placed',
            subtitle: 'Logged and weighed at the counter',
            icon: Icons.storefront_outlined,
            state: TimelineStepState.completed,
            timestamp: order.createdAt,
          ),
          TimelineStepData(
            title: 'Processing',
            subtitle: 'Washing, drying & folding laundry',
            icon: Icons.local_laundry_service_outlined,
            state: (status == OrderStatus.ready ||
                    status == OrderStatus.out_for_delivery ||
                    isCompleted)
                ? TimelineStepState.completed
                : (status == OrderStatus.processing
                    ? TimelineStepState.active
                    : TimelineStepState.upcoming),
            timestamp: order.processingAt,
          ),
          TimelineStepData(
            title: 'Ready for Delivery',
            subtitle: 'Packed and waiting for rider dispatch',
            icon: Icons.inventory_2_outlined,
            state: (status == OrderStatus.out_for_delivery || isCompleted)
                ? TimelineStepState.completed
                : (status == OrderStatus.ready
                    ? TimelineStepState.active
                    : TimelineStepState.upcoming),
          ),
          TimelineStepData(
            title: 'Out for Delivery',
            subtitle: 'Rider is on the way to delivery address',
            icon: Icons.local_shipping_outlined,
            state: isCompleted
                ? TimelineStepState.completed
                : (status == OrderStatus.out_for_delivery
                    ? TimelineStepState.active
                    : TimelineStepState.upcoming),
          ),
          TimelineStepData(
            title: 'Completed',
            subtitle: 'Delivered to customer',
            icon: Icons.check_circle_outline,
            state: isCompleted
                ? TimelineStepState.completed
                : TimelineStepState.upcoming,
          ),
        ];
      }
    } else {
      // Online Orders (Always starts with rider pickup)
      final requestAccepted = status != OrderStatus.pending_approval &&
          status != OrderStatus.rejected &&
          status != OrderStatus.cancelled;

      final pickupDone =
          requestAccepted && status != OrderStatus.pending_pickup;
      final checkInDone = pickupDone && !needsCheckIn;
      final washingDone = checkInDone &&
          (status == OrderStatus.ready ||
              status == OrderStatus.out_for_delivery ||
              isCompleted);

      if (isDelivery) {
        // Flow 3: Online Request + Home Delivery (7 Steps)
        return [
          TimelineStepData(
            title: 'Request Submitted',
            subtitle: status == OrderStatus.pending_approval
                ? 'Awaiting branch review and acceptance'
                : 'Request accepted by branch',
            icon: Icons.phone_android_outlined,
            state: requestAccepted
                ? TimelineStepState.completed
                : (status == OrderStatus.pending_approval
                    ? TimelineStepState.active
                    : TimelineStepState.upcoming),
            timestamp: order.createdAt,
          ),
          TimelineStepData(
            title: 'Waiting for Rider',
            subtitle: 'Rider assigned for laundry collection',
            icon: Icons.two_wheeler_outlined,
            state: pickupDone
                ? TimelineStepState.completed
                : (status == OrderStatus.pending_pickup
                    ? TimelineStepState.active
                    : TimelineStepState.upcoming),
          ),
          TimelineStepData(
            title: 'Store Check-in',
            subtitle: needsCheckIn && status == OrderStatus.processing
                ? 'Laundry arrived at branch; awaiting weighing & tagging'
                : 'Weighed and tagged at branch',
            icon: Icons.scale_outlined,
            state: checkInDone
                ? TimelineStepState.completed
                : ((needsCheckIn && status == OrderStatus.processing)
                    ? TimelineStepState.active
                    : TimelineStepState.upcoming),
          ),
          TimelineStepData(
            title: 'Processing',
            subtitle: 'Washing, drying & folding laundry',
            icon: Icons.local_laundry_service_outlined,
            state: washingDone
                ? TimelineStepState.completed
                : ((!needsCheckIn && status == OrderStatus.processing)
                    ? TimelineStepState.active
                    : TimelineStepState.upcoming),
            timestamp: order.processingAt,
          ),
          TimelineStepData(
            title: 'Ready for Delivery',
            subtitle: 'Packed and waiting for rider dispatch',
            icon: Icons.inventory_2_outlined,
            state: (status == OrderStatus.out_for_delivery || isCompleted)
                ? TimelineStepState.completed
                : (status == OrderStatus.ready
                    ? TimelineStepState.active
                    : TimelineStepState.upcoming),
          ),
          TimelineStepData(
            title: 'Out for Delivery',
            subtitle: 'Rider is on the way to delivery address',
            icon: Icons.local_shipping_outlined,
            state: isCompleted
                ? TimelineStepState.completed
                : (status == OrderStatus.out_for_delivery
                    ? TimelineStepState.active
                    : TimelineStepState.upcoming),
          ),
          TimelineStepData(
            title: 'Completed',
            subtitle: 'Delivered to customer',
            icon: Icons.check_circle_outline,
            state: isCompleted
                ? TimelineStepState.completed
                : TimelineStepState.upcoming,
          ),
        ];
      } else {
        // Flow 4: Online Request + Shop Pickup (6 Steps)
        return [
          TimelineStepData(
            title: 'Request Submitted',
            subtitle: status == OrderStatus.pending_approval
                ? 'Awaiting branch review and acceptance'
                : 'Request accepted by branch',
            icon: Icons.phone_android_outlined,
            state: requestAccepted
                ? TimelineStepState.completed
                : (status == OrderStatus.pending_approval
                    ? TimelineStepState.active
                    : TimelineStepState.upcoming),
            timestamp: order.createdAt,
          ),
          TimelineStepData(
            title: 'Waiting for Rider',
            subtitle: 'Rider assigned for laundry collection',
            icon: Icons.two_wheeler_outlined,
            state: pickupDone
                ? TimelineStepState.completed
                : (status == OrderStatus.pending_pickup
                    ? TimelineStepState.active
                    : TimelineStepState.upcoming),
          ),
          TimelineStepData(
            title: 'Store Check-in',
            subtitle: needsCheckIn && status == OrderStatus.processing
                ? 'Laundry arrived at branch; awaiting weighing & tagging'
                : 'Weighed and tagged at branch',
            icon: Icons.scale_outlined,
            state: checkInDone
                ? TimelineStepState.completed
                : ((needsCheckIn && status == OrderStatus.processing)
                    ? TimelineStepState.active
                    : TimelineStepState.upcoming),
          ),
          TimelineStepData(
            title: 'Processing',
            subtitle: 'Washing, drying & folding laundry',
            icon: Icons.local_laundry_service_outlined,
            state: washingDone
                ? TimelineStepState.completed
                : ((!needsCheckIn && status == OrderStatus.processing)
                    ? TimelineStepState.active
                    : TimelineStepState.upcoming),
            timestamp: order.processingAt,
          ),
          TimelineStepData(
            title: 'Ready for Pickup',
            subtitle: 'Clean and packed, ready for claim at the shop',
            icon: Icons.shopping_bag_outlined,
            state: isCompleted
                ? TimelineStepState.completed
                : (status == OrderStatus.ready
                    ? TimelineStepState.active
                    : TimelineStepState.upcoming),
          ),
          TimelineStepData(
            title: 'Completed',
            subtitle: 'Claimed by customer',
            icon: Icons.check_circle_outline,
            state: isCompleted
                ? TimelineStepState.completed
                : TimelineStepState.upcoming,
          ),
        ];
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _calculateSteps();
    final isCancelled = order.status == OrderStatus.cancelled;
    final isRejected = order.status == OrderStatus.rejected;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Order Timeline',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getOrderTypeLabel(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accentBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
          ],

          // Cancelled / Rejected Alert Banner
          if (isCancelled) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.errorRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.errorRed.withValues(alpha: 0.25),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cancel, color: AppTheme.errorRed, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This order has been cancelled.',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.errorRed,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isRejected) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: AppTheme.errorRed, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Request Rejected',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.errorRed,
                          ),
                        ),
                        if (order.rejectionReason != null &&
                            order.rejectionReason!.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            order.rejectionReason!,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.red.shade900,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Step items list
          ...List.generate(steps.length, (index) {
            final step = steps[index];
            final isLast = index == steps.length - 1;
            final nextStep = isLast ? null : steps[index + 1];

            return _buildTimelineRow(
              step: step,
              isLast: isLast,
              isNextActiveOrDone: nextStep != null &&
                  (nextStep.state == TimelineStepState.completed ||
                      nextStep.state == TimelineStepState.active),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTimelineRow({
    required TimelineStepData step,
    required bool isLast,
    required bool isNextActiveOrDone,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Node and connector line
          Column(
            children: [
              _buildNodeIcon(step),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2.5,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: isNextActiveOrDone
                        ? AppTheme.accentBlue
                        : const Color(0xFFE2E8F0),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),

          // Right: Content (Title, Subtitle, Time, Badges)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          step.title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: step.state == TimelineStepState.active
                                ? FontWeight.bold
                                : (step.state == TimelineStepState.completed
                                    ? FontWeight.w600
                                    : FontWeight.normal),
                            color: step.state == TimelineStepState.active
                                ? AppTheme.accentBlue
                                : (step.state == TimelineStepState.completed
                                    ? AppTheme.textDark
                                    : const Color(0xFF94A3B8)),
                          ),
                        ),
                      ),
                      if (step.state == TimelineStepState.active)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accentBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'CURRENT',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accentBlue,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    step.subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: step.state == TimelineStepState.upcoming
                          ? const Color(0xFF94A3B8)
                          : AppTheme.textLight,
                    ),
                  ),
                  if (step.timestamp != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatDateTime(step.timestamp!),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: step.state == TimelineStepState.active
                            ? AppTheme.accentBlue
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeIcon(TimelineStepData step) {
    switch (step.state) {
      case TimelineStepState.completed:
        return Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: AppTheme.accentBlue,
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(Icons.check, size: 16, color: Colors.white),
          ),
        );

      case TimelineStepState.active:
        return Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.accentBlue, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentBlue.withValues(alpha: 0.25),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: Icon(step.icon, size: 16, color: AppTheme.accentBlue),
          ),
        );

      case TimelineStepState.upcoming:
        return Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
          ),
          child: Center(
            child: Icon(step.icon, size: 14, color: const Color(0xFF94A3B8)),
          ),
        );
    }
  }
}
