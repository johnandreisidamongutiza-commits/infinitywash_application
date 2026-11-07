import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import '../../../theme/app_theme.dart';
import '../../../utils/app_error.dart';
import '../../../models/order.dart';
import '../../../services/feedback_service.dart';
import '../../../services/customer_service.dart';
import '../../../services/order_service.dart';
import '../../../services/payment_service.dart';
import '../../../services/arrival_proof_service.dart';
import '../../../widgets/star_rating.dart';
import '../../../widgets/order_timeline_view.dart';
import '../../shared/gcash_qr_payment_screen.dart';
import 'request_service_flow.dart';
import '../chats/customer_chat_detail_screen.dart';
import '../delivery/order_delivery_tracking_screen.dart';
import '../../../config/location_constants.dart';

class CustomerOrderDetailsScreen extends StatefulWidget {
  final LaundryOrder order;

  const CustomerOrderDetailsScreen({super.key, required this.order});

  @override
  State<CustomerOrderDetailsScreen> createState() => _CustomerOrderDetailsScreenState();
}

class _CustomerOrderDetailsScreenState extends State<CustomerOrderDetailsScreen>
    with WidgetsBindingObserver {
  final FeedbackService _feedbackService = FeedbackService();
  final CustomerService _customerService = CustomerService();
  final OrderService _orderService = OrderService();
  final ArrivalProofService _arrivalProofService = ArrivalProofService();
  final TextEditingController _commentController = TextEditingController();

  Map<String, dynamic>? _existingFeedback;
  bool _isLoadingFeedback = true;
  bool _isSubmitting = false;
  int _selectedRating = 0;
  
  // Order refresh management
  LaundryOrder? _latestOrder;
  bool _isRefreshing = false;
  bool _wasUpdated = false;
  bool _isLoadingArrivalProofs = false;
  List<ArrivalProof> _arrivalProofs = const [];
  Timer? _autoRefreshTimer;

  bool _isTerminalOrder(LaundryOrder? order) {
    if (order == null) return false;
    return order.status == OrderStatus.completed ||
        order.status == OrderStatus.cancelled ||
        order.status == OrderStatus.rejected;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _latestOrder = widget.order;
    _loadFeedback();
    _loadArrivalProofs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshOrder();
        _startAutoRefresh();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _commentController.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Pause polling when app is in background to save API requests
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      // Resume polling when returning to foreground if order is still active
      if (!_isTerminalOrder(_latestOrder)) {
        _refreshOrder();
        _startAutoRefresh();
      }
    }
  }

  /// Start auto-refresh timer (60 seconds for order detail view)
  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();

    // Do not poll if the order is already in a terminal state
    if (_isTerminalOrder(_latestOrder)) {
      return;
    }

    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (timer) {
        if (mounted && !_isRefreshing) {
          _refreshOrder();
        }
      },
    );
  }

  Future<void> _refreshOrder() async {
    if (!mounted) return;
    try {
      setState(() => _isRefreshing = true);

      // Fetch this one order by id.
      final updated =
          await _orderService.getOrderById(widget.order.id) ?? _latestOrder;

      if (mounted && updated != null) {
        // Check if total amount or status changed
        final oldTotal = _latestOrder?.totalAmount;
        final newTotal = updated.totalAmount;
        final oldStatus = _latestOrder?.status;
        final newStatus = updated.status;

        setState(() {
          _latestOrder = updated;
          _isRefreshing = false;
        });

        // Stop polling if the order reached a terminal status
        if (_isTerminalOrder(updated)) {
          _autoRefreshTimer?.cancel();
          _autoRefreshTimer = null;
        }

        // Show notification if amount or status changed
        if ((oldTotal != null && newTotal != null && oldTotal != newTotal) ||
            (oldStatus != null && oldStatus != newStatus)) {
          _wasUpdated = true;
          
          String message = '';
          if (oldTotal != newTotal && newTotal != null) {
            message = 'Order updated! New total: ₱${newTotal.toStringAsFixed(2)}';
          } else if (oldStatus != newStatus) {
            message = 'Order status updated to: ${updated.statusText}';
          }
          
          if (message.isNotEmpty && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: AppTheme.accentBlue,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          
          // Reset update flag after 3 seconds
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() => _wasUpdated = false);
            }
          });
        }
      }
      _loadArrivalProofs();
    } catch (e) {
      print('Error refreshing order: $e');
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _loadArrivalProofs() async {
    if (_isLoadingArrivalProofs) return;
    if (mounted) setState(() => _isLoadingArrivalProofs = true);
    try {
      final proofs = await _arrivalProofService
          .getProofsForCustomerOrder(widget.order.id);
      if (mounted) setState(() => _arrivalProofs = proofs);
    } catch (e) {
      debugPrint('Could not load customer arrival proofs: $e');
    } finally {
      if (mounted) setState(() => _isLoadingArrivalProofs = false);
    }
  }

  Future<void> _showPaymentOptions(LaundryOrder order) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Choose how to pay', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Total: ₱${(order.totalAmount ?? 0).toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.textLight)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _payOrderWithGcash(order);
                },
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Pay with GCash'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _showCashPaymentInstructions();
                },
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Pay with cash'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _payOrderWithGcash(LaundryOrder order) async {
    final amount = order.totalAmount ?? 0;
    final receipt = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (_) => GcashQrPaymentScreen(
          title: 'Pay with GCash',
          orderLabel: order.displayNumber,
          amount: amount,
          customerName: order.customerName,
        ),
      ),
    );
    if (receipt == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Text('Uploading receipt...')]),
      ),
    );
    try {
      await PaymentService().submitGcashPayment(
        orderId: order.id,
        amount: amount,
        receiptFile: receipt,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GCash receipt submitted for verification.')),
      );
      await _refreshOrder();
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit payment. ${mapErrorToMessage(error)}')),
      );
    }
  }

  Future<void> _showCashPaymentInstructions() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pay with cash'),
        content: const Text('Please give the cash payment to the rider or staff. They will confirm it in the system, and your order will show as paid after confirmation.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Got it')),
        ],
      ),
    );
  }

  void _showArrivalProof(ArrivalProof proof) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${proof.jobType == 'pickup' ? 'Pickup' : 'Delivery'} arrival proof',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  proof.signedUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const Padding(
                          padding: EdgeInsets.all(36),
                          child: CircularProgressIndicator(),
                        ),
                  errorBuilder: (context, error, stackTrace) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('This arrival photo is temporarily unavailable.'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showArrivalProofOptions() {
    if (_arrivalProofs.length == 1) {
      _showArrivalProof(_arrivalProofs.single);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Rider arrival proofs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            ..._arrivalProofs.map((proof) => ListTile(
                  leading: const Icon(Icons.location_on_outlined, color: AppTheme.accentBlue),
                  title: Text('${proof.jobType == 'pickup' ? 'Pickup' : 'Delivery'} arrival'),
                  subtitle: proof.createdAt == null
                      ? null
                      : Text(_formatDateTime(proof.createdAt!.toLocal())),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showArrivalProof(proof);
                  },
                )),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _loadFeedback() async {
    try {
      final feedback = await _feedbackService.getFeedbackForOrder(widget.order.id);
      setState(() {
        _existingFeedback = feedback;
        _isLoadingFeedback = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingFeedback = false;
      });
    }
  }

  Future<void> _submitFeedback() async {
    if (_selectedRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a rating'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final customerId = await _customerService.getCurrentAuthenticatedCustomerId();
      await _feedbackService.submitFeedback(
        orderId: widget.order.id,
        customerId: customerId,
        customerName: widget.order.customerName,
        rating: _selectedRating,
        comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thank you for your feedback!'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadFeedback();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mapErrorToMessage(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return '1d ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    }

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year}';
  }

  @override
  Widget build(BuildContext context) {
    final order = _latestOrder ?? widget.order;
    final isCompleted = order.status == OrderStatus.completed;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Order Details'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshOrder,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Show update notification badge
              if (_wasUpdated)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.refresh, color: Colors.white, size: 16),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Order updated by staff',
                          style: TextStyle(
                            color: AppTheme.accentBlue,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              
              _buildHeader(order),
              if (_arrivalProofs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _showArrivalProofOptions,
                    icon: const Icon(Icons.photo_camera_back_outlined, size: 17),
                    label: const Text("See proof of rider's arrival"),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accentBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
              if (_hasActiveDelivery(order)) ...[
                const SizedBox(height: 16),
                _buildLiveTrackingBanner(order),
              ],
              const SizedBox(height: 24),
              OrderTimelineView(order: order),
              const SizedBox(height: 24),
              _buildServiceDetails(order),
              const SizedBox(height: 24),
              _buildPaymentInfo(order),
              if (isCompleted) ...[
                const SizedBox(height: 24),
                _buildFeedbackSection(),
              ],
              const SizedBox(height: 24),
              _buildActionButtons(order),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(LaundryOrder order) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getStatusColor(order).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getStatusIcon(order),
                  color: _getStatusColor(order),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order #${order.displayNumber}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_getStatusText(order)} • ${_formatDateTime(order.createdAt)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }



  Widget _buildServiceDetails(LaundryOrder order) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Service Details',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 16),
          if (order.loads.isNotEmpty) ...[
            ...order.loads.map((load) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppTheme.accentBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Load ${load.loadNumber}: ${load.category} (${load.weight} kg)',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Weight',
                style: TextStyle(fontSize: 13, color: AppTheme.textLight),
              ),
              Text(
                '${order.totalWeight.toStringAsFixed(1)} kg',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Loads',
                style: TextStyle(fontSize: 13, color: AppTheme.textLight),
              ),
              Text(
                '${order.loads.length}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentInfo(LaundryOrder order) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Information',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Amount',
                style: TextStyle(fontSize: 14, color: AppTheme.textLight),
              ),
              Row(
                children: [
                  Text(
                    '₱${(order.totalAmount ?? 0.0).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _wasUpdated ? Colors.lightBlueAccent : AppTheme.accentBlue,
                    ),
                  ),
                  if (_wasUpdated) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.lightBlueAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.lightBlueAccent),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: Colors.lightBlueAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: order.paymentStatus == PaymentStatus.paid
                  ? AppTheme.statusCompletedBg
                  : AppTheme.statusActiveBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: order.paymentStatus == PaymentStatus.paid
                    ? AppTheme.statusCompletedBorder
                    : AppTheme.statusActiveBorder,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  order.paymentStatus == PaymentStatus.paid
                      ? Icons.check_circle_outline
                      : Icons.schedule,
                  size: 16,
                  color: order.paymentStatus == PaymentStatus.paid
                      ? AppTheme.statusCompleted
                      : AppTheme.statusActive,
                ),
                const SizedBox(width: 8),
                Text(
                  order.paymentStatus == PaymentStatus.paid
                      ? 'Paid via ${order.paymentMethod ?? "N/A"}'
                      : 'Payment Pending',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: order.paymentStatus == PaymentStatus.paid
                        ? AppTheme.statusCompleted
                        : AppTheme.statusActive,
                  ),
                ),
              ],
            ),
          ),
          if (order.status == OrderStatus.processing &&
              order.paymentStatus == PaymentStatus.unpaid) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showPaymentOptions(order),
                icon: const Icon(Icons.payment),
                label: const Text('Pay for laundry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeedbackSection() {
    if (_isLoadingFeedback) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: AppStyles.cardDecoration,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_existingFeedback != null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: AppStyles.cardDecoration.copyWith(
          color: Colors.green.withValues(alpha: 0.05),
          border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text(
                  'Feedback Submitted',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Your Rating',
              style: TextStyle(fontSize: 13, color: AppTheme.textLight),
            ),
            const SizedBox(height: 8),
            StarRatingDisplay(
              rating: _existingFeedback!['rating'] as int,
              size: 24,
              showCount: true,
            ),
            if (_existingFeedback!['comment'] != null && (_existingFeedback!['comment'] as String).isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Your Comment',
                style: TextStyle(fontSize: 13, color: AppTheme.textLight),
              ),
              const SizedBox(height: 8),
              Text(
                _existingFeedback!['comment'] as String,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textDark,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if ((_existingFeedback!['admin_reply'] as String?)?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 16),
              const Text(
                'Reply from InfinityWash',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryBlue,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _existingFeedback!['admin_reply'] as String,
                style: const TextStyle(fontSize: 14, color: AppTheme.textDark),
              ),
              if (_existingFeedback!['admin_reply_at'] != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Replied on ${_formatDateTime(DateTime.parse(_existingFeedback!['admin_reply_at'] as String))}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                ),
              ],
            ],
            const SizedBox(height: 12),
            Text(
              'Submitted on ${_formatDateTime(DateTime.parse(_existingFeedback!['created_at'] as String))}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
            ),
          ],
        ),
      );
    }

    // No feedback yet - show form
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rate_review_outlined, color: AppTheme.accentBlue, size: 20),
              SizedBox(width: 8),
              Text(
                'Rate Your Experience',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'How was our service?',
            style: TextStyle(fontSize: 13, color: AppTheme.textLight),
          ),
          const SizedBox(height: 12),
          Center(
            child: StarRating(
              rating: _selectedRating,
              size: 40,
              onRatingChanged: (rating) {
                setState(() {
                  _selectedRating = rating;
                });
              },
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Comments & Suggestions (Optional)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentController,
            maxLines: 3,
            maxLength: 150,
            decoration: InputDecoration(
              hintText: 'Tell us about your experience...',
              hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textLight),
              filled: true,
              fillColor: AppTheme.softGray,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitFeedback,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Submit Feedback',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(LaundryOrder order) {
    return Column(
      children: [
        if (_hasActiveDelivery(order)) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OrderDeliveryTrackingScreen(orderId: order.id),
                  ),
                );
              },
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: const Text(
                'Track Live Delivery',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CustomerChatDetailScreen(
                    recipientName: 'InfinityWash Support',
                    recipientRole: 'Customer Support',
                    recipientType: ChatRecipientType.support,
                    orderId: order.id,
                    orderNumber: order.displayNumber,
                    phoneNumber: LocationConstants.shopPhone,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text(
              'Contact Support',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(LaundryOrder order) => AppTheme.statusColor(order.status);

  IconData _getStatusIcon(LaundryOrder order) {
    switch (order.status) {
      case OrderStatus.completed:
        return Icons.check_circle;
      case OrderStatus.rejected:
        return Icons.cancel;
      case OrderStatus.cancelled:
        return Icons.block;
      default:
        return Icons.schedule;
    }
  }

  String _getStatusText(LaundryOrder order) {
    switch (order.status) {
      case OrderStatus.pending_approval:
        return 'Pending Approval';
      case OrderStatus.pending_pickup:
        return 'Pending Pickup';
      case OrderStatus.processing:
        return 'Processing';
      case OrderStatus.ready:
        return 'Ready';
      case OrderStatus.out_for_delivery:
        return 'Out for Delivery';
      case OrderStatus.completed:
        return 'Completed';
      case OrderStatus.rejected:
        return 'Rejected';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  bool _hasActiveDelivery(LaundryOrder order) {
    return order.status == OrderStatus.out_for_delivery ||
        (order.status == OrderStatus.pending_pickup &&
            order.collectionMethod == CollectionMethod.riderPickup) ||
        (order.status == OrderStatus.ready &&
            order.returnMethod == ReturnMethod.delivery);
  }

  Widget _buildLiveTrackingBanner(LaundryOrder order) {
    final isPickup = order.status == OrderStatus.pending_pickup;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OrderDeliveryTrackingScreen(orderId: order.id),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.statusActiveBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.statusActiveBorder),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: AppTheme.statusActive,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPickup ? Icons.shopping_bag : Icons.two_wheeler,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPickup ? 'Rider Pickup Active' : 'Laundry Out for Delivery',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppTheme.statusActive,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Track rider live location & arrival on the map.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textDark),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.statusActive,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Track',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
