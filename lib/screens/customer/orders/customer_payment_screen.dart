import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import '../../../services/order_service.dart';

class CustomerPaymentScreen extends StatefulWidget {
  final String orderId;
  final double weight;
  final double servicePrice;
  final double deliveryFee;
  final double? totalAmount;
  final VoidCallback? onPaymentSuccess;

  const CustomerPaymentScreen({
    super.key,
    this.orderId = 'IW-105',
    this.weight = 5.5,
    this.servicePrice = 170.0,
    this.deliveryFee = 0.0,
    this.totalAmount,
    this.onPaymentSuccess,
  });

  @override
  State<CustomerPaymentScreen> createState() => _CustomerPaymentScreenState();
}

class _CustomerPaymentScreenState extends State<CustomerPaymentScreen> {
  final OrderService _orderService = OrderService();
  String _selectedMethod = 'G-Cash';
  bool _isSuccess = false;
  final TextEditingController _refController = TextEditingController(text: '902834195723');
  
  // Order data management
  LaundryOrder? _latestOrder;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _wasUpdated = false;
  StreamSubscription? _orderSubscription;

  double get _finalTotal {
    if (_latestOrder != null && _latestOrder!.totalAmount != null) {
      return _latestOrder!.totalAmount!;
    }
    return widget.totalAmount ?? (widget.servicePrice + widget.deliveryFee);
  }

  double get _weight {
    return _latestOrder?.totalWeight ?? widget.weight;
  }

  double get _servicePrice {
    if (_latestOrder != null && _latestOrder!.totalAmount != null) {
      return _latestOrder!.totalAmount!;
    }
    return widget.servicePrice;
  }

  String get _orderDisplay => LaundryOrder.formatDisplayNumber(id: widget.orderId);

  @override
  void initState() {
    super.initState();
    _fetchLatestOrderData();
    _subscribeToOrderUpdates();
  }

