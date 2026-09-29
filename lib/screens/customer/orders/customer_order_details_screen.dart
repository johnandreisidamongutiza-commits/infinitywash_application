import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import '../../../services/feedback_service.dart';
import '../../../services/customer_service.dart';
import '../../../widgets/star_rating.dart';
import 'request_service_flow.dart';
import '../chats/customer_chat_detail_screen.dart';

class CustomerOrderDetailsScreen extends StatefulWidget {
  final LaundryOrder order;

  const CustomerOrderDetailsScreen({super.key, required this.order});

  @override
  State<CustomerOrderDetailsScreen> createState() => _CustomerOrderDetailsScreenState();
}

class _CustomerOrderDetailsScreenState extends State<CustomerOrderDetailsScreen> {
  final FeedbackService _feedbackService = FeedbackService();
  final CustomerService _customerService = CustomerService();
  final TextEditingController _commentController = TextEditingController();

  Map<String, dynamic>? _existingFeedback;
  bool _isLoadingFeedback = true;
  bool _isSubmitting = false;
  int _selectedRating = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFeedback();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
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
        _error = 'Failed to load feedback';
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
            content: Text('Thank you for your feedback! 🎉'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadFeedback();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit feedback: ${e.toString()}'),
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
    final isCompleted = widget.order.status == OrderStatus.completed;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Order Details'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildTimeline(),
            const SizedBox(height: 24),
            _buildServiceDetails(),
            const SizedBox(height: 24),
            _buildPaymentInfo(),
            if (isCompleted) ...[
              const SizedBox(height: 24),
              _buildFeedbackSection(),
            ],
            const SizedBox(height: 24),
            _buildActionButtons(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
                  color: _getStatusColor().withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getStatusIcon(),
                  color: _getStatusColor(),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order #${widget.order.displayNumber}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_getStatusText()} • ${_formatDateTime(widget.order.createdAt)}',
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

  Widget _buildTimeline() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Timeline',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 16),
          _buildTimelineItem(
            'Requested',
            widget.order.createdAt,
            Icons.schedule,
            isCompleted: true,
          ),
          if (widget.order.status == OrderStatus.processing ||
              widget.order.status == OrderStatus.ready ||
              widget.order.status == OrderStatus.out_for_delivery ||
              widget.order.status == OrderStatus.completed)
            _buildTimelineItem(
              'Processing',
              widget.order.createdAt,
              Icons.local_laundry_service,
              isCompleted: true,
            ),
          if (widget.order.status == OrderStatus.ready ||
              widget.order.status == OrderStatus.out_for_delivery ||
              widget.order.status == OrderStatus.completed)
            _buildTimelineItem(
              'Ready',
              widget.order.createdAt,
              Icons.check_circle,
              isCompleted: true,
            ),
          if (widget.order.status == OrderStatus.completed)
            _buildTimelineItem(
              'Completed',
              widget.order.createdAt,
              Icons.done_all,
              isCompleted: true,
              isLast: true,
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(
    String label,
    DateTime time,
    IconData icon, {
    required bool isCompleted,
    bool isLast = false,
  }) {
    return Row(
      children: [
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isCompleted ? AppTheme.accentBlue : Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 16,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 32,
                color: isCompleted ? AppTheme.accentBlue : Colors.grey[300],
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isCompleted ? AppTheme.textDark : AppTheme.textLight,
                ),
              ),
              Text(
                _formatDateTime(time),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textLight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildServiceDetails() {
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
          if (widget.order.loads.isNotEmpty) ...[
            ...widget.order.loads.map((load) => Padding(
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
                '${widget.order.totalWeight.toStringAsFixed(1)} kg',
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
                '${widget.order.loads.length}',
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

  Widget _buildPaymentInfo() {
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
              Text(
                '₱${(widget.order.totalAmount ?? 0.0).toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accentBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.order.paymentStatus == PaymentStatus.paid
                  ? Colors.green.withValues(alpha: 0.08)
                  : Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  widget.order.paymentStatus == PaymentStatus.paid
                      ? Icons.check_circle
                      : Icons.schedule,
                  size: 16,
                  color: widget.order.paymentStatus == PaymentStatus.paid
                      ? Colors.green
                      : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.order.paymentStatus == PaymentStatus.paid
                      ? 'Paid via ${widget.order.paymentMethod ?? "N/A"}'
                      : 'Payment Pending',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: widget.order.paymentStatus == PaymentStatus.paid
                        ? Colors.green
                        : Colors.orange,
                  ),
                ),
              ],
            ),
          ),
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
          const Row(
            children: [
              Text(
                '💬',
                style: TextStyle(fontSize: 20),
              ),
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

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RequestServiceFlow()),
              );
            },
            icon: const Icon(Icons.replay, size: 18),
            label: const Text(
              'Reorder',
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
        const SizedBox(height: 12),
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
                    orderId: widget.order.displayNumber,
                    phoneNumber: '0912-345-6789',
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

  Color _getStatusColor() {
    switch (widget.order.status) {
      case OrderStatus.completed:
        return Colors.green;
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return Colors.red;
      default:
        return AppTheme.accentBlue;
    }
  }

  IconData _getStatusIcon() {
    switch (widget.order.status) {
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

  String _getStatusText() {
    switch (widget.order.status) {
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
      default:
        return 'Unknown';
    }
  }
}
