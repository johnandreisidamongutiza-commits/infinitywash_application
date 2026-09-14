import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import '../../../services/mock_data_service.dart';
import '../route/rider_route_screen.dart';

class RiderOrderDetailsScreen extends StatefulWidget {
  final LaundryOrder order;
  final bool isPickup;

  const RiderOrderDetailsScreen({
    super.key,
    required this.order,
    required this.isPickup,
  });

  @override
  State<RiderOrderDetailsScreen> createState() => _RiderOrderDetailsScreenState();
}

class _RiderOrderDetailsScreenState extends State<RiderOrderDetailsScreen> {
  final List<String> _scannedTags = [];
  final TextEditingController _tagController = TextEditingController();
  bool _isScanning = false;

  bool get _hasTBDLoads => widget.order.loads.isEmpty;

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('=== RiderOrderDetailsScreen build called ===');
    print('Order ID: ${widget.order.id}');
    print('Customer: ${widget.order.customerName}');
    print('Has TBD Loads: $_hasTBDLoads');
    print('Loads count: ${widget.order.loads.length}');
    print('Delivery address: ${widget.order.deliveryAddress}');
    print('Customer phone: ${widget.order.customerPhone}');
    
    // Ensure we have valid data
    if (widget.order.customerName.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order Details')),
        body: const Center(
          child: Text('Error: Invalid order data'),
        ),
      );
    }
    
    // Use actual order data
    String orderNumber = widget.order.id;
    String customerName = widget.order.customerName;
    String address = widget.order.deliveryAddress ?? 'No address provided';
    String phoneNumber = widget.order.customerPhone ?? 'No phone';
    String rfidTag = widget.order.rfidTag ?? 'Not assigned';
    String serviceType = '${widget.order.collectionText} → ${widget.order.returnText}';
    String weight = _hasTBDLoads ? 'To be determined at pickup' : widget.order.weightDisplay;
    String instructions = widget.order.instructions ?? widget.order.customerDescription ?? 'No special instructions';
    String total = _hasTBDLoads 
        ? '₱TBD - Determined by load count' 
        : '₱${widget.order.basePrice.toStringAsFixed(0)}';
    String date = '${widget.order.createdAt.month}/${widget.order.createdAt.day}/${widget.order.createdAt.year}';

    print('Building UI with orderNumber: $orderNumber, customer: $customerName');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Order Details'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: widget.order.customerName.isEmpty 
          ? const Center(child: Text('Error: Invalid order data'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Card - Order Number and Type
                  _buildHeaderCard(orderNumber, date),
                  const SizedBox(height: 24),

                  // Customer Information Section
                  Text('Customer Information', style: AppTheme.lightTheme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _buildCustomerInfoCard(customerName, address, phoneNumber, rfidTag),
                  const SizedBox(height: 24),

                  // Order Details Section
                  Text('Order Details', style: AppTheme.lightTheme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _buildOrderDetailsCard(serviceType, weight, instructions, total),
                  const SizedBox(height: 24),

                  // RFID Scanning Section (only for TBD loads)
                  if (_hasTBDLoads && widget.isPickup) ...[
                    _buildRfidScanningSection(),
                    const SizedBox(height: 24),
                  ],

                  // Order Status Section
                  if (!_isScanning) ...[
                    Text('Order Status', style: AppTheme.lightTheme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    _buildOrderStatusCard(),
                    const SizedBox(height: 32),
                  ],

                  // Action Buttons
                  if (!_isScanning) ...[
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const RiderRouteScreen()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 56),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.navigation),
                          SizedBox(width: 8),
                          Text('Navigate to Location'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () {
                        _showContactOptions(context, phoneNumber, customerName, orderNumber);
                      },
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 56),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phone),
                          SizedBox(width: 8),
                          Text('Contact Customer'),
                        ],
                      ),
                    ),
                    if (_hasTBDLoads && widget.isPickup) ...[
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isScanning = true;
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentBlue,
                          minimumSize: const Size(double.infinity, 56),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.qr_code_scanner),
                            SizedBox(width: 8),
                            Text('Scan RFID Tags & Confirm Pickup'),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderCard(String orderNumber, String date) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Order $orderNumber',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppTheme.accentBlue,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                date,
                style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: widget.isPickup ? AppTheme.errorRed.withValues(alpha: 0.1) : AppTheme.teamMemberIconOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.isPickup ? 'PICKUP' : 'DELIVERY',
              style: TextStyle(
                color: widget.isPickup ? AppTheme.errorRed : AppTheme.teamMemberIconOrange,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRfidScanningSection() {
    int loadCount = _scannedTags.length;
    double totalAmount = loadCount * 170.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration.copyWith(
        border: Border.all(color: AppTheme.accentBlue, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_scanner, color: AppTheme.accentBlue, size: 24),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Scan RFID Tags',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                ),
              ),
              if (_isScanning)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isScanning = false;
                      _scannedTags.clear();
                      _tagController.clear();
                    });
                  },
                  child: const Text('Cancel'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Scan each bag/load\'s RFID tag:',
            style: TextStyle(fontSize: 13, color: AppTheme.textLight),
          ),
          const SizedBox(height: 12),
          
          // Tag input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tagController,
                  decoration: InputDecoration(
                    hintText: 'Enter or scan RFID tag',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: _addTag,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _addTag(_tagController.text),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Icon(Icons.add),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Scanned tags list
          if (_scannedTags.isNotEmpty) ...[
            const Text(
              'Scanned Tags:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark),
            ),
            const SizedBox(height: 8),
            ...(_scannedTags.asMap().entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.softGray,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${entry.key + 1}',
                            style: const TextStyle(
                              color: AppTheme.accentBlue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          setState(() {
                            _scannedTags.removeAt(entry.key);
                          });
                        },
                      ),
                    ],
                  ),
                ),
              );
            })),
            const SizedBox(height: 16),
            
            // Summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.accentBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.accentBlue),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Loads:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      Text(
                        '$loadCount load${loadCount > 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Amount:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      Text(
                        '₱${totalAmount.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Warning for minimum loads
            if (loadCount < 2)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        loadCount == 0
                            ? 'Please scan at least 2 RFID tags (minimum 2 loads required)'
                            : 'Only 1 load scanned. Minimum 2 loads required. Continue anyway?',
                        style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 16),
            
            // Confirm button
            ElevatedButton(
              onPressed: loadCount > 0 ? _confirmPickup : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size(double.infinity, 56),
                disabledBackgroundColor: AppTheme.borderGray,
              ),
              child: Text(
                loadCount < 2 ? 'Confirm Pickup (Charge 2-load minimum)' : 'Confirm Pickup',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _addTag(String tag) {
    final trimmedTag = tag.trim().toUpperCase();
    if (trimmedTag.isEmpty) return;

    // Validate tag availability
    if (!MockDataService().isRfidAvailable(trimmedTag)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tag $trimmedTag is already in use or invalid'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check for duplicates
    if (_scannedTags.contains(trimmedTag)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tag already scanned'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _scannedTags.add(trimmedTag);
      _tagController.clear();
    });
  }

  void _confirmPickup() {
    if (_scannedTags.isEmpty) return;

    // Enforce 2-load minimum
    final actualLoadCount = _scannedTags.length < 2 ? 2 : _scannedTags.length;
    
    // Create OrderLoad objects
    final loads = List.generate(
      actualLoadCount,
      (index) => OrderLoad(
        loadNumber: index + 1,
        category: 'Regular Clothing',
        weight: 8.0,
        categoryLimit: 8.0,
        unit: 'kg',
        description: index < _scannedTags.length ? 'Tag: ${_scannedTags[index]}' : 'Additional minimum load',
        isOverLimit: false,
        loadStatus: LoadStatus.queued,
      ),
    );

    // Confirm pickup with loads
    MockDataService().confirmPickupWithLoads(widget.order.id, loads);

    // Show success and go back
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Pickup confirmed! $actualLoadCount loads (₱${actualLoadCount * 170})'),
        backgroundColor: Colors.green,
      ),
    );

    Navigator.pop(context);
  }

  Widget _buildCustomerInfoCard(String name, String address, String phone, String rfid) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        children: [
          _buildInfoRow(Icons.person_outline, name),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.location_on_outlined, address),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.phone_outlined, phone),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.style_outlined, 'RFID: $rfid'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppTheme.accentBlue),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, color: AppTheme.textDark),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderDetailsCard(String serviceType, String weight, String instructions, String total) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        children: [
          _buildDetailRow('Service Type', serviceType),
          const Divider(height: 24),
          _buildDetailRow('Weight', weight),
          const Divider(height: 24),
          _buildDetailRow('Instructions', instructions),
          const Divider(height: 24),
          _buildDetailRow('Estimated Total', total, isTotal: true),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textLight,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textDark,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        children: [
          _buildStatusStep(
            widget.isPickup ? 'Pending Pickup' : 'Pending Delivery',
            Icons.pending,
            true,
            isLast: false,
          ),
          _buildConnector(true),
          _buildStatusStep(
            'In Transit',
            Icons.local_shipping_outlined,
            false,
            isLast: false,
          ),
          _buildConnector(false),
          _buildStatusStep(
            widget.isPickup ? 'Picked Up' : 'Delivered',
            Icons.check_circle_outline,
            false,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusStep(String label, IconData icon, bool isActive, {required bool isLast}) {
    Color color = isActive ? AppTheme.accentBlue : AppTheme.textLight.withValues(alpha: 0.3);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? AppTheme.textDark : AppTheme.textLight,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
        if (isActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.accentBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Current',
              style: TextStyle(
                color: AppTheme.accentBlue,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildConnector(bool isActive) {
    return Container(
      margin: const EdgeInsets.only(left: 19, top: 4, bottom: 4),
      height: 24,
      width: 2,
      color: isActive ? AppTheme.accentBlue : AppTheme.borderGray,
    );
  }

  void _showContactOptions(BuildContext context, String phoneNumber, String customerName, String orderNumber) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.borderGray,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Contact Customer',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.phone, color: AppTheme.accentBlue),
              title: const Text('Call Customer'),
              subtitle: Text(phoneNumber),
              onTap: () {
                Navigator.pop(context);
                // In production, implement actual phone call
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Calling $phoneNumber...')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.message, color: AppTheme.accentBlue),
              title: const Text('Send Message'),
              subtitle: const Text('Send SMS or in-app message'),
              onTap: () {
                Navigator.pop(context);
                // In production, implement messaging
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Opening messenger...')),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
