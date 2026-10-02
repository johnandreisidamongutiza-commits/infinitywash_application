import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/top_notification.dart';
import '../../../models/order.dart';
import '../../../services/service_request_service.dart';
import '../../../services/customer_service.dart';
import '../../../services/feedback_service.dart';
import 'request_service_flow.dart';
import 'customer_order_details_screen.dart';
import '../chats/customer_chat_detail_screen.dart';

class CustomerOrdersScreen extends StatefulWidget {
  const CustomerOrdersScreen({super.key});

  @override
  State<CustomerOrdersScreen> createState() => _CustomerOrdersScreenState();
}

class _CustomerOrdersScreenState extends State<CustomerOrdersScreen> {
  final ServiceRequestService _serviceRequestService = ServiceRequestService();
  final CustomerService _customerService = CustomerService();
  final FeedbackService _feedbackService = FeedbackService();
  int _selectedTabIndex = 0; // 0: Requests, 1: Active, 2: History
  final Set<String> _expandedOrderIds = {};
  
  // Loading and data state
  bool _isLoading = false;
  List<LaundryOrder> _customerOrders = [];
  String? _errorMessage;
  
  // Feedback cache: orderId -> hasFeedback
  final Map<String, bool> _feedbackStatus = {};
  
  // Real-time subscription
  StreamSubscription? _ordersSubscription;
  String? _currentCustomerId;

  @override
  void initState() {
    super.initState();
    _loadCustomerOrders();
    _subscribeToOrderUpdates();
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    super.dispose();
  }

  /// Subscribe to real-time order updates
  void _subscribeToOrderUpdates() async {
    try {
      // Get customer ID
      final customerId = await _customerService.getCurrentAuthenticatedCustomerId();
      _currentCustomerId = customerId;
      
      // Subscribe to orders table changes for this customer
      // NOTE: Real-time stream only includes orders table, not joined data (order_loads, etc.)
      // So we refetch full data when changes are detected
      _ordersSubscription = Supabase.instance.client
          .from('orders')
          .stream(primaryKey: ['id'])
          .eq('customer_id', customerId)
          .listen((data) {
            if (mounted) {
              // Don't use real-time data directly - it lacks joins
              // Instead, trigger a full refresh to get complete data
              _loadCustomerOrders();
            }
          });
      
      print('✅ Subscribed to real-time order updates for customer: $customerId');
    } catch (e) {
      print('⚠️ Error setting up real-time subscription: $e');
    }
  }

  /// Handle real-time order updates (Deprecated - now triggers full refresh)
  /// Kept for reference but no longer used
  // void _handleOrdersUpdate(List<Map<String, dynamic>> data) {
  //   // Real-time stream data doesn't include joins (order_loads, customers, etc.)
  //   // So parsing it directly creates incomplete order objects
  //   // Instead, we now trigger _loadCustomerOrders() which uses proper query with joins
  // }

  /// Load customer orders from database
  Future<void> _loadCustomerOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get authenticated customer ID
      final customerId = await _customerService.getCurrentAuthenticatedCustomerId();
      
      // Fetch orders for this customer
      final orders = await _serviceRequestService.getOrdersByCustomerId(customerId);
      
      // Load feedback status for completed orders
      await _loadFeedbackStatus(orders);
      
