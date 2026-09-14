import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import '../../../services/mock_data_service.dart';
import 'order_status_screen.dart';
import 'create_order_flow.dart';

class RfidCheckerScreen extends StatefulWidget {
  final String? initialTag;
  const RfidCheckerScreen({super.key, this.initialTag});

  @override
  State<RfidCheckerScreen> createState() => _RfidCheckerScreenState();
}

class _RfidCheckerScreenState extends State<RfidCheckerScreen> {
  final TextEditingController _manualTagController = TextEditingController();

  String? _scannedTag;
  LaundryOrder? _matchedOrder;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialTag != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scanTag(widget.initialTag!);
        }
      });
    }
  }

  @override
  void dispose() {
    _manualTagController.dispose();
    super.dispose();
  }

  void _scanTag(String tag) {
    final cleanTag = tag.trim().toUpperCase();
    if (cleanTag.isEmpty) return;

    setState(() {
      _isSearching = true;
      _scannedTag = cleanTag;
    });

    // Simulate instant NFC reader detection
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;

      final allOrders = [
        ...MockDataService().activeOrders,
        ...MockDataService().completedOrders,
      ];

      LaundryOrder? found;
      for (final order in allOrders) {
        if (order.rfidTag != null && order.rfidTag!.toUpperCase() == cleanTag) {
          found = order;
          break;
        }
      }

      setState(() {
        _isSearching = false;
        _matchedOrder = found;
      });

      _manualTagController.clear();
    });
  }

  void _resetScanner() {
    setState(() {
      _scannedTag = null;
      _matchedOrder = null;
      _isSearching = false;
      _manualTagController.clear();
    });
  }

  Color _getLoadStatusColor(LoadStatus status) {
    switch (status) {
      case LoadStatus.queued:
        return Colors.grey;
      case LoadStatus.washing:
        return AppTheme.accentBlue;
      case LoadStatus.drying:
        return Colors.orange;
      case LoadStatus.folded:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableTags = MockDataService().availableRfidTags;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('RFID Tag Checker'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.accentBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.nfc, size: 14, color: AppTheme.accentBlue),
                const SizedBox(width: 4),
                Text(
                  '${availableTags.length} Free Tags',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Scanner Hero Panel (Reader Status & Manual Field)
              _buildScannerHero(),
              const SizedBox(height: 20),

              // 2. Interactive Mock Scenarios
              _buildMockScenariosSection(availableTags),
              const SizedBox(height: 24),

              // 3. Scan Results View (Matched Order, Available Tag, or Unrecognized)
              if (_isSearching)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_scannedTag != null)
                _buildScanResultView(availableTags)
              else
                _buildIdleGuide(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScannerHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accentBlue.withValues(alpha: 0.08),
            AppTheme.lightBlue.withValues(alpha: 0.28),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isSearching ? Colors.orange : AppTheme.accentBlue.withValues(alpha: 0.3),
          width: _isSearching ? 2.0 : 1.0,
        ),
      ),
      child: Column(
        children: [
          // Live Reader Status LED Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: _isSearching
                  ? Colors.orange.withValues(alpha: 0.12)
                  : const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isSearching ? Colors.orange : Colors.green.shade400,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isSearching ? Colors.orange : Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _isSearching
                        ? 'READING RFID SIGNAL...'
                        : 'READER ACTIVE • WAITING FOR SCAN',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _isSearching ? Colors.orange.shade900 : Colors.green.shade900,
                      letterSpacing: 0.6,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Layered Concentric Radar Graphic
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isSearching
                      ? Colors.orange.withValues(alpha: 0.15)
                      : AppTheme.accentBlue.withValues(alpha: 0.12),
                ),
              ),
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _isSearching
                          ? Colors.orange.withValues(alpha: 0.35)
                          : AppTheme.accentBlue.withValues(alpha: 0.25),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.nfc,
                  size: 38,
                  color: _isSearching ? Colors.orange : AppTheme.accentBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Status Title & Subtitle
          Text(
            _isSearching
                ? 'Scanning RFID Tag: $_scannedTag'
                : 'Waiting for RFID Card or Fob',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            _isSearching
                ? 'Connecting to database and fetching customer details...'
                : 'Hold tag against counter reader, or tap a mock scenario below',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
          ),
          const SizedBox(height: 16),

          // Manual scan / USB barcode reader input
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.borderGray),
                  ),
                  child: TextField(
                    controller: _manualTagController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      hintText: 'Enter Tag ID (e.g. RFID-001)...',
                      hintStyle: TextStyle(fontSize: 12, color: AppTheme.textLight),
                      prefixIcon: Icon(Icons.qr_code_scanner, size: 18, color: AppTheme.textLight),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                    ),
                    onSubmitted: _scanTag,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _scanTag(_manualTagController.text),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Check',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMockScenariosSection(List<String> availableTags) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.science_outlined, size: 16, color: AppTheme.accentBlue),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Mock Counter Scenarios (Hardware Simulator):',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Tap any realistic scenario below to simulate tapping an RFID tag:',
          style: TextStyle(fontSize: 11, color: AppTheme.textLight),
        ),
        const SizedBox(height: 10),

        // Scenario 1: Customer Pickup (Carlos Reyes)
        _buildScenarioCard(
          tag: 'RFID-005',
          title: 'Scenario 1: Customer Claiming Clean Laundry',
          customer: 'Carlos Reyes • 4.0 kg • Paid',
          badgeText: 'Claim Ready',
          badgeColor: Colors.green,
          icon: Icons.check_circle_outline,
          description: 'Simulate customer presenting their bag tag at counter to claim finished order.',
        ),
        const SizedBox(height: 8),

        // Scenario 2: Active Wash Status (John Doe)
        _buildScenarioCard(
          tag: 'RFID-001',
          title: 'Scenario 2: Customer Status Inquiry',
          customer: 'John Doe • 5.5 kg • Unpaid',
          badgeText: 'Processing',
          badgeColor: AppTheme.accentBlue,
          icon: Icons.local_laundry_service,
          description: 'Simulate checking progress for an ongoing wash cycle.',
        ),
        const SizedBox(height: 8),

        // Scenario 3: Rider Delivery with Landmark (Maria Santos)
        _buildScenarioCard(
          tag: 'RFID-003',
          title: 'Scenario 3: Rider Dispatch (Delivery & Landmark)',
          customer: 'Maria Santos • 456 Banilad Rd (Beside green pharmacy)',
          badgeText: 'Delivery Order',
          badgeColor: Colors.orange,
          icon: Icons.delivery_dining,
          description: 'Simulate checking delivery address & landmark notes before handing to rider.',
        ),
        const SizedBox(height: 8),

        // Scenario 4: Fresh Free Tag
        _buildScenarioCard(
          tag: availableTags.isNotEmpty ? availableTags.first : 'RFID-002',
          title: 'Scenario 4: Fresh Unassigned Counter Tag',
          customer: 'Free Tag in Inventory • Ready for New Laundry',
          badgeText: 'Available',
          badgeColor: Colors.teal,
          icon: Icons.add_shopping_cart,
          description: 'Simulate picking up an unassigned tag to attach to a new walk-in order.',
        ),
        const SizedBox(height: 8),

        // Scenario 5: Unrecognized / Unknown Tag
        _buildScenarioCard(
          tag: 'RFID-999',
          title: 'Scenario 5: Unknown / Foreign RFID Tag',
          customer: 'Tag not registered in database',
          badgeText: 'Unrecognized',
          badgeColor: Colors.red,
          icon: Icons.warning_amber_rounded,
          description: 'Simulate scanning an unprogrammed or foreign tag to test error handling.',
        ),
      ],
    );
  }

  Widget _buildScenarioCard({
    required String tag,
    required String title,
    required String customer,
    required String badgeText,
    required Color badgeColor,
    required IconData icon,
    required String description,
  }) {
    final isSelected = _scannedTag == tag;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _scanTag(tag),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? badgeColor.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? badgeColor : AppTheme.borderGray.withValues(alpha: 0.8),
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: badgeColor.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: badgeColor, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        customer,
                        style: TextStyle(fontSize: 11, color: badgeColor, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.touch_app, size: 10),
                      const SizedBox(width: 3),
                      Text(
                        tag,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: badgeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanResultView(List<String> availableTags) {
    if (_matchedOrder != null) {
      return _buildAssignedOrderCard(_matchedOrder!);
    } else if (availableTags.contains(_scannedTag)) {
      return _buildAvailableTagCard(_scannedTag!);
    } else {
      return _buildUnrecognizedTagCard(_scannedTag!);
    }
  }

  Widget _buildAssignedOrderCard(LaundryOrder order) {
    Color statusColor = AppTheme.accentBlue;
    if (order.status == OrderStatus.ready) statusColor = Colors.green;
    if (order.status == OrderStatus.completed) statusColor = Colors.grey;

    final bool isDelivery = order.returnMethod == ReturnMethod.delivery;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentBlue.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Tag & Order Status
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accentBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.nfc, color: AppTheme.accentBlue, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        order.rfidTag ?? 'RFID Tag',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
                      ),
                      Text(
                        'Order ${order.id}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textLight, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  order.statusText.toUpperCase(),
                  style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),

          const Divider(height: 24),

          // 1. Customer Details
          const Text('Customer Details', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLight)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.softGray,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.accentBlue.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person, color: AppTheme.accentBlue, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.customerName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (order.customerPhone != null && order.customerPhone!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.phone_outlined, size: 12, color: AppTheme.accentBlue),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    order.customerPhone!,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      order.channel == OrderChannel.walkIn ? Icons.storefront_outlined : Icons.smartphone_outlined,
                      size: 13,
                      color: AppTheme.textLight,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        order.channel == OrderChannel.walkIn ? 'Walk-in Counter Order' : 'Online Request',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 2. Laundry Specs & Instructions
          const Text('Laundry Specs', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLight)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.softGray,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Total Weight:', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
                    ),
                    Text(order.weightDisplay, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                  ],
                ),
                if (order.hasMultipleLoads) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Multiple Loads:', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${order.totalLoads} loads', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.accentBlue)),
                      ),
                    ],
                  ),
                ],
                if (order.instructions != null && order.instructions!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Notes: ', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
                      Expanded(
                        child: Text(
                          order.instructions!,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Load Breakdown (if multiple loads)
          if (order.hasMultipleLoads) ...[
            const Text('Load Breakdown', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLight)),
            const SizedBox(height: 6),
            ...order.loads.asMap().entries.map((entry) {
              final load = entry.value;
              final loadIndex = entry.key;
              return Container(
                margin: EdgeInsets.only(bottom: loadIndex < order.loads.length - 1 ? 8 : 0),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _getLoadStatusColor(load.loadStatus).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          load.statusIcon,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Load ${load.loadNumber}: ${load.category}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                '${load.weight.toStringAsFixed(1)} ${load.unit}',
                                style: TextStyle(fontSize: 11, color: load.isOverLimit ? Colors.orange : AppTheme.textLight),
                              ),
                              const SizedBox(width: 4),
                              const Text('•', style: TextStyle(fontSize: 11, color: AppTheme.textLight)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  load.statusText,
                                  style: TextStyle(fontSize: 11, color: _getLoadStatusColor(load.loadStatus), fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (load.notes != null && load.notes!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              load.notes!,
                              style: const TextStyle(fontSize: 10, color: AppTheme.textLight, fontStyle: FontStyle.italic),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
          ],

          // 3. Fulfillment & Payment
          const Text('Fulfillment & Payment', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLight)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.softGray,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Return Mode', style: TextStyle(fontSize: 11, color: AppTheme.textLight)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(isDelivery ? Icons.delivery_dining : Icons.storefront, size: 15, color: AppTheme.accentBlue),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  order.returnText,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Payment Status', style: TextStyle(fontSize: 11, color: AppTheme.textLight)),
                          const SizedBox(height: 2),
                          Text(
                            order.paymentStatus == PaymentStatus.paid ? 'PAID ✓' : 'UNPAID (Claim)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: order.paymentStatus == PaymentStatus.paid ? Colors.green : Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (isDelivery && ((order.deliveryAddress != null && order.deliveryAddress!.isNotEmpty) || (order.deliveryLandmark != null && order.deliveryLandmark!.isNotEmpty))) ...[
                  const Divider(height: 16),
                  if (order.deliveryAddress != null && order.deliveryAddress!.isNotEmpty) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.accentBlue),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            order.deliveryAddress!,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (order.deliveryLandmark != null && order.deliveryLandmark!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.flag_outlined, size: 14, color: Colors.orange),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Landmark: ${order.deliveryLandmark!}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Primary Actions
          Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: _resetScanner,
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('Scan Next', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => OrderStatusScreen(order: order)),
                    );
                  },
                  icon: const Icon(Icons.launch, size: 14),
                  label: const Text('View Order', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), overflow: TextOverflow.ellipsis),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    backgroundColor: AppTheme.accentBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvailableTagCard(String tag) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.green.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline, color: Colors.green, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tag,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
                    ),
                    const Text(
                      'Tag Available & Ready for Use',
                      style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'This RFID tag is currently unassigned and ready to be attached to a new walk-in or online laundry load.',
            style: TextStyle(fontSize: 12, color: AppTheme.textLight),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: _resetScanner,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Scan Another', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CreateOrderFlow()),
                    );
                  },
                  icon: const Icon(Icons.add_shopping_cart, size: 14),
                  label: const Text('Create Order', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), overflow: TextOverflow.ellipsis),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUnrecognizedTagCard(String tag) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tag,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
                    ),
                    const Text(
                      'Unrecognized Tag Code',
                      style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'This tag is not registered in the laundry shop RFID database. Please verify the tag ID or try scanning again.',
            style: TextStyle(fontSize: 12, color: AppTheme.textLight),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _resetScanner,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleGuide() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.softGray,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: AppTheme.textLight),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tip: You can use any USB RFID reader plugged into the counter or tap a test tag above to simulate a scan.',
              style: TextStyle(fontSize: 11, color: AppTheme.textLight),
            ),
          ),
        ],
      ),
    );
  }
}
