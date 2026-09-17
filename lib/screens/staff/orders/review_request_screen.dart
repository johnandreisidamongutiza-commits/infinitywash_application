import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import '../../../services/service_request_service.dart';
import '../../../services/supabase_service.dart';

class ReviewRequestScreen extends StatefulWidget {
  final LaundryOrder request;

  const ReviewRequestScreen({super.key, required this.request});

  @override
  State<ReviewRequestScreen> createState() => _ReviewRequestScreenState();
}

class _ReviewRequestScreenState extends State<ReviewRequestScreen> {
  late LaundryOrder _request;
  final ServiceRequestService _serviceRequestService = ServiceRequestService();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _request = widget.request;
    _fetchFreshRequest();
  }

  Future<void> _fetchFreshRequest() async {
    try {
      final response = await SupabaseService.client
          .from('orders')
          .select('''
            *,
            customers!inner(first_name, last_name, phone, address, landmark)
          ''')
          .eq('id', widget.request.id)
          .maybeSingle();

      if (response != null && mounted) {
        final freshOrder = LaundryOrder.fromJson(response);
        final customer = response['customers'] as Map<String, dynamic>?;
        final firstName = customer?['first_name'] as String? ?? '';
        final lastName = customer?['last_name'] as String? ?? '';
        final customerName = lastName.isNotEmpty
            ? '$firstName $lastName'
            : (firstName.isNotEmpty ? firstName : freshOrder.customerName);
        final customerPhone = customer?['phone'] as String? ?? freshOrder.customerPhone;

        setState(() {
          _request = LaundryOrder(
            id: freshOrder.id,
            orderNumber: freshOrder.orderNumber,
            customerName: customerName,
            customerPhone: customerPhone,
            deliveryAddress: freshOrder.deliveryAddress ?? customer?['address'] as String?,
            deliveryLandmark: freshOrder.deliveryLandmark ?? customer?['landmark'] as String?,
            channel: freshOrder.channel,
            collectionMethod: freshOrder.collectionMethod,
            returnMethod: freshOrder.returnMethod,
            status: freshOrder.status,
            paymentStatus: freshOrder.paymentStatus,
            loads: freshOrder.loads,
            instructions: freshOrder.instructions,
            rfidTag: freshOrder.rfidTag,
            createdAt: freshOrder.createdAt,
            paymentMethod: freshOrder.paymentMethod,
            paidAt: freshOrder.paidAt,
            laundryPhotoUrls: freshOrder.laundryPhotoUrls,
            customerDescription: freshOrder.customerDescription,
            estimatedLoads: freshOrder.estimatedLoads,
            rejectionReason: freshOrder.rejectionReason,
            staffMessage: freshOrder.staffMessage,
            reviewedAt: freshOrder.reviewedAt,
            reviewedBy: freshOrder.reviewedBy,
            expiresAt: freshOrder.expiresAt,
            underReviewBy: freshOrder.underReviewBy,
          );
        });
        print('✅ Fresh request loaded with ${_request.laundryPhotoUrls?.length ?? 0} photos');
      }
    } catch (e) {
      print('⚠️ Error loading fresh request: $e');
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final isToday = dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day;

    final hour = dateTime.hour > 12
        ? dateTime.hour - 12
        : (dateTime.hour == 0 ? 12 : dateTime.hour);
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour:${dateTime.minute.toString().padLeft(2, '0')} $period';

    if (isToday) {
      return 'Today at $timeStr';
    }

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year} at $timeStr';
  }

  String? _getExpiryCountdown() {
    if (_request.expiresAt == null) return null;
    final now = DateTime.now();
    final difference = _request.expiresAt!.difference(now);

    if (difference.isNegative) {
      return 'Expired';
    }

    final hours = difference.inHours;
    final minutes = difference.inMinutes % 60;

    if (hours > 0) {
      return 'Expires in ${hours}h ${minutes}m';
    } else {
      return 'Expires in ${minutes}m';
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openPhotoViewer(int initialIndex) {
    final photos = _request.laundryPhotoUrls ?? [];
    if (photos.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _FullScreenImageViewer(
          photoUrls: photos,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  Future<void> _handleAccept() async {
    final isRiderPickup = _request.collectionMethod == CollectionMethod.riderPickup;
    final staffMessageController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline, color: Colors.green, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Accept Request?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This request will be marked as "Processing" and added to your active orders.',
                style: TextStyle(fontSize: 13, color: AppTheme.textDark),
              ),
              const SizedBox(height: 16),
              const Text(
                'Message to Customer (Optional)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: staffMessageController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'e.g., We have approved your pickup request.',
                  hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                  filled: true,
                  fillColor: AppTheme.softGray,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textLight)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm Accept', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isProcessing = true);
      try {
        await _serviceRequestService.approveServiceRequest(
          orderId: _request.id,
          isRiderPickup: isRiderPickup,
          staffMessage: staffMessageController.text.trim(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Request accepted! Order moved to processing.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to accept request: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _handleDecline() async {
    String selectedReason = 'out_of_service_area';
    final reasons = [
      {'id': 'out_of_service_area', 'label': 'Out of service area'},
      {'id': 'capacity_full', 'label': 'Shop is at full capacity'},
      {'id': 'invalid_items', 'label': 'Unsupported or invalid items'},
      {'id': 'unreachable', 'label': 'Customer unreachable / invalid info'},
      {'id': 'other', 'label': 'Other reason'},
    ];
    final messageController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cancel_outlined, color: Colors.red, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Decline Request', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please select a reason for declining this request:',
                  style: TextStyle(fontSize: 13, color: AppTheme.textDark),
                ),
                const SizedBox(height: 12),
                ...reasons.map((r) {
                  return RadioListTile<String>(
                    value: r['id']!,
                    groupValue: selectedReason,
                    title: Text(r['label']!, style: const TextStyle(fontSize: 13)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: Colors.red,
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedReason = val);
                      }
                    },
                  );
                }),
                const SizedBox(height: 8),
                const Text(
                  'Explanation for Customer',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: messageController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Provide additional context to the customer...',
                    hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                    filled: true,
                    fillColor: AppTheme.softGray,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textLight)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Decline Request', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isProcessing = true);
      try {
        await _serviceRequestService.rejectServiceRequest(
          orderId: _request.id,
          reason: selectedReason,
          staffMessage: messageController.text.trim(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Request declined.'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to decline request: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderDisplayId = _request.orderNumber ?? _request.id;
    final expiryText = _getExpiryCountdown();
    final isExpired = expiryText == 'Expired';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('Review Request', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isProcessing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Updating request status...', style: TextStyle(color: AppTheme.textLight)),
                ],
              ),
            )
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeaderCard(orderDisplayId, expiryText, isExpired),
                      const SizedBox(height: 16),
                      _buildCustomerCard(),
                      const SizedBox(height: 16),
                      _buildLogisticsCard(),
                      const SizedBox(height: 16),
                      _buildLaundryDetailsCard(),
                      const SizedBox(height: 16),
                      _buildPhotosCard(),
                    ],
                  ),
                ),
                _buildBottomActionBar(),
              ],
            ),
    );
  }

  Widget _buildHeaderCard(String orderDisplayId, String? expiryText, bool isExpired) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        orderDisplayId,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentBlue,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.copy_outlined, size: 16, color: AppTheme.textLight),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Copy Request ID',
                      onPressed: () => _copyToClipboard(orderDisplayId, 'Request ID'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'PENDING REVIEW',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.access_time, size: 14, color: AppTheme.textLight),
              const SizedBox(width: 6),
              Text(
                'Submitted: ${_formatDateTime(_request.createdAt)}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
              ),
            ],
          ),
          if (expiryText != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isExpired
                    ? Colors.red.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isExpired ? Icons.error_outline : Icons.timer_outlined,
                    size: 14,
                    color: isExpired ? Colors.red : Colors.orange.shade800,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    expiryText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isExpired ? Colors.red : Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCustomerCard() {
    final customerName = _request.customerName;
    final phone = _request.customerPhone;
    final address = _request.deliveryAddress;
    final landmark = _request.deliveryLandmark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_outline, color: AppTheme.accentBlue, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'Customer Information',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            customerName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textDark),
          ),
          if (phone != null && phone.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.phone_outlined, size: 16, color: AppTheme.textLight),
                const SizedBox(width: 8),
                Text(
                  phone,
                  style: const TextStyle(fontSize: 13, color: AppTheme.textDark, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _copyToClipboard(phone, 'Phone number'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.softGray,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Copy', style: TextStyle(fontSize: 10, color: AppTheme.accentBlue, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
          if (address != null && address.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.textLight),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        address,
                        style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
                      ),
                      if (landmark != null && landmark.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.flag_outlined, size: 12, color: AppTheme.accentBlue),
                            const SizedBox(width: 4),
                            Text(
                              'Landmark: $landmark',
                              style: const TextStyle(fontSize: 11, color: AppTheme.accentBlue, fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLogisticsCard() {
    final isRiderPickup = _request.collectionMethod == CollectionMethod.riderPickup;
    final isDelivery = _request.returnMethod == ReturnMethod.delivery;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.local_shipping_outlined, color: Colors.purple, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'Service & Logistics',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildLogisticRow(
            icon: isRiderPickup ? Icons.two_wheeler : Icons.storefront_outlined,
            title: 'Collection Method',
            badgeText: _request.collectionText,
            badgeColor: isRiderPickup ? AppTheme.accentBlue : Colors.teal,
            subtitle: isRiderPickup
                ? 'Rider will collect laundry from customer'
                : 'Customer will drop off laundry at the shop',
          ),
          const Divider(height: 20),
          _buildLogisticRow(
            icon: isDelivery ? Icons.delivery_dining : Icons.shopping_bag_outlined,
            title: 'Return Method',
            badgeText: _request.returnText,
            badgeColor: isDelivery ? Colors.green : Colors.indigo,
            subtitle: isDelivery
                ? 'Rider will deliver clean laundry to customer'
                : 'Customer will pick up clean laundry at the shop',
          ),
        ],
      ),
    );
  }

  Widget _buildLogisticRow({
    required IconData icon,
    required String title,
    required String badgeText,
    required Color badgeColor,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: badgeColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeText.toUpperCase(),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLaundryDetailsCard() {
    final description = _request.customerDescription;
    final instructions = _request.instructions;

    final hasDescription = description != null && description.trim().isNotEmpty;
    final hasInstructions = instructions != null && instructions.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.dry_cleaning_outlined, color: Colors.teal, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'Laundry Details & Notes',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Customer Description of Items',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textLight),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.softGray,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              hasDescription ? description : 'No specific item description provided.',
              style: TextStyle(
                fontSize: 13,
                color: hasDescription ? AppTheme.textDark : AppTheme.textLight,
                fontStyle: hasDescription ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ),
          if (hasInstructions) ...[
            const SizedBox(height: 12),
            const Text(
              'Special Instructions / Address Note',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textLight),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Text(
                instructions,
                style: const TextStyle(fontSize: 12, color: AppTheme.textDark),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhotosCard() {
    final photos = _request.laundryPhotoUrls ?? [];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
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
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accentBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.photo_library_outlined, color: AppTheme.accentBlue, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Attached Photos',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  ),
                ],
              ),
              if (photos.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${photos.length} photo${photos.length > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accentBlue,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (photos.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Icon(Icons.photo_outlined, size: 36, color: AppTheme.textLight),
                  SizedBox(height: 8),
                  Text('No photos attached to this request', style: TextStyle(color: AppTheme.textLight, fontSize: 12)),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tap any photo to view full size and zoom in:',
                  style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                ),
                const SizedBox(height: 10),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1,
                  ),
                  itemCount: photos.length,
                  itemBuilder: (context, index) {
                    final photoPath = photos[index];
                    return GestureDetector(
                      onTap: () => _openPhotoViewer(index),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildThumbnailImage(photoPath),
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.zoom_in, color: Colors.white, size: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  bool _isBase64Image(String path) {
    return path.startsWith('data:image') ||
        (path.length > 100 && !path.startsWith('/') && !path.contains('\\') && !path.startsWith('http'));
  }

  Widget _buildThumbnailImage(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPhotoPlaceholder(path),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: AppTheme.softGray,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
      );
    } else if (_isBase64Image(path)) {
      try {
        final base64String = path.contains(',') ? path.split(',').last : path;
        final bytes = base64Decode(base64String.trim());
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildPhotoPlaceholder(path),
        );
      } catch (e) {
        return _buildPhotoPlaceholder(path);
      }
    } else {
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildPhotoPlaceholder(path),
        );
      } else {
        return _buildPhotoPlaceholder(path);
      }
    }
  }

  Widget _buildPhotoPlaceholder([String? path]) {
    final fileName = path != null ? path.split(RegExp(r'[/\\]')).last : '';
    return Container(
      color: AppTheme.softGray,
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo, color: AppTheme.accentBlue, size: 26),
          const SizedBox(height: 4),
          Text(
            fileName.isNotEmpty ? fileName : 'Photo',
            style: const TextStyle(fontSize: 9, color: AppTheme.textDark, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          const Text('Tap to view', style: TextStyle(fontSize: 8, color: AppTheme.textLight)),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              flex: 1,
              child: OutlinedButton(
                onPressed: _handleDecline,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Decline',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _handleAccept,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Accept Request',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full screen interactive image viewer
class _FullScreenImageViewer extends StatefulWidget {
  final List<String> photoUrls;
  final int initialIndex;

  const _FullScreenImageViewer({
    required this.photoUrls,
    required this.initialIndex,
  });

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image, color: Colors.white54, size: 48),
                SizedBox(height: 8),
                Text('File not accessible', style: TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        );
      } else {
        final fileName = path.split(RegExp(r'[/\\]')).last;
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.phone_android, color: Colors.white70, size: 56),
                const SizedBox(height: 16),
                Text(
                  'Photo attached from customer device:\n$fileName',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Local path: $path',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Note: Because this was captured as a local cache file on the customer\'s mobile device, it is directly viewable on that device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      }
    }
  }
}
