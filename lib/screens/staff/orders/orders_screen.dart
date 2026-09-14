import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import 'create_order_flow.dart';
import 'order_status_screen.dart';
import '../../../services/mock_data_service.dart';

class OrdersScreen extends StatefulWidget {
  final int initialTab;
  const OrdersScreen({super.key, this.initialTab = 1});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requestCount = MockDataService().pendingRequests.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Orders'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: AppTheme.softGray,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppTheme.accentBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.textLight,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              dividerHeight: 0,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Requests'),
                      if (requestCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$requestCount',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Tab(text: 'Active'),
                const Tab(text: 'History'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRequestsTab(),
          _buildActiveTab(),
          _buildHistoryTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateOrderFlow()),
          );
          setState(() {});
        },
        backgroundColor: AppTheme.accentBlue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // ========== REQUESTS TAB ==========

  Widget _buildRequestsTab() {
    final requests = MockDataService().pendingRequests;

    if (requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.online_prediction, size: 80, color: AppTheme.textLight.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text('No pending online requests', style: TextStyle(color: AppTheme.textLight)),
            const SizedBox(height: 8),
            Text(
              'New requests from customers will appear here.',
              style: TextStyle(color: AppTheme.textLight.withValues(alpha: 0.5), fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: requests.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _buildRequestCard(requests[index]),
    );
  }

  Widget _buildRequestCard(LaundryOrder request) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(request.id, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
              Row(
                children: [
                  _buildBadge(request.collectionText, AppTheme.accentBlue),
                  const SizedBox(width: 6),
                  _buildBadge(request.returnText, Colors.green),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(request.customerName, style: AppTheme.lightTheme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (request.instructions != null && request.instructions!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Note: ${request.instructions}',
                style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      MockDataService().declineRequest(request.id);
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.errorRed,
                    side: const BorderSide(color: AppTheme.errorRed),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _showApproveDialog(request),
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showApproveDialog(LaundryOrder request) {
    final weightController = TextEditingController();
    String? selectedRfidTag;
    String selectedCategory = 'Regular Clothing';
    final availableTags = MockDataService().availableRfidTags;

    final Map<String, Map<String, dynamic>> categories = {
      'Regular Clothing': {'limit': 8.0, 'unit': 'kg', 'desc': 'T-shirts, shorts, sleeveless, socks, underwear'},
      'Heavy Clothing': {'limit': 6.0, 'unit': 'kg', 'desc': 'Jeans, cargo, jackets, sweaters, corduroy'},
      'Beddings & Towels': {'limit': 5.0, 'unit': 'kg', 'desc': 'Bedsheets, blankets, towels, curtains'},
      'Heavyweight Beddings': {'limit': 1.0, 'unit': 'pc', 'desc': 'Comforter, heavy fleece blanket, duvet'},
    };

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Accept Order', style: TextStyle(fontSize: 17)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Enter the weight, select category, and assign an RFID tag to proceed.'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: categories.entries.map((entry) {
                    return DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text('${entry.key} (≤${entry.value['limit']} ${entry.value['unit']})', style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => selectedCategory = val);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: weightController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Weight',
                    border: OutlineInputBorder(),
                    suffixText: 'kg/pc',
                  ),
                ),
                const SizedBox(height: 16),
                if (availableTags.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.errorRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: AppTheme.errorRed, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No RFID tags available',
                            style: TextStyle(color: AppTheme.errorRed, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: selectedRfidTag,
                    decoration: const InputDecoration(
                      labelText: 'RFID Tag',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.nfc_outlined),
                    ),
                    items: availableTags.map((tag) {
                      return DropdownMenuItem<String>(
                        value: tag,
                        child: Text(tag),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedRfidTag = value);
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: (selectedRfidTag == null || availableTags.isEmpty) ? null : () {
                final weight = double.tryParse(weightController.text) ?? 1.0;
                final categoryData = categories[selectedCategory]!;
                
                // Create single load
                final loads = [
                  OrderLoad(
                    loadNumber: 1,
                    category: selectedCategory,
                    weight: weight,
                    categoryLimit: categoryData['limit'] as double,
                    unit: categoryData['unit'] as String,
                    description: categoryData['desc'] as String,
                    isOverLimit: weight > (categoryData['limit'] as double),
                    loadStatus: LoadStatus.queued,
                  ),
                ];
                
                setState(() {
                  MockDataService().approveRequest(request.id, loads, selectedRfidTag!);
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Order approved! RFID $selectedRfidTag assigned.')),
                );
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  // ========== ACTIVE TAB ==========

  Widget _buildActiveTab() {
    final orders = MockDataService().activeOrders;

    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined, size: 80, color: AppTheme.textLight.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text('No active orders', style: TextStyle(color: AppTheme.textLight)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: orders.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _buildOrderCard(orders[index]),
    );
  }

  Widget _buildOrderCard(LaundryOrder order) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => OrderStatusScreen(order: order)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: AppStyles.cardDecoration,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(order.id, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
                _buildStatusBadge(order.status),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 20, color: AppTheme.textLight),
                const SizedBox(width: 8),
                Expanded(child: Text(order.customerName, style: AppTheme.lightTheme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(order.weightDisplay, style: AppTheme.lightTheme.textTheme.bodyMedium),
                    if (order.hasMultipleLoads) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${order.totalLoads} loads',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
                        ),
                      ),
                    ],
                    if (order.rfidTag != null) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.nfc_outlined, size: 14, color: AppTheme.accentBlue.withValues(alpha: 0.7)),
                      const SizedBox(width: 4),
                      Text(
                        order.rfidTag!,
                        style: const TextStyle(fontSize: 12, color: AppTheme.accentBlue, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ],
                ),
                Text(
                  order.paymentStatus == PaymentStatus.paid ? 'PAID' : 'UNPAID',
                  style: TextStyle(
                    color: order.paymentStatus == PaymentStatus.paid ? Colors.green : AppTheme.errorRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            // Show load statuses for multi-load orders
            if (order.hasMultipleLoads) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.softGray,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: order.loads.map((load) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          children: [
                            Text(
                              load.statusIcon,
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'L${load.loadNumber}',
                              style: const TextStyle(fontSize: 9, color: AppTheme.textLight, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ========== HISTORY TAB ==========

  Widget _buildHistoryTab() {
    // Mock completed orders
    final List<LaundryOrder> history = [
      LaundryOrder(
        id: 'IW-999',
        customerName: 'Jane Smith',
        channel: OrderChannel.walkIn,
        status: OrderStatus.completed,
        paymentStatus: PaymentStatus.paid,
        loads: [
          OrderLoad(
            loadNumber: 1,
            category: 'Regular Clothing',
            weight: 4.0,
            categoryLimit: 8.0,
            unit: 'kg',
            description: 'T-shirts, shorts, sleeveless, socks, underwear',
            isOverLimit: false,
            loadStatus: LoadStatus.folded,
          ),
        ],
        rfidTag: 'RFID-002',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      LaundryOrder(
        id: 'IW-998',
        customerName: 'Bob Brown',
        channel: OrderChannel.online,
        collectionMethod: CollectionMethod.riderPickup,
        returnMethod: ReturnMethod.delivery,
        status: OrderStatus.completed,
        paymentStatus: PaymentStatus.paid,
        loads: [
          OrderLoad(
            loadNumber: 1,
            category: 'Heavy Clothing',
            weight: 7.2,
            categoryLimit: 6.0,
            unit: 'kg',
            description: 'Jeans, cargo, jackets, sweaters, corduroy',
            isOverLimit: true,
            loadStatus: LoadStatus.folded,
          ),
        ],
        rfidTag: 'RFID-004',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    ];

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 80, color: AppTheme.textLight.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text('No completed orders yet', style: TextStyle(color: AppTheme.textLight)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: history.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final order = history[index];
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: AppStyles.cardDecoration,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.green),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.customerName, style: AppTheme.lightTheme.textTheme.titleMedium),
                    Text('Order ${order.id} • ${order.weightDisplay}', style: AppTheme.lightTheme.textTheme.bodyMedium),
                  ],
                ),
              ),
              Text(
                '₱${order.basePrice.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        );
      },
    );
  }

  // ========== SHARED WIDGETS ==========

  Widget _buildStatusBadge(OrderStatus status) {
    Color color;
    switch (status) {
      case OrderStatus.pending_approval: color = Colors.grey; break;
      case OrderStatus.pending_pickup: color = Colors.amber; break;
      case OrderStatus.processing: color = Colors.blue; break;
      case OrderStatus.ready: color = AppTheme.errorRed; break;
      case OrderStatus.out_for_delivery: color = Colors.cyan; break;
      case OrderStatus.completed: color = Colors.green; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }
}
