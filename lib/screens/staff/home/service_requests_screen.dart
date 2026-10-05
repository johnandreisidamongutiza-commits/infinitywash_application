import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_error.dart';
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
          _errorMessage = mapErrorToMessage(e);
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

  Future<void> _handleDeclineRequest(LaundryOrder request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline Request?'),
        content: Text('Are you sure you want to decline order #${request.displayNumber}?'),
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

    if (confirmed != true || !mounted) return;

    try {
      await _serviceRequestService.rejectServiceRequest(
        orderId: request.id,
        reason: 'Declined by staff',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request ${request.displayNumber} declined')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapErrorToMessage(e)),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
    _loadPendingRequests();
  }

  Future<void> _showApproveDialog(LaundryOrder request) async {
    // Ask for the staff's estimate of loads (used for the initial bill).
    final estimatedLoads = await showDialog<int>(
      context: context,
      builder: (context) {
        int selected = 2;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text('Accept ${request.displayNumber}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Estimated loads (customer suggested ${request.estimatedLoads ?? 'not specified'}):'),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: selected,
                  items: const [1, 2, 3, 4, 5]
                      .map((n) => DropdownMenuItem(value: n, child: Text('$n load${n > 1 ? 's' : ''}')))
                      .toList(),
                  onChanged: (v) => setState(() => selected = v ?? selected),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, selected),
                child: const Text('Accept'),
              ),
            ],
          ),
        );
      },
    );

    if (estimatedLoads == null || !mounted) return;

    try {
      // Creates the pickup dispatch job for rider-pickup requests.
      await _serviceRequestService.approveServiceRequest(
        orderId: request.id,
        isRiderPickup: request.collectionMethod == CollectionMethod.riderPickup,
        estimatedLoads: estimatedLoads,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request ${request.displayNumber} accepted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapErrorToMessage(e)),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
    _loadPendingRequests();
  }
}
