import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import 'payment_process_screen.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _showPaid = false;

  // Mock data
  final List<LaundryOrder> _orders = [
    LaundryOrder(
      id: 'IW-101',
      customerName: 'Alice Green',
      channel: OrderChannel.walkIn,
      status: OrderStatus.ready,
      paymentStatus: PaymentStatus.unpaid,
      loads: [
        OrderLoad(
          loadNumber: 1,
          category: 'Regular Clothing',
          weight: 4.5,
          categoryLimit: 8.0,
          unit: 'kg',
          description: 'T-shirts, shorts, sleeveless, socks, underwear',
          isOverLimit: false,
          loadStatus: LoadStatus.folded,
        ),
      ],
      createdAt: DateTime.now(),
    ),
    LaundryOrder(
      id: 'IW-102',
      customerName: 'Charlie Brown',
      channel: OrderChannel.online,
      collectionMethod: CollectionMethod.riderPickup,
      returnMethod: ReturnMethod.delivery,
      status: OrderStatus.completed,
      paymentStatus: PaymentStatus.paid,
      loads: [
        OrderLoad(
          loadNumber: 1,
          category: 'Heavy Clothing',
          weight: 6.0,
          categoryLimit: 6.0,
          unit: 'kg',
          description: 'Jeans, cargo, jackets, sweaters, corduroy',
          isOverLimit: false,
          loadStatus: LoadStatus.folded,
        ),
      ],
      createdAt: DateTime.now(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final filteredOrders = _orders.where((o) => 
      _showPaid ? o.paymentStatus == PaymentStatus.paid : o.paymentStatus == PaymentStatus.unpaid
    ).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Payments'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                _buildFilterChip('Unpaid', !_showPaid),
                const SizedBox(width: 12),
                _buildFilterChip('Paid', _showPaid),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: filteredOrders.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) => _buildPaymentCard(filteredOrders[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected) {
    return GestureDetector(
      onTap: () => setState(() => _showPaid = label == 'Paid'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentBlue : AppTheme.softGray,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textDark,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentCard(LaundryOrder order) {
    double total = 170.0; // Flat Full Service package rate (₱170.00)
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: order.paymentStatus == PaymentStatus.paid ? Colors.green.withValues(alpha: 0.1) : AppTheme.errorRed.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              order.paymentStatus == PaymentStatus.paid ? Icons.check : Icons.payment,
              color: order.paymentStatus == PaymentStatus.paid ? Colors.green : AppTheme.errorRed,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.customerName, style: AppTheme.lightTheme.textTheme.titleMedium),
                Text('Order ${order.id}', style: AppTheme.lightTheme.textTheme.bodyMedium),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₱${total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              if (order.paymentStatus == PaymentStatus.unpaid)
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => PaymentProcessScreen(order: order)),
                    );
                  },
                  child: const Text('Pay Now', style: TextStyle(color: AppTheme.accentBlue)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
