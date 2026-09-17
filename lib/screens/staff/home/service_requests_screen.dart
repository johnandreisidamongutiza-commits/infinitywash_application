import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import '../../../services/service_request_service.dart';

class ServiceRequestsScreen extends StatefulWidget {
  const ServiceRequestsScreen({super.key});

  @override
  State<ServiceRequestsScreen> createState() => _ServiceRequestsScreenState();
}

class _ServiceRequestsScreenState extends State<ServiceRequestsScreen> {
  final ServiceRequestService _serviceRequestService = ServiceRequestService();
  List<LaundryOrder> _requests = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPendingRequests();
  }

  Future<void> _loadPendingRequests() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final requests = await _serviceRequestService.getPendingServiceRequests();
      
      if (mounted) {
        setState(() {
          _requests = requests;
          _isLoading = false;
        });
      }
      
      print('✅ Loaded ${requests.length} pending service requests');
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
      
      print('❌ Error loading pending requests: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Online Requests'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : _requests.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _loadPendingRequests,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(24),
                        itemCount: _requests.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 16),
                        itemBuilder: (context, index) => _buildRequestCard(_requests[index]),
                      ),
                    ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text('Error loading requests', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textLight, fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadPendingRequests,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.online_prediction, size: 80, color: AppTheme.textLight.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          const Text('No pending online requests', style: TextStyle(color: AppTheme.textLight)),
        ],
      ),
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
          if (request.deliveryAddress != null && request.deliveryAddress!.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.textLight),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    request.deliveryAddress!,
                    style: AppTheme.lightTheme.textTheme.bodySmall?.copyWith(color: AppTheme.textLight),
                  ),
                ),
              ],
            ),
          if (request.customerPhone != null && request.customerPhone!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.phone_outlined, size: 16, color: AppTheme.textLight),
                const SizedBox(width: 4),
                Text(
                  request.customerPhone!,
                  style: AppTheme.lightTheme.textTheme.bodySmall?.copyWith(color: AppTheme.textLight),
                ),
              ],
            ),
          ],
          if (request.laundryPhotoUrls != null && request.laundryPhotoUrls!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${request.laundryPhotoUrls!.length} photo(s) attached',
              style: const TextStyle(fontSize: 11, color: AppTheme.accentBlue, fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.lightBlue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: AppTheme.accentBlue),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Accept/Decline functionality coming soon. For now, use the main orders management.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textDark),
                  ),
                ),
              ],
            ),
          ),
          /* TODO: Implement Accept/Decline with real database operations
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _handleDeclineRequest(request),
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.errorRed, side: const BorderSide(color: AppTheme.errorRed)),
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
          */
        ],
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

  /* TODO: Implement approve/decline with real database operations
  
  Future<void> _handleDeclineRequest(LaundryOrder request) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline Request?'),
        content: Text('Are you sure you want to decline order #${request.orderNumber}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // TODO: Call service to update order status to 'rejected'
      // await _orderService.rejectOrder(request.id, reason: 'Staff declined');
      _loadPendingRequests();
    }
  }

  void _showApproveDialog(LaundryOrder request) {
    // TODO: Implement full approval flow with:
    // - Weight verification
    // - Category selection
    // - RFID tag assignment
    // - Load creation
    // - Order status update to 'processing'
    // - Bill calculation and push notification to customer
  }
  */
}