  @override
  void dispose() {
    _refController.dispose();
    _orderSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchLatestOrderData() async {
    try {
      if (!_isLoading) {
        setState(() => _isRefreshing = true);
      }

      final orders = await _orderService.fetchOrders(
        statuses: null,
        limit: 100,
      );

      final order = orders.cast<LaundryOrder?>().firstWhere(
        (o) => o?.id == widget.orderId,
        orElse: () => null,
      );

      if (mounted) {
        setState(() {
          if (order != null) {
            // Check if order was updated (total changed)
            if (_latestOrder != null && 
                order.totalAmount != null && 
                _latestOrder!.totalAmount != order.totalAmount) {
              _wasUpdated = true;
              // Reset the flag after 3 seconds
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) {
                  setState(() => _wasUpdated = false);
                }
              });
            }
            _latestOrder = order;
          }
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      print('Error fetching order: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  void _subscribeToOrderUpdates() {
    try {
      _orderSubscription = Supabase.instance.client
          .from('orders')
          .stream(primaryKey: ['id'])
          .eq('id', widget.orderId)
          .listen((data) {
            if (data.isNotEmpty && mounted) {
              try {
                final updatedOrder = LaundryOrder.fromJson(data.first);
                
                // Check if total amount changed
                final oldTotal = _latestOrder?.totalAmount;
                final newTotal = updatedOrder.totalAmount;
                
                setState(() {
                  _latestOrder = updatedOrder;
                });

                // Show notification if amount changed
                if (oldTotal != null && 
                    newTotal != null && 
                    oldTotal != newTotal &&
                    !_isSuccess) {
                  _wasUpdated = true;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Order updated by staff! New total: ₱${newTotal.toStringAsFixed(2)}',
                      ),
                      backgroundColor: AppTheme.accentBlue,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                  
                  // Reset update flag after 3 seconds
                  Future.delayed(const Duration(seconds: 3), () {
                    if (mounted) {
                      setState(() => _wasUpdated = false);
                    }
                  });
                }
              } catch (e) {
                print('Error parsing real-time order update: $e');
              }
            }
          });
    } catch (e) {
      print('Error setting up real-time subscription: $e');
    }
  }

  void _completePayment() {
    setState(() => _isSuccess = true);
    widget.onPaymentSuccess?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_isSuccess) return _buildSuccessView();

    // Show loading state on initial load
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Complete Payment'),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Loading order details...',
                style: TextStyle(color: AppTheme.textLight, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Complete Payment'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchLatestOrderData,
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
              
              _buildAmountCard(),
              const SizedBox(height: 24),

              // Per-kilo bill breakdown
              _buildBreakdownCard(),
              const SizedBox(height: 24),

              Text('Payment Method', style: AppTheme.lightTheme.textTheme.titleMedium),
              const SizedBox(height: 12),
              _buildMethodCard(
                'G-Cash',
                Icons.account_balance_wallet_outlined,
                'Instant confirmation via GCash QR or number',
              ),
              const SizedBox(height: 10),
              _buildMethodCard(
                'Cash on Delivery',
                Icons.payments_outlined,
                'Pay rider in cash upon doorstep delivery',
              ),
              const SizedBox(height: 20),

              if (_selectedMethod == 'G-Cash') ...[
                _buildGcashInstructions(),
                const SizedBox(height: 20),
                Text('GCash Reference Number', style: AppTheme.lightTheme.textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _refController,
                  decoration: InputDecoration(
                    hintText: 'Enter 12-digit GCash reference #',
                    filled: true,
                    fillColor: AppTheme.softGray,
                    prefixIcon: const Icon(Icons.receipt_long, color: AppTheme.accentBlue),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter reference from your GCash SMS or receipt.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.green, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'You chose Cash on Delivery. Please prepare ₱${_finalTotal.toStringAsFixed(2)} when the rider arrives with your clean clothes.',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textDark, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _completePayment,
                child: Text(
                  _selectedMethod == 'G-Cash'
                      ? 'Confirm GCash Payment (₱${_finalTotal.toStringAsFixed(2)})'
                      : 'Confirm Cash on Delivery',
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAmountCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.accentBlue,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentBlue.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Verified Bill',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Order #$_orderDisplay',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '₱${_finalTotal.toStringAsFixed(2)}',
                style: TextStyle(
                  color: _wasUpdated ? Colors.lightBlueAccent : Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_wasUpdated) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.lightBlueAccent.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.lightBlueAccent),
                  ),
                  child: const Text(
                    'UPDATED',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Based on store verified weight: ${_weight.toStringAsFixed(1)} kg',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (_latestOrder != null && _latestOrder!.loads.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${_latestOrder!.loads.length} load${_latestOrder!.loads.length > 1 ? 's' : ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBreakdownCard() {
    final loads = _latestOrder?.loads ?? [];
    
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.softGray,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Itemized Calculation',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
          ),
          const Divider(height: 20),
          if (loads.isNotEmpty) ...[
            ...loads.map((load) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Load ${load.loadNumber}: ${load.category} (${load.weight} ${load.unit})',
                      style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
                    ),
                  ),
                  Text(
                    '₱170.00',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                  ),
                ],
              ),
            )),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Full Service Wash, Dry & Fold (${_weight.toStringAsFixed(1)} kg)',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
                ),
                Text(
                  '₱${_servicePrice.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Detergent + Fab Con',
                style: TextStyle(fontSize: 13, color: AppTheme.textDark),
              ),
              Text(
                'INCLUDED',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Pick Up & Delivery',
                style: TextStyle(fontSize: 13, color: AppTheme.textDark),
              ),
              Text(
                'INCLUDED (FREE)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Amount',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
              Text(
                '₱${_finalTotal.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _wasUpdated ? Colors.lightBlueAccent : AppTheme.accentBlue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMethodCard(String method, IconData icon, String subtitle) {
    final bool isSelected = _selectedMethod == method;
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = method),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.accentBlue : AppTheme.borderGray,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.accentBlue.withValues(alpha: 0.1) : AppTheme.softGray,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: isSelected ? AppTheme.accentBlue : AppTheme.textLight, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(method, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.textLight)),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? AppTheme.accentBlue : AppTheme.borderGray,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGcashInstructions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF007DFE).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF007DFE).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF007DFE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.qr_code_2, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Send via GCash Send Money / QR',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF005AB5)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Account Name:', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
              Text('INFINITYWASH HUB', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('GCash Mobile Number:', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
              Text('0917-555-WASH (9274)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, size: 54, color: Colors.green),
                ),
                const SizedBox(height: 20),
                Text('Payment Confirmed!', style: AppTheme.lightTheme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  _selectedMethod == 'G-Cash'
                      ? 'Your GCash payment has been verified. Your clean laundry is ready for dispatch.'
                      : 'Cash on delivery recorded. Please prepare payment upon delivery.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textLight, fontSize: 13),
                ),
                const SizedBox(height: 28),
                _buildReceiptCard(),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to Active Orders'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.softGray,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Column(
        children: [
          const Text('INFINITYWASH LAUNDRY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Text('Official E-Receipt', style: TextStyle(fontSize: 10, letterSpacing: 1.5, color: AppTheme.textLight)),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Order Number', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
              Text('#$_orderDisplay', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Verified Weight', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
              Text('${widget.weight.toStringAsFixed(1)} kg • Full Service (₱${widget.servicePrice.toStringAsFixed(0)})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Payment Mode', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
              Text(_selectedMethod, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          if (_selectedMethod == 'G-Cash') ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Reference No.', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
                Text(_refController.text.isNotEmpty ? _refController.text : '902834195723',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.accentBlue)),
              ],
            ),
          ],
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Paid', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text('₱${_finalTotal.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
            ],
          ),
        ],
      ),
    );
  }
}
