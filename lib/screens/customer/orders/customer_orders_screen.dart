import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/top_notification.dart';
import '../delivery/delivery_tracking_screen.dart';
import 'customer_payment_screen.dart';
import 'request_service_flow.dart';

class CustomerOrdersScreen extends StatefulWidget {
  const CustomerOrdersScreen({super.key});

  @override
  State<CustomerOrdersScreen> createState() => _CustomerOrdersScreenState();
}

class _CustomerOrdersScreenState extends State<CustomerOrdersScreen> {
  int _selectedTabIndex = 0; // 0: Active, 1: History
  bool _hasActiveOrder = true; // For prototype demonstration
  bool _isIW105Completed = false;
  // Status of the order: 'processing' (approved by staff) vs 'pending_approval'
  String _orderStatus = 'processing';
  bool _isSpecsExpanded = false;
  bool _isBillingExpanded = true;
  int _orderRating = 0; // 0 means not yet reviewed
  String _feedbackComment = '';

  // Official InfinityWash pricing state variables
  bool _isWeighed = true;
  bool _isPaid = false;
  String _activePaymentMethod = 'GCash'; // 'GCash' or 'Cash on Delivery'
  double _activeWeight = 5.5; // Within 8kg limit for regular clothes
  final double _fullServicePrice = 170.0; // FULL SERVICE: Wash, Dry & Fold (Detergent + Fab Con + Delivery included)

  double get _totalAmount => _fullServicePrice; // ₱170.00 Flat

