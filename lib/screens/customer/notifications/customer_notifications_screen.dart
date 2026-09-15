import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/notification_model.dart';
import '../../../services/notification_service.dart';
import '../orders/customer_orders_screen.dart';
import '../delivery/delivery_tracking_screen.dart';

class CustomerNotificationsScreen extends StatefulWidget {
  final VoidCallback? onNotificationsCleared;

  const CustomerNotificationsScreen({super.key, this.onNotificationsCleared});

  @override
  State<CustomerNotificationsScreen> createState() => _CustomerNotificationsScreenState();
}

class _CustomerNotificationsScreenState extends State<CustomerNotificationsScreen> {
  final NotificationService _notificationService = NotificationService();
  List<NotificationModel> _notifications = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final notifications = await _notificationService.getNotifications();
      if (mounted) {
        setState(() {
          _notifications = notifications;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load notifications';
          _isLoading = false;
        });
      }
    }
  }

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  Future<void> _markAllAsRead() async {
    final unreadIds = _notifications
        .where((n) => !n.isRead)
        .map((n) => n.id)
        .toList();

    if (unreadIds.isEmpty) return;

    try {
      await _notificationService.markAllAsRead(unreadIds);
      setState(() {
        for (var n in _notifications) {
          n.isRead = true;
        }
      });
      widget.onNotificationsCleared?.call(); // Notify parent
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to mark all as read: $e')),
        );
      }
    }
  }

  Future<void> _onNotificationTap(NotificationModel notif) async {
    if (!notif.isRead) {
      try {
        await _notificationService.markAsRead(notif.id);
        setState(() {
          notif.isRead = true;
        });
        widget.onNotificationsCleared?.call(); // Notify parent
      } catch (e) {
        print('Error marking notification as read: $e');
      }
    }

    // Navigate based on notification type
    if (!mounted) return;
    
    final type = notif.type;
    if (type == 'delivery') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const DeliveryTrackingScreen()),
      );
    } else if (type == 'order' || type == 'order_update') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const CustomerOrdersScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text(
                'Mark all read',
                style: TextStyle(
                  color: AppTheme.accentBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_notifications.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadNotifications,
      child: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: _notifications.length,
        separatorBuilder: (context, index) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final notif = _notifications[index];
          return _buildNotificationCard(notif);
        },
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 80, color: AppTheme.errorRed.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Something went wrong',
              style: const TextStyle(fontSize: 16, color: AppTheme.textDark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadNotifications,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 80, color: AppTheme.textLight.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text(
              'No notifications yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
            ),
            const SizedBox(height: 8),
            const Text(
              'You\'ll receive live updates here when your laundry order progresses.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textLight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(NotificationModel notif) {
    final bool isRead = notif.isRead;
    Color iconColor;
    Color iconBgColor;
    IconData icon;

    switch (notif.type) {
      case 'delivery':
        iconColor = AppTheme.teamMemberIconOrange;
        iconBgColor = AppTheme.teamMemberOrange;
        icon = Icons.delivery_dining;
        break;
      case 'payment':
        iconColor = Colors.green;
        iconBgColor = Colors.green.withValues(alpha: 0.12);
        icon = Icons.payments_outlined;
        break;
      case 'completed':
        iconColor = Colors.green;
        iconBgColor = Colors.green.withValues(alpha: 0.12);
        icon = Icons.check_circle_outline;
        break;
      case 'alert':
        iconColor = AppTheme.errorRed;
        iconBgColor = AppTheme.errorRed.withValues(alpha: 0.12);
        icon = Icons.warning_amber_rounded;
        break;
      case 'announcement':
        iconColor = AppTheme.accentBlue;
        iconBgColor = AppTheme.lightBlue;
        icon = Icons.campaign;
        break;
      default:
        iconColor = AppTheme.accentBlue;
        iconBgColor = AppTheme.lightBlue;
        icon = Icons.local_laundry_service;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onNotificationTap(notif),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isRead ? Colors.white : AppTheme.accentBlue.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isRead ? AppTheme.borderGray.withValues(alpha: 0.6) : AppTheme.accentBlue.withValues(alpha: 0.3),
              width: isRead ? 1 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            notif.title,
                            style: TextStyle(
                              fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                              fontSize: 15,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.accentBlue,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notif.message,
                      style: TextStyle(
                        fontSize: 12,
                        color: isRead ? AppTheme.textLight : AppTheme.textDark.withValues(alpha: 0.8),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      notif.timeAgo,
                      style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