      setState(() {
        _customerOrders = orders;
        _isLoading = false;
      });
      print('✅ Loaded ${orders.length} customer orders');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load orders: ${e.toString()}';
      });
      print('❌ Error loading customer orders: $e');
    }
  }

  /// Load feedback status for orders
  Future<void> _loadFeedbackStatus(List<LaundryOrder> orders) async {
    final completedOrders = orders.where((o) => o.status == OrderStatus.completed);
    
    for (final order in completedOrders) {
      try {
        final feedback = await _feedbackService.getFeedbackForOrder(order.id);
        _feedbackStatus[order.id] = feedback != null;
      } catch (e) {
        print('⚠️ Error loading feedback for ${order.id}: $e');
        _feedbackStatus[order.id] = false;
      }
    }
  }

  /// Cancel an order
  Future<void> _cancelOrder(String orderId) async {
    try {
      await _serviceRequestService.cancelOrder(orderId);
      
      // Show success notification
      if (mounted) {
        showTopNotification(
          context,
          message: 'Request cancelled successfully',
          icon: Icons.check_circle,
          backgroundColor: Colors.green,
        );
      }
      
      // Reload orders to reflect the change
      await _loadCustomerOrders();
    } catch (e) {
      print('❌ Error cancelling order: $e');
      
      // Show error notification
      if (mounted) {
        showTopNotification(
          context,
          message: 'Failed to cancel request: ${e.toString()}',
          icon: Icons.error,
          backgroundColor: Colors.red,
        );
      }
    }
  }

  /// Filter orders by status for different tabs
  List<LaundryOrder> get _requestOrders => _customerOrders.where((order) => 
      order.status == OrderStatus.pending_approval).toList();
  
  List<LaundryOrder> get _activeOrders => _customerOrders.where((order) => 
      order.status == OrderStatus.pending_pickup ||
      order.status == OrderStatus.processing || 
      order.status == OrderStatus.ready || 
      order.status == OrderStatus.out_for_delivery).toList();
  
  List<LaundryOrder> get _historyOrders => _customerOrders.where((order) => 
      order.status == OrderStatus.completed || 
      order.status == OrderStatus.rejected ||
      order.status == OrderStatus.cancelled).toList();

  /// Get payment method display text based on order's payment preference
  String _getPaymentMethodDisplay(LaundryOrder order) {
    // If already paid, show the actual payment method used
    if (order.paymentStatus == PaymentStatus.paid && order.paymentMethod != null) {
      return order.paymentMethod!;
    }
    
    // Otherwise, show the customer's preferred payment method
    if (order.paymentPreference != null && order.paymentPreference!.isNotEmpty) {
      return order.paymentPreference!;
    }
    
    // Default to GCash for old orders without preference
    return 'GCash';
  }

  /// Get pay button text based on payment preference
  String _getPayButtonText(LaundryOrder order, double amount) {
    final preference = order.paymentPreference ?? 'GCash';
    final amountStr = '₱${amount.toStringAsFixed(2)}';
    
    if (preference == 'Cash on Delivery') {
      return 'Confirm Cash on Delivery ($amountStr)';
    } else if (preference == 'GCash') {
      return 'Pay $amountStr via GCash';
    } else {
      return 'Pay $amountStr via $preference';
    }
  }

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
          if (_activeOrders.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CustomerChatDetailScreen(
                        recipientName: 'InfinityWash Support',
                        recipientRole: 'Customer Support Helpdesk',
                        recipientType: ChatRecipientType.support,
                        orderId: _activeOrders.first.displayNumber,
                        phoneNumber: '0912-345-6789',
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.softGray,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.8)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 13, color: AppTheme.accentBlue),
                      SizedBox(width: 4),
                      Text(
                        'Need help?',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadCustomerOrders,
        color: AppTheme.accentBlue,
        child: Column(
          children: [
            _buildTabBar(),
            Expanded(
              child: _buildCurrentTabView(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const RequestServiceFlow()),
          );
          
          // If a service request was submitted successfully, refresh the data
          if (result == true) {
            _loadCustomerOrders();
          }
        },
        backgroundColor: AppTheme.accentBlue,
        icon: const Icon(Icons.add),
        label: const Text('Request Service', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildTabBar() {
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
              title: 'Requests',
              count: _requestOrders.length,
              isSelected: _selectedTabIndex == 0,
              onTap: () => setState(() => _selectedTabIndex = 0),
            ),
          ),
          Expanded(
            child: _buildTabButton(
              title: 'Active',
              count: _activeOrders.length,
              isSelected: _selectedTabIndex == 1,
              onTap: () => setState(() => _selectedTabIndex = 1),
            ),
          ),
          Expanded(
            child: _buildTabButton(
              title: 'History',
              count: _historyOrders.length,
              isSelected: _selectedTabIndex == 2,
              onTap: () => setState(() => _selectedTabIndex = 2),
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
                    color: Colors.black.withValues(alpha: 0.06),
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
                    ? AppTheme.accentBlue.withValues(alpha: 0.12)
                    : AppTheme.borderGray.withValues(alpha: 0.5),
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

  Widget _buildCurrentTabView() {
    // Handle loading state
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your orders...', style: TextStyle(color: AppTheme.textLight)),
          ],
        ),
      );
    }

    // Handle error state
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadCustomerOrders,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Handle normal state
    switch (_selectedTabIndex) {
      case 0:
        return _buildRequestsTab();
      case 1:
        return _buildActiveTab();
      case 2:
        return _buildHistoryTab();
      default:
        return const SizedBox();
    }
  }

  // ==================== REQUESTS TAB ====================
  Widget _buildRequestsTab() {
    if (_requestOrders.isEmpty) {
      return _buildEmptyState(
        icon: Icons.pending_actions_outlined,
        title: 'No pending requests',
        subtitle: 'You don\'t have any laundry requests awaiting review.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
      itemCount: _requestOrders.length,
      itemBuilder: (context, index) {
        final order = _requestOrders[index];
        return _buildRequestCard(order);
      },
    );
  }

  Widget _buildRequestCard(LaundryOrder order) {
    final bool isExpanded = _expandedOrderIds.contains(order.id);
    final bool isRejected = order.status == OrderStatus.rejected;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: AppStyles.cardDecoration,
      child: Column(
        children: [
          // Collapsed header - always visible
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedOrderIds.remove(order.id);
                } else {
                  _expandedOrderIds.add(order.id);
                }
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isRejected
                          ? Colors.red.withValues(alpha: 0.1)
                          : AppTheme.teamMemberOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isRejected ? Icons.cancel_outlined : Icons.pending_outlined,
                      color: isRejected ? Colors.red : AppTheme.teamMemberIconOrange,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order #${order.displayNumber}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDateTime(order.createdAt),
                          style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(order.status),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppTheme.textLight,
                  ),
                ],
              ),
            ),
          ),
          // Expanded details
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isRejected) ...[
                    _buildRejectionDetails(order),
                    const SizedBox(height: 16),
                  ] else ...[
                    _buildPendingApprovalDetails(order),
                    const SizedBox(height: 16),
                  ],
                  if (!isRejected)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              // Show confirmation dialog
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Cancel Request?'),
                                  content: const Text('Are you sure you want to cancel this service request? This action cannot be undone.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text('Keep Request'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                                      child: const Text('Cancel Request'),
                                    ),
                                  ],
                                ),
                              );
                              
                              // If user confirmed, cancel the order
                              if (confirmed == true) {
                                await _cancelOrder(order.id);
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Cancel Request', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPendingApprovalDetails(LaundryOrder order) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.teamMemberOrange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.teamMemberIconOrange.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: AppTheme.teamMemberIconOrange, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your request is being reviewed by our staff. You\'ll be notified once approved.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textDark),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (order.laundryPhotoUrls != null && order.laundryPhotoUrls!.isNotEmpty) ...[
          Text(
            'Photos (${order.laundryPhotoUrls!.length})',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: order.laundryPhotoUrls!.length,
              itemBuilder: (context, index) {
                final photos = order.laundryPhotoUrls!;
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => _CustomerRequestPhotoViewer(
                          photoUrls: photos,
                          initialIndex: index,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 80,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.softGray,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderGray),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildThumbnailImage(photos[index]),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (order.customerDescription != null && order.customerDescription!.isNotEmpty) ...[
          const Text(
            'Your Notes',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 4),
          Text(
            order.customerDescription!,
            style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
          ),
          const SizedBox(height: 12),
        ],
        _buildOrderDetailRow(Icons.location_on_outlined, 'Delivery Address', order.deliveryAddress ?? 'N/A'),
        const SizedBox(height: 8),
        _buildOrderDetailRow(Icons.phone_outlined, 'Contact', order.customerPhone ?? 'N/A'),
      ],
    );
  }

  Widget _buildRejectionDetails(LaundryOrder order) {
    String rejectionText = 'Your request was rejected';
    if (order.rejectionReason != null) {
      switch (order.rejectionReason) {
        case 'out_of_service_area':
          rejectionText = 'Out of service area';
          break;
        case 'capacity_full':
          rejectionText = 'Capacity full';
          break;
        case 'invalid_items':
          rejectionText = 'Invalid items';
          break;
        default:
          rejectionText = order.rejectionReason!;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cancel_outlined, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    rejectionText,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                ],
              ),
              if (order.staffMessage != null && order.staffMessage!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  order.staffMessage!,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textDark),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (order.reviewedAt != null) ...[
          Text(
            'Reviewed ${_formatDateTime(order.reviewedAt!)} by ${order.reviewedBy ?? "Staff"}',
            style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
          ),
        ],
      ],
    );
  }

  // ==================== ACTIVE TAB ====================
  Widget _buildActiveTab() {
    if (_activeOrders.isEmpty) {
      return _buildEmptyState(
        icon: Icons.shopping_basket_outlined,
        title: 'No active orders',
        subtitle: 'You don\'t have any orders in progress right now.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
      itemCount: _activeOrders.length,
      itemBuilder: (context, index) {
        final order = _activeOrders[index];
        return _buildActiveOrderCard(order);
      },
    );
  }

  Widget _buildActiveOrderCard(LaundryOrder order) {
    final bool isExpanded = _expandedOrderIds.contains(order.id);
    final bool needsPayment = order.paymentStatus == PaymentStatus.unpaid;
    // Use totalAmount from database if available, otherwise estimate from weight
    final double displayPrice = order.totalAmount != null && order.totalAmount! > 0 
        ? order.totalAmount! 
        : order.totalWeight * 30.0; // Fallback to ₱30/kg estimate

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: AppStyles.cardDecoration,
      child: Column(
        children: [
          // Collapsed header - More informative
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedOrderIds.remove(order.id);
                } else {
                  _expandedOrderIds.add(order.id);
                }
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Order #${order.displayNumber}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildStatusBadge(order.status),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: AppTheme.textLight,
                      ),
                    ],
                  ),
                  if (order.status == OrderStatus.processing || order.status == OrderStatus.ready) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.access_time, size: 12, color: Colors.green),
                          SizedBox(width: 4),
                          Text(
                            'Est. Today, 4:00 PM',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // Service title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.lightBlue,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _getStatusIcon(order.status),
                          color: AppTheme.accentBlue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Wash, Dry & Fold',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                            ),
                            Text(
                              _getStatusDescription(order.status) + (order.totalWeight > 0 ? ' • ${order.totalWeight.toStringAsFixed(1)} kg' : ''),
                              style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Progress tracker - always visible
                  _buildCompactProgressTracker(order.status),

                  // Payment banner for GCash/online payments if unpaid
                  if (needsPayment && 
                      order.totalWeight > 0 &&
                      order.paymentPreference != 'Cash on Delivery') ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.lightBlue,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.receipt_outlined, color: AppTheme.accentBlue, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Verified Bill Ready • ${_getPaymentMethodDisplay(order)} Due',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
                                ),
                                Text(
                                  'Total Due: ₱${displayPrice.toStringAsFixed(2)} (${order.totalWeight.toStringAsFixed(1)} kg)',
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textDark),
                                ),
                              ],
                            ),
                          ),
                          if (order.status == OrderStatus.processing || order.status == OrderStatus.ready)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'DUE',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],

                  // Cash on Delivery banner if COD selected  
                  if (needsPayment &&
                      order.totalWeight > 0 &&
                      order.paymentPreference == 'Cash on Delivery') ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.payments, color: Colors.green, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Verified Bill Ready • Cash on Delivery',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                                ),
                                Text(
                                  'Amount: ₱${displayPrice.toStringAsFixed(2)} (${order.totalWeight.toStringAsFixed(1)} kg)',
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textDark),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'COD',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Rider info for delivery status
                  if (order.status == OrderStatus.out_for_delivery) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.softGray,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: AppTheme.lightBlue,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.person, color: AppTheme.accentBlue, size: 20),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Michael Rider',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                                    ),
                                    Text(
                                      'Honda Click • ABC-1234',
                                      style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.phone, size: 16),
                                  label: const Text('Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  onPressed: () {},
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                                  label: const Text('Chat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  onPressed: () {},
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    showTopNotification(
                                      context,
                                      message: 'Opening live tracking...',
                                      icon: Icons.location_on,
                                      backgroundColor: AppTheme.accentBlue,
                                    );
                                  },
                                  icon: const Icon(Icons.map, size: 16),
                                  label: const Text('Track', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.accentBlue,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Expanded details
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildActiveOrderExpandedDetails(order),
            ),
          ],
        ],
      ),
    );
  }

  int _customerProgressStepIndex(OrderStatus status) {
    switch (status) {
      case OrderStatus.processing:
      case OrderStatus.ready:
      case OrderStatus.out_for_delivery:
        return 1;
      case OrderStatus.completed:
        return 2;
      default:
        return 0;
    }
  }

  Widget _buildCompactProgressTracker(OrderStatus status) {
    final steps = [
      {'label': 'Booked', 'icon': Icons.check_circle},
      {'label': 'Processing', 'icon': Icons.sync},
      {'label': 'Done', 'icon': Icons.check_circle},
    ];

    final currentStepIndex = _customerProgressStepIndex(status);

    return SizedBox(
      height: 50,
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int stepIndex = 0; stepIndex < steps.length; stepIndex++) ...[
            _buildCompactProgressStep(
              label: steps[stepIndex]['label'] as String,
              icon: steps[stepIndex]['icon'] as IconData,
              isActive: stepIndex <= currentStepIndex,
              isCurrent: stepIndex == currentStepIndex,
            ),
            if (stepIndex < steps.length - 1)
              Container(
                width: 40,
                height: 2,
                margin: const EdgeInsets.only(bottom: 14, left: 8, right: 8),
                color: stepIndex < currentStepIndex ? AppTheme.accentBlue : AppTheme.borderGray,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactProgressStep({
    required String label,
    required IconData icon,
    required bool isActive,
    required bool isCurrent,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive ? AppTheme.accentBlue : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? AppTheme.accentBlue : AppTheme.borderGray,
              width: 2,
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isActive ? Colors.white : AppTheme.textLight,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            color: isActive ? AppTheme.accentBlue : AppTheme.textLight,
          ),
        ),
      ],
    );
  }

  Widget _buildActiveOrderExpandedDetails(LaundryOrder order) {
    // Use totalAmount from database if available, otherwise estimate from weight
    final double displayPrice = order.totalAmount != null && order.totalAmount! > 0 
        ? order.totalAmount! 
        : order.totalWeight * 30.0; // Fallback to ₱30/kg estimate
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Delivery address section
        if (order.deliveryAddress != null) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on, size: 18, color: AppTheme.textLight),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.deliveryAddress!,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                    ),
                    if (order.deliveryLandmark != null)
                      Text(
                        '(${order.deliveryLandmark})',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textLight, fontStyle: FontStyle.italic),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
        ],

        // Order specs
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.softGray,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_laundry_service, size: 18, color: AppTheme.accentBlue),
                  const SizedBox(width: 8),
                  const Text(
                    'Wash, Dry & Fold',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  ),
                  const Spacer(),
                  if (order.paymentStatus == PaymentStatus.unpaid)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'DUE',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (order.loads.isNotEmpty)
                ...order.loads.map((load) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Text(
                            '  • ${load.weight.toStringAsFixed(1)} kg',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '• ${load.category}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                          ),
                          if (load.loadStatus != null) ...[
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getLoadStatusColor(load.loadStatus!).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _getLoadStatusText(load.loadStatus!),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _getLoadStatusColor(load.loadStatus!),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    )),
              if (order.customerDescription != null && order.customerDescription!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Your Notes',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                ),
                const SizedBox(height: 4),
                Text(
                  order.customerDescription!,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                ),
              ],
              if (order.instructions != null && order.instructions!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  order.instructions!,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textLight, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Pricing section
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.softGray,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Amount',
                    style: TextStyle(fontSize: 12, color: AppTheme.textLight),
                  ),
                  SizedBox(height: 2),
                ],
              ),
              // Dynamic payment method display
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Amount',
                    style: TextStyle(fontSize: 12, color: AppTheme.textLight),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _getPaymentMethodDisplay(order),
                    style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                  ),
                ],
              ),
              Text(
                '₱${displayPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
            ],
          ),
        ),

        // Pay button for GCash/online payments if unpaid
        if (order.paymentStatus == PaymentStatus.unpaid && 
            order.totalWeight > 0 &&
            order.paymentPreference != 'Cash on Delivery') ...[
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: () {
              showTopNotification(
                context,
                message: 'Opening ${order.paymentPreference ?? "GCash"} payment...',
                icon: Icons.payment,
                backgroundColor: AppTheme.accentBlue,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentBlue,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              _getPayButtonText(order, displayPrice),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],

        // Cash on Delivery notice if COD selected
        if (order.paymentStatus == PaymentStatus.unpaid &&
            order.totalWeight > 0 &&
            order.paymentPreference == 'Cash on Delivery') ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.payments, color: Colors.green, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cash on Delivery',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Please prepare ₱${displayPrice.toStringAsFixed(2)} when the rider arrives',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textDark),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 14),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CustomerChatDetailScreen(
                        recipientName: 'Support',
                        recipientRole: 'Customer Support',
                        recipientType: ChatRecipientType.support,
                        orderId: order.displayNumber,
                        phoneNumber: '0912-345-6789',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text('Chat', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (order.status != OrderStatus.pending_pickup) ...[
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    showTopNotification(
                      context,
                      message: 'Feature coming soon',
                      icon: Icons.help_outline,
                      backgroundColor: AppTheme.textLight,
                    );
                  },
                  icon: const Icon(Icons.help_outline, size: 16),
                  label: const Text('Help', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildProgressTracker(OrderStatus status) {
    final steps = [
      {'label': 'Booked', 'icon': Icons.check_circle_outline},
      {'label': 'Processing', 'icon': Icons.sync},
      {'label': 'Done', 'icon': Icons.check_circle_outline},
    ];

    final currentStepIndex = _customerProgressStepIndex(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Progress',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
        ),
        const SizedBox(height: 12),
        Row(
          children: List.generate(steps.length, (index) {
            final step = steps[index];
            final isActive = index <= currentStepIndex;
            final isCurrent = index == currentStepIndex;

            return Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isActive ? AppTheme.accentBlue : AppTheme.softGray,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            step['icon'] as IconData,
                            size: 18,
                            color: isActive ? Colors.white : AppTheme.textLight,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          step['label'] as String,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            color: isActive ? AppTheme.accentBlue : AppTheme.textLight,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  if (index < steps.length - 1)
                    Container(
                      width: 20,
                      height: 2,
                      color: isActive ? AppTheme.accentBlue : AppTheme.borderGray,
                    ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  // ==================== HISTORY TAB ====================
  Widget _buildHistoryTab() {
    if (_historyOrders.isEmpty) {
      return _buildEmptyState(
        icon: Icons.history,
        title: 'No order history',
        subtitle: 'Your completed orders will appear here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
      itemCount: _historyOrders.length,
      itemBuilder: (context, index) {
        final order = _historyOrders[index];
        return _buildHistoryCard(order);
      },
    );
  }

  Widget _buildHistoryCard(LaundryOrder order) {
    final bool hasFeedback = _feedbackStatus[order.id] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: AppStyles.cardDecoration,
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CustomerOrderDetailsScreen(order: order),
            ),
          );
          // Refresh if feedback was submitted
          if (result == true) {
            _loadCustomerOrders();
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.check_circle_outline, color: Colors.green, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order #${order.displayNumber}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Completed • ${_formatDateTime(order.createdAt)}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                    ),
                    const SizedBox(height: 6),
                    // Feedback badge
                    Row(
                      children: [
                        if (hasFeedback)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, size: 12, color: Color(0xFFFFD700)),
                                SizedBox(width: 4),
                                Text(
                                  'Rated',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFB8860B),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.accentBlue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '💬',
                                  style: TextStyle(fontSize: 10),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Rate this order',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.accentBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (order.totalWeight > 0)
                Text(
                  '${order.totalWeight.toStringAsFixed(1)} kg',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textLight),
                ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: AppTheme.textLight,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== HELPER WIDGETS ====================
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 80, color: AppTheme.textLight.withValues(alpha: 0.3)),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textLight),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(OrderStatus status) {
    Color bgColor;
    Color textColor;
    String text;
    IconData icon;

    switch (status) {
      case OrderStatus.pending_approval:
        bgColor = AppTheme.teamMemberOrange.withValues(alpha: 0.12);
        textColor = AppTheme.teamMemberIconOrange;
        text = 'Pending';
        icon = Icons.pending;
        break;
      case OrderStatus.rejected:
        bgColor = Colors.red.withValues(alpha: 0.12);
        textColor = Colors.red;
        text = 'Rejected';
        icon = Icons.cancel;
        break;
      case OrderStatus.cancelled:
        bgColor = Colors.grey.withValues(alpha: 0.12);
        textColor = Colors.grey;
        text = 'Cancelled';
        icon = Icons.block;
        break;
      case OrderStatus.pending_pickup:
        bgColor = Colors.blue.withValues(alpha: 0.12);
        textColor = Colors.blue;
        text = 'Pickup';
        icon = Icons.home;
        break;
      case OrderStatus.processing:
        const processingTeal = Color(0xFF0F766E);
        bgColor = processingTeal.withValues(alpha: 0.12);
        textColor = processingTeal;
        text = 'Processing';
        icon = Icons.sync;
        break;
      case OrderStatus.ready:
        const processingTeal = Color(0xFF0F766E);
        bgColor = processingTeal.withValues(alpha: 0.12);
        textColor = processingTeal;
        text = 'Processing';
        icon = Icons.sync;
        break;
      case OrderStatus.out_for_delivery:
        bgColor = AppTheme.accentBlue.withValues(alpha: 0.12);
        textColor = AppTheme.accentBlue;
        text = 'Delivering';
        icon = Icons.delivery_dining;
        break;
      case OrderStatus.completed:
        bgColor = Colors.green.withValues(alpha: 0.12);
        textColor = Colors.green;
        text = 'Completed';
        icon = Icons.check_circle;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppTheme.textLight),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
              ),
              Text(
                value,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textDark),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getStatusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_pickup:
        return Icons.home_outlined;
      case OrderStatus.processing:
        return Icons.sync;
      case OrderStatus.ready:
        return Icons.sync;
      case OrderStatus.out_for_delivery:
        return Icons.delivery_dining;
      default:
        return Icons.shopping_bag_outlined;
    }
  }

  String _getStatusDescription(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_pickup:
        return 'Waiting for rider pickup';
      case OrderStatus.processing:
        return 'Your laundry is being processed';
      case OrderStatus.ready:
        return 'Your laundry is being processed';
      case OrderStatus.out_for_delivery:
        return 'On the way to you';
      default:
        return '';
    }
  }

  Color _getLoadStatusColor(LoadStatus? status) {
    if (status == null) return AppTheme.textLight;
    switch (status) {
      case LoadStatus.queued:
        return AppTheme.textLight;
      case LoadStatus.washing:
        return Colors.blue;
      case LoadStatus.drying:
        return Colors.orange;
      case LoadStatus.folded:
        return Colors.green;
    }
  }

  String _getLoadStatusText(LoadStatus? status) {
    if (status == null) return 'Queued';
    switch (status) {
      case LoadStatus.queued:
        return 'Queued';
      case LoadStatus.washing:
        return 'Washing';
      case LoadStatus.drying:
        return 'Drying';
      case LoadStatus.folded:
        return 'Folded';
    }
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${dt.day}/${dt.month}/${dt.year}';
    }
  }

  Widget _buildThumbnailImage(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.photo, color: AppTheme.textLight, size: 32),
      );
    } else if (path.startsWith('data:image') ||
        (path.length > 100 && !path.startsWith('/') && !path.contains('\\'))) {
      try {
        final base64String = path.contains(',') ? path.split(',').last : path;
        final bytes = base64Decode(base64String.trim());
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.photo, color: AppTheme.textLight, size: 32),
        );
      } catch (e) {
        return const Icon(Icons.photo, color: AppTheme.textLight, size: 32);
      }
    } else {
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.photo, color: AppTheme.textLight, size: 32),
        );
      } else {
        return const Icon(Icons.photo, color: AppTheme.textLight, size: 32);
      }
    }
  }
}

class _CustomerRequestPhotoViewer extends StatefulWidget {
  final List<String> photoUrls;
  final int initialIndex;

  const _CustomerRequestPhotoViewer({
    required this.photoUrls,
    required this.initialIndex,
  });

  @override
  State<_CustomerRequestPhotoViewer> createState() => _CustomerRequestPhotoViewerState();
}

class _CustomerRequestPhotoViewerState extends State<_CustomerRequestPhotoViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.8),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: Text(
          'Photo ${_currentIndex + 1} of ${widget.photoUrls.length}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.photoUrls.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          final path = widget.photoUrls[index];
          return Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: _buildFullImage(path),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFullImage(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        },
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image, color: Colors.white54, size: 48),
              SizedBox(height: 8),
              Text('Unable to load photo', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      );
    } else if (path.startsWith('data:image') ||
        (path.length > 100 && !path.startsWith('/') && !path.contains('\\'))) {
      try {
        final base64String = path.contains(',') ? path.split(',').last : path;
        final bytes = base64Decode(base64String.trim());
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
          ),
        );
      } catch (e) {
        return const Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
        );
      }
    } else {
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
          ),
        );
      } else {
        return const Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
        );
      }
    }
  }
}