  final List<Map<String, dynamic>> _historyOrders = [
    {
      'orderId': 'IW-102',
      'date': 'Aug 28, 2026',
      'service': 'Wash & Fold',
      'weight': '5.0 kg',
      'amount': '₱300.00',
      'paymentMethod': 'GCash',
      'status': 'Delivered',
      'rating': 5,
      'comment': 'Great service! Clothes smell fantastic.',
      'rider': 'Michael Rider',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('My Orders'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppTheme.textDark),
            tooltip: 'Demo: Change Status',
            onSelected: (val) {
              setState(() {
                if (val == 'weighed_gcash_unpaid') {
                  _hasActiveOrder = true;
                  _isIW105Completed = false;
                  _orderStatus = 'processing';
                  _isWeighed = true;
                  _isPaid = false;
                  _activePaymentMethod = 'GCash';
                  _selectedTabIndex = 0;
                } else if (val == 'weighed_cod') {
                  _hasActiveOrder = true;
                  _isIW105Completed = false;
                  _orderStatus = 'processing';
                  _isWeighed = true;
                  _isPaid = false;
                  _activePaymentMethod = 'Cash on Delivery';
                  _selectedTabIndex = 0;
                } else if (val == 'weighed_gcash_paid') {
                  _hasActiveOrder = true;
                  _isIW105Completed = false;
                  _orderStatus = 'processing';
                  _isWeighed = true;
                  _isPaid = true;
                  _activePaymentMethod = 'GCash';
                  _selectedTabIndex = 0;
                } else if (val == 'unweighed') {
                  _hasActiveOrder = true;
                  _isIW105Completed = false;
                  _orderStatus = 'processing';
                  _isWeighed = false;
                  _isPaid = false;
                  _selectedTabIndex = 0;
                } else if (val == 'pending_approval') {
                  _hasActiveOrder = true;
                  _isIW105Completed = false;
                  _orderStatus = 'pending_approval';
                  _isWeighed = false;
                  _isPaid = false;
                  _selectedTabIndex = 0;
                } else if (val == 'completed') {
                  _hasActiveOrder = false;
                  _isIW105Completed = true;
                  _selectedTabIndex = 1;
                } else if (val == 'no_active') {
                  _hasActiveOrder = false;
                  _selectedTabIndex = 0;
                }
              });
              String message = '';
              if (val == 'weighed_gcash_unpaid') {
                message = 'Simulating: Verified 5.5 kg - GCash Payment Due';
              } else if (val == 'weighed_cod') {
                message = 'Simulating: Verified 5.5 kg - Cash on Delivery';
              } else if (val == 'weighed_gcash_paid') {
                message = 'Simulating: Paid via GCash (₱${_totalAmount.toStringAsFixed(2)})';
              } else if (val == 'unweighed') {
                message = 'Simulating: Pending Store Scale Weighing';
              } else if (val == 'pending_approval') {
                message = 'Simulating: Active Order (Pending Approval)';
              } else if (val == 'completed') {
                message = 'Order #IW-105 completed! Moved to History.';
              } else {
                message = 'Simulating: No Active Orders';
              }
              showTopNotification(
                context,
                message: message,
                icon: (val == 'completed' || val == 'weighed_gcash_paid') ? Icons.check_circle : Icons.swap_horiz,
                backgroundColor: (val == 'completed' || val == 'weighed_gcash_paid') ? Colors.green : AppTheme.accentBlue,
              );
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'weighed_gcash_unpaid',
                child: Text('Simulate: Weighed (GCash Due)'),
              ),
              const PopupMenuItem(
                value: 'weighed_cod',
                child: Text('Simulate: Weighed (Cash on Delivery)'),
              ),
              const PopupMenuItem(
                value: 'weighed_gcash_paid',
                child: Text('Simulate: Weighed & Paid (GCash)'),
              ),
              const PopupMenuItem(
                value: 'unweighed',
                child: Text('Simulate: Pending Scale Weighing'),
              ),
              const PopupMenuItem(
                value: 'pending_approval',
                child: Text('Simulate: Active (Pending Approval)'),
              ),
              const PopupMenuItem(
                value: 'completed',
                child: Text('Simulate: Order Completed (Move to History)'),
              ),
              const PopupMenuItem(
                value: 'no_active',
                child: Text('Simulate: No Active Orders'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: _selectedTabIndex == 0
                ? (_hasActiveOrder ? _buildActiveOrderView() : _buildNoOrderView())
                : _buildHistoryView(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final int historyCount = _historyOrders.length + (_isIW105Completed ? 1 : 0);
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.softGray,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              title: 'Active',
              count: _hasActiveOrder ? 1 : 0,
              isSelected: _selectedTabIndex == 0,
              onTap: () => setState(() => _selectedTabIndex = 0),
            ),
          ),
          Expanded(
            child: _buildTabButton(
              title: 'History',
              count: historyCount,
              isSelected: _selectedTabIndex == 1,
              onTap: () => setState(() => _selectedTabIndex = 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppTheme.accentBlue : AppTheme.textLight,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.accentBlue.withOpacity(0.12)
                    : AppTheme.borderGray.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? AppTheme.accentBlue : AppTheme.textLight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoOrderView() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 60.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_basket_outlined, size: 80, color: AppTheme.textLight.withOpacity(0.2)),
          const SizedBox(height: 20),
          Text(
            'No active orders',
            style: AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(color: AppTheme.textLight),
          ),
          const SizedBox(height: 8),
          const Text(
            'You don\'t have any laundry orders in progress right now.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RequestServiceFlow()),
              );
            },
            child: const Text('Request Laundry Service'),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryView() {
    final List<Widget> items = [];

    if (_isIW105Completed) {
      items.add(_buildHistoryCard({
        'orderId': 'IW-105',
        'date': 'Sept 04, 2026',
        'service': 'Wash, Dry & Fold',
        'weight': '5.5 kg',
        'amount': '₱350.00',
        'paymentMethod': 'GCash',
        'status': 'Delivered',
        'rider': 'Michael Rider',
      }, isCurrentSession: true));
    }

    for (var o in _historyOrders) {
      items.add(_buildHistoryCard(o));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: items,
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> order, {bool isCurrentSession = false}) {
    final int rating = isCurrentSession ? _orderRating : (order['rating'] ?? 0);
    final String comment = isCurrentSession ? _feedbackComment : (order['comment'] ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: AppStyles.cardDecoration,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.lightBlue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.check_circle_outline, color: AppTheme.accentBlue, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #${order['orderId']}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                      ),
                      Text(
                        order['date'],
                        style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 12, color: Colors.green),
                    SizedBox(width: 4),
                    Text(
                      'Delivered',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${order['service']} (${order['weight']})',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark),
              ),
              Text(
                order['amount'],
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.accentBlue),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.delivery_dining, size: 15, color: AppTheme.textLight),
              const SizedBox(width: 4),
              Text(
                'Rider: ${order['rider']} • ${order['paymentMethod']}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Rating section
          if (rating == 0) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.teamMemberOrange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.teamMemberIconOrange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star_outline, color: AppTheme.teamMemberIconOrange, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Rate this delivery',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => _showFeedbackBottomSheet(orderId: order['orderId']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.teamMemberIconOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Rate Order', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  ...List.generate(
                    5,
                    (i) => Icon(
                      i < rating ? Icons.star : Icons.star_border,
                      size: 14,
                      color: AppTheme.teamMemberIconOrange,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '($rating.0)',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  ),
                  if (comment.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '"$comment"',
                        style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.textLight),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  if (isCurrentSession) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _showFeedbackBottomSheet(orderId: order['orderId']),
                      child: const Text(
                        'Edit',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Reorder button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RequestServiceFlow()),
                );
              },
              icon: const Icon(Icons.replay, size: 16),
              label: const Text('Reorder', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveOrderView() {
    final bool isApproved = _orderStatus != 'pending_approval';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Existing Status Step Card (Kept exactly as requested)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: AppStyles.cardDecoration,
            child: Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Order IW-105', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
                    Text('Sept 04, 2026', style: TextStyle(fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 24),
                _buildStatusStep('Processing', Icons.sync, true),
                _buildConnector(true),
                _buildStatusStep('Ready', Icons.check_circle_outline, false),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Assigned Rider & Delivery Card
          _buildRiderInfoCard(),
          const SizedBox(height: 16),

          // 3. Expandable Laundry Specifications Card
          _buildLaundryDetailsCard(),
          const SizedBox(height: 16),

          // 4. Per-Kilo Payment Callout Action Card
          _buildPaymentActionCard(),
          const SizedBox(height: 16),

          // 5. Expandable Billing & Payment Breakdown Card
          _buildBillingBreakdownCard(),
          const SizedBox(height: 24),

          // 5. Action Buttons
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DeliveryTrackingScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.navigation_outlined, size: 20),
                SizedBox(width: 8),
                Text('Track Delivery on Map', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RequestServiceFlow()),
              );
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_shopping_cart, size: 20),
                SizedBox(width: 8),
                Text('Request New Service', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 6. Cancellation Rule: Can ONLY cancel if staff has NOT approved yet
          if (!isApproved)
            OutlinedButton(
              onPressed: _showCancelDialog,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                foregroundColor: AppTheme.errorRed,
                side: const BorderSide(color: AppTheme.errorRed),
              ),
              child: const Text('Cancel Active Request'),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderGray),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, size: 18, color: AppTheme.textLight),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Request approved by staff. Cannot be cancelled while processing.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textLight),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      showTopNotification(
                        context,
                        message: 'Support Hotline: 0912-345-6789. We are here to help!',
                        icon: Icons.support_agent,
                        backgroundColor: AppTheme.accentBlue,
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Support',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }





  void _showFeedbackBottomSheet({String? orderId}) {
    final String targetOrderId = orderId ?? 'IW-105';
    int tempRating = _orderRating == 0 ? 5 : _orderRating;
    final textController = TextEditingController(text: _feedbackComment);
    final List<String> complimentTags = [
      'Clean & Fresh',
      'On-time Delivery',
      'Neatly Folded',
      'Polite Rider',
      'Great Fragrance',
    ];
    final Set<String> selectedTags = {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              top: 24,
              left: 24,
              right: 24,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.borderGray,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Rate Order #$targetOrderId',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'How was your experience with InfinityWash and rider Michael?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppTheme.textLight),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starVal = index + 1;
                      return IconButton(
                        onPressed: () {
                          setModalState(() => tempRating = starVal);
                        },
                        iconSize: 36,
                        icon: Icon(
                          starVal <= tempRating ? Icons.star : Icons.star_border,
                          color: AppTheme.teamMemberIconOrange,
                        ),
                      );
                    }),
                  ),
                  Text(
                    tempRating == 5
                        ? 'Excellent! 🎉'
                        : tempRating == 4
                            ? 'Very Good 👍'
                            : tempRating == 3
                                ? 'Good 😊'
                                : tempRating == 2
                                    ? 'Fair 😐'
                                    : 'Needs Improvement 😞',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.teamMemberIconOrange),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Quick Compliments', style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontSize: 13)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: complimentTags.map((tag) {
                      final isSelected = selectedTags.contains(tag);
                      return FilterChip(
                        label: Text(tag, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : AppTheme.textDark)),
                        selected: isSelected,
                        selectedColor: AppTheme.accentBlue,
                        backgroundColor: AppTheme.softGray,
                        showCheckmark: false,
                        onSelected: (val) {
                          setModalState(() {
                            if (val) {
                              selectedTags.add(tag);
                            } else {
                              selectedTags.remove(tag);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: textController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Add a comment or special feedback (optional)...',
                      hintStyle: TextStyle(fontSize: 12, color: AppTheme.textLight.withOpacity(0.6)),
                      filled: true,
                      fillColor: AppTheme.softGray,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      String finalComment = textController.text.trim();
                      if (finalComment.isEmpty && selectedTags.isNotEmpty) {
                        finalComment = selectedTags.join(', ');
                      }
                      setState(() {
                        _orderRating = tempRating;
                        _feedbackComment = finalComment;
                      });
                      showTopNotification(
                        context,
                        message: 'Thank you! Your feedback for Order #IW-105 was submitted.',
                        icon: Icons.star,
                        backgroundColor: AppTheme.teamMemberIconOrange,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentBlue,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Submit Feedback', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Maybe Later', style: TextStyle(fontSize: 13, color: AppTheme.textLight)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRiderInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.lightBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.delivery_dining, color: AppTheme.accentBlue, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Michael Rider', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    SizedBox(height: 2),
                    Text('Honda Click (ABC-1234)', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  showTopNotification(
                    context,
                    message: 'Calling rider Michael (+63 912 345 6789)...',
                    icon: Icons.phone,
                    backgroundColor: AppTheme.accentBlue,
                  );
                },
                icon: const Icon(Icons.phone, color: AppTheme.accentBlue),
                tooltip: 'Call Rider',
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_outlined, size: 18, color: AppTheme.errorRed),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '123 Laundry St, Clean City',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                    ),
                    SizedBox(height: 2),
                    Text('Landmark: Near the blue gate', style: TextStyle(fontSize: 11, color: AppTheme.textLight)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Est. 4:00 PM',
                  style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLaundryDetailsCard() {
    return Container(
      decoration: AppStyles.cardDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() => _isSpecsExpanded = !_isSpecsExpanded);
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.lightBlue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.local_laundry_service_outlined, size: 20, color: AppTheme.accentBlue),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Laundry Specifications', style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(
                            !_isWeighed
                                ? 'Pending Weighing • Wash, Dry & Fold'
                                : '${_activeWeight.toStringAsFixed(1)} kg • Wash, Dry & Fold',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _isSpecsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: AppTheme.textLight,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isSpecsExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  _buildDetailRow('Service Type', 'Wash, Dry & Fold'),
                  const Divider(height: 16),
                  _buildDetailRow(
                    'Measured Weight',
                    !_isWeighed ? 'Pending Store Scale' : '${_activeWeight.toStringAsFixed(1)} kg (Within 8kg Regular Limit)',
                  ),
                  const Divider(height: 16),
                  _buildDetailRow('Package Rate', '₱170.00 Full Service (Detergent + Fab Con Included)'),
                  const Divider(height: 16),
                  _buildDetailRow('RFID Tag', 'IW-RF-10234'),
                  const Divider(height: 16),
                  _buildDetailRow('Collection', 'Rider Pick-up'),
                  const Divider(height: 16),
                  _buildDetailRow('Return Method', 'Doorstep Delivery'),
                  const Divider(height: 16),
                  _buildDetailRow('Special Instructions', 'No fabric softener please.'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentActionCard() {
    // 1. If clothes haven't been weighed yet by staff
    if (!_isWeighed) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.scale_outlined, color: Colors.amber, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pending Store Verification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                  SizedBox(height: 2),
                  Text(
                    'Once clothes are verified on the shop scale, your ₱170.00 full service bill will appear here.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textLight, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 2. Weighed and Paid via GCash
    if (_isPaid) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paid via GCash • ₱${_totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green),
                  ),
                  const SizedBox(height: 2),
                  const Text('Ref #902834195723 • Digital Receipt Issued', style: TextStyle(fontSize: 11, color: AppTheme.textLight)),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CustomerPaymentScreen(
                      orderId: 'IW-105',
                      weight: _activeWeight,
                      servicePrice: _fullServicePrice,
                      deliveryFee: 0.0,
                      totalAmount: _totalAmount,
                    ),
                  ),
                );
              },
              child: const Text('Receipt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.accentBlue)),
            ),
          ],
        ),
      );
    }

    // 3. Weighed and Cash on Delivery
    if (_activePaymentMethod == 'Cash on Delivery') {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.payments_outlined, color: Colors.teal, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cash on Delivery (₱${_totalAmount.toStringAsFixed(2)})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Verified weight: ${_activeWeight.toStringAsFixed(1)} kg (within 8kg limit). Please prepare exact cash for Michael Rider upon delivery.',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textLight, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 4. Weighed and GCash Payment is Due
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.accentBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.accentBlue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.receipt_long, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Verified Bill Ready',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.accentBlue),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('PAYMENT DUE', style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Total Due: ₱${_totalAmount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 2),
          const Text(
            'Full Service (Wash, Dry & Fold): ₱170.00 • Detergent, Fab Con & Delivery included',
            style: TextStyle(fontSize: 12, color: AppTheme.textLight),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CustomerPaymentScreen(
                    orderId: 'IW-105',
                    weight: _activeWeight,
                    servicePrice: _fullServicePrice,
                    deliveryFee: 0.0,
                    totalAmount: _totalAmount,
                    onPaymentSuccess: () {
                      setState(() {
                        _isPaid = true;
                      });
                      showTopNotification(
                        context,
                        message: 'Payment of ₱${_totalAmount.toStringAsFixed(2)} confirmed via GCash!',
                        icon: Icons.check_circle,
                        backgroundColor: Colors.green,
                      );
                    },
                  ),
                ),
              );
            },
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
            label: Text('Pay ₱${_totalAmount.toStringAsFixed(2)} via GCash'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingBreakdownCard() {
    return Container(
      decoration: AppStyles.cardDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() => _isBillingExpanded = !_isBillingExpanded);
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.lightBlue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.receipt_long_outlined, size: 20, color: AppTheme.accentBlue),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Billing & Payment', style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(
                            !_isWeighed
                                ? 'Store weighing required'
                                : '₱${_totalAmount.toStringAsFixed(2)} • ${_isPaid ? 'Paid via GCash' : (_activePaymentMethod == 'GCash' ? 'Payment Due' : 'Cash on Delivery')}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                          ),
                        ],
                      ),
                    ),
                    _buildBillingStatusBadge(),
                    Icon(
                      _isBillingExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: AppTheme.textLight,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isBillingExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  if (!_isWeighed) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.softGray,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.scale_outlined, size: 20, color: AppTheme.accentBlue),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Laundry is awaiting store scale verification. Full service is ₱170.00 / load (Pickup & Delivery included).',
                              style: TextStyle(fontSize: 12, color: AppTheme.textLight, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    _buildBillingRow(
                      'Full Service: Wash, Dry & Fold (${_activeWeight.toStringAsFixed(1)} kg)',
                      '₱${_fullServicePrice.toStringAsFixed(2)}',
                    ),
                    _buildBillingRow('Detergent + Fab Con', 'INCLUDED (FREE)'),
                    _buildBillingRow('Pick Up & Delivery', 'INCLUDED (FREE)'),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Text(
                          '₱${_totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                            color: AppTheme.accentBlue,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBillingStatusBadge() {
    if (!_isWeighed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('UNWEIGHED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber)),
      );
    }
    if (_isPaid) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 12, color: Colors.green),
            SizedBox(width: 4),
            Text('PAID', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
          ],
        ),
      );
    }
    if (_activePaymentMethod == 'Cash on Delivery') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('COD', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text('DUE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange)),
    );
  }

  Widget _buildBillingRow(String label, String amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textLight)),
          Text(amount, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
        ],
      ),
    );
  }

  void _showCancelDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Request?'),
        content: const Text('Are you sure you want to cancel this laundry request? Since it is still pending approval, no fees will be charged.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Order'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _hasActiveOrder = false);
              showTopNotification(
                context,
                message: 'Your laundry request has been cancelled.',
                icon: Icons.check_circle,
                backgroundColor: AppTheme.errorRed,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusStep(String label, IconData icon, bool isActive) {
    Color color = isActive ? AppTheme.accentBlue : AppTheme.textLight.withOpacity(0.3);
    return Row(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 16),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            fontSize: 18,
          ),
        ),
        const Spacer(),
        if (isActive) const Icon(Icons.pending, color: AppTheme.accentBlue),
      ],
    );
  }

  Widget _buildConnector(bool isActive) {
    return Container(
      margin: const EdgeInsets.only(left: 24),
      height: 30,
      width: 2,
      color: isActive ? AppTheme.accentBlue : AppTheme.borderGray,
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textLight)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark),
            ),
          ),
        ],
      ),
    );
  }
}
