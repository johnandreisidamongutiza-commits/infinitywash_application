import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

/// Test Screen - Phase 11.5: Order Status Synchronization
/// 
/// Tests the automatic status sync between dispatch_jobs and orders:
/// - pickup_done → orders.status = 'processing'
/// - delivery_done → orders.status = 'completed'
class TestStatusSyncScreen extends StatefulWidget {
  const TestStatusSyncScreen({super.key});

  @override
  State<TestStatusSyncScreen> createState() => _TestStatusSyncScreenState();
}

class _TestStatusSyncScreenState extends State<TestStatusSyncScreen> {
  final _supabaseService = SupabaseService();
  final _dispatchJobIdController = TextEditingController();
  final _orderIdController = TextEditingController();
  
  String? _currentDispatchJobStatus;
  String? _currentOrderStatus;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _dispatchJobIdController.dispose();
    _orderIdController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentStatuses() async {
    final dispatchJobId = _dispatchJobIdController.text.trim();
    final orderId = _orderIdController.text.trim();

    if (dispatchJobId.isEmpty || orderId.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both Dispatch Job ID and Order ID';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Fetch dispatch job status
      final dispatchJob = await SupabaseService.client
          .from('dispatch_jobs')
          .select('status')
          .eq('id', dispatchJobId)
          .maybeSingle();

      // Fetch order status
      final order = await SupabaseService.client
          .from('orders')
          .select('status')
          .eq('id', orderId)
          .maybeSingle();

      setState(() {
        _currentDispatchJobStatus = dispatchJob?['status'] as String?;
        _currentOrderStatus = order?['status'] as String?;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error fetching statuses: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _completePickup() async {
    final dispatchJobId = _dispatchJobIdController.text.trim();
    final orderId = _orderIdController.text.trim();

    if (dispatchJobId.isEmpty || orderId.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both Dispatch Job ID and Order ID';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _supabaseService.completeDispatchJobAction(
        dispatchJobId: dispatchJobId,
        orderId: orderId,
        actionStatus: 'pickup_done',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Pickup completed! Order status → processing'),
          backgroundColor: Colors.green,
        ),
      );

      // Refresh statuses
      await _fetchCurrentStatuses();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error completing pickup: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _completeDelivery() async {
    final dispatchJobId = _dispatchJobIdController.text.trim();
    final orderId = _orderIdController.text.trim();

    if (dispatchJobId.isEmpty || orderId.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both Dispatch Job ID and Order ID';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _supabaseService.completeDispatchJobAction(
        dispatchJobId: dispatchJobId,
        orderId: orderId,
        actionStatus: 'delivery_done',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Delivery completed! Order status → completed'),
          backgroundColor: Colors.green,
        ),
      );

      // Refresh statuses
      await _fetchCurrentStatuses();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error completing delivery: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Status Sync'),
        backgroundColor: Colors.blue,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Instructions
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '📋 Phase 11.5: Status Synchronization',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Tests automatic status sync:\n'
                            '• Complete Pickup → dispatch_jobs.status = pickup_done\n'
                            '                   → orders.status = processing\n'
                            '• Complete Delivery → dispatch_jobs.status = delivery_done\n'
                            '                     → orders.status = completed',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Dispatch Job ID Input
                  TextField(
                    controller: _dispatchJobIdController,
                    decoration: const InputDecoration(
                      labelText: 'Dispatch Job ID',
                      border: OutlineInputBorder(),
                      hintText: 'Enter dispatch job UUID',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Order ID Input
                  TextField(
                    controller: _orderIdController,
                    decoration: const InputDecoration(
                      labelText: 'Order ID',
                      border: OutlineInputBorder(),
                      hintText: 'Enter order UUID',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Fetch Status Button
                  ElevatedButton.icon(
                    onPressed: _fetchCurrentStatuses,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Fetch Current Statuses'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Current Statuses Display
                  if (_currentDispatchJobStatus != null ||
                      _currentOrderStatus != null)
                    Card(
                      color: Colors.grey.shade100,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current Statuses',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.delivery_dining, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Dispatch Job: ${_currentDispatchJobStatus ?? 'N/A'}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.shopping_bag, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Order: ${_currentOrderStatus ?? 'N/A'}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Complete Pickup Button
                  ElevatedButton.icon(
                    onPressed: _completePickup,
                    icon: const Icon(Icons.check_box),
                    label: const Text('Complete Pickup'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Complete Delivery Button
                  ElevatedButton.icon(
                    onPressed: _completeDelivery,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Complete Delivery'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Error Message
                  if (_errorMessage != null)
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.error, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Test Instructions
                  Card(
                    color: Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🧪 How to Test',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '1. Create test order in Supabase\n'
                            '2. Create dispatch job linked to that order\n'
                            '3. Enter IDs above and fetch statuses\n'
                            '4. Click "Complete Pickup"\n'
                            '5. Verify dispatch_jobs.status = pickup_done\n'
                            '6. Verify orders.status = processing\n'
                            '7. Click "Complete Delivery"\n'
                            '8. Verify dispatch_jobs.status = delivery_done\n'
                            '9. Verify orders.status = completed',
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
