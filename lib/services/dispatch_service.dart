import '../services/supabase_service.dart';
import '../models/dispatch_job.dart';
import '../models/order.dart';

/// Dispatch Service
/// 
/// Handles the complete workflow from order approval to dispatch job creation.
/// Connects staff approval system with rider delivery tracking.
class DispatchService {
  final SupabaseService _supabaseService = SupabaseService();
  final _supabaseClient = SupabaseService.client;

  /// Complete Workflow: Staff Approves Order → Create Dispatch Jobs
  /// 
  /// This is called when staff approves a customer order.
  /// Creates pickup and delivery dispatch jobs for the rider.
  Future<Map<String, DispatchJob>> createDispatchJobsForOrder({
    required LaundryOrder order,
    required String riderId,
    required double pickupLatitude,
    required double pickupLongitude,
    required String pickupAddress,
    double? deliveryLatitude,
    double? deliveryLongitude,
    String? deliveryAddress,
  }) async {
    try {
      print('📋 Creating dispatch jobs for order: ${order.orderNumber}');

      // 1. Create PICKUP job (rider goes to customer to collect laundry)
      final pickupJob = await _supabaseService.createDispatchJob(
        orderId: order.id,
        riderId: riderId,
        jobType: 'pickup',
        latitude: pickupLatitude,
        longitude: pickupLongitude,
        address: pickupAddress,
        notes: 'Pickup laundry from customer',
      );

      print('✅ Pickup job created: ${pickupJob.id}');

      // 2. Create DELIVERY job (rider delivers clean laundry back to customer)
      // This will be activated after pickup is done
      final deliveryJob = await _supabaseService.createDispatchJob(
        orderId: order.id,
        riderId: riderId,
        jobType: 'delivery',
        latitude: deliveryLatitude ?? pickupLatitude, // Use pickup location if delivery not specified
        longitude: deliveryLongitude ?? pickupLongitude,
        address: deliveryAddress ?? pickupAddress,
        notes: 'Deliver clean laundry to customer',
      );

      print('✅ Delivery job created: ${deliveryJob.id}');

      return {
        'pickup': pickupJob,
        'delivery': deliveryJob,
      };
    } catch (e) {
      print('❌ Error creating dispatch jobs: $e');
      rethrow;
    }
  }

  /// Staff Approval Handler
  /// 
  /// Called when staff approves an order in the admin panel.
  /// Automatically creates dispatch jobs and assigns to a rider.
  Future<void> handleOrderApproval({
    required String orderId,
    required String riderId,
    required double customerLatitude,
    required double customerLongitude,
    required String customerAddress,
  }) async {
    try {
      print('👨‍💼 Staff approving order: $orderId');

      // 1. Update order status to approved
      await _supabaseClient.from('orders').update({
        'status': 'pending_pickup',
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderId);

      print('✅ Order status updated to pending_pickup');

      // 2. Get order details
      final orderResponse = await _supabaseClient
          .from('orders')
          .select()
          .eq('id', orderId)
          .single();

      final order = LaundryOrder.fromJson(orderResponse);

      // 3. Create dispatch jobs
      await createDispatchJobsForOrder(
        order: order,
        riderId: riderId,
        pickupLatitude: customerLatitude,
        pickupLongitude: customerLongitude,
        pickupAddress: customerAddress,
        // Delivery location same as pickup (return to customer)
        deliveryLatitude: customerLatitude,
        deliveryLongitude: customerLongitude,
        deliveryAddress: customerAddress,
      );

      print('✅ Order approval complete! Rider can now see the job.');
    } catch (e) {
      print('❌ Error handling order approval: $e');
      rethrow;
    }
  }

  /// Get pending pickup jobs for a rider
  /// Shows all jobs that need to be picked up
  Future<List<DispatchJob>> getRiderPendingPickups(String riderId) async {
    try {
      final response = await _supabaseClient
          .from('dispatch_jobs')
          .select()
          .eq('rider_id', riderId)
          .eq('job_type', 'pickup')
          .inFilter('status', ['assigned', 'in_progress'])
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => DispatchJob.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Error fetching pending pickups: $e');
      return [];
    }
  }

  /// Get pending delivery jobs for a rider
  /// Shows all jobs that need to be delivered (after pickup is done)
  Future<List<DispatchJob>> getRiderPendingDeliveries(String riderId) async {
    try {
      final response = await _supabaseClient
          .from('dispatch_jobs')
          .select()
          .eq('rider_id', riderId)
          .eq('job_type', 'delivery')
          .inFilter('status', ['assigned', 'in_progress'])
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => DispatchJob.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Error fetching pending deliveries: $e');
      return [];
    }
  }

  /// Assign dispatch job to a different rider
  /// Used by staff to reassign jobs
  Future<void> reassignJob({
    required String jobId,
    required String newRiderId,
  }) async {
    try {
      await _supabaseClient.from('dispatch_jobs').update({
        'rider_id': newRiderId,
        'assigned_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', jobId);

      print('✅ Job $jobId reassigned to rider $newRiderId');
    } catch (e) {
      print('❌ Error reassigning job: $e');
      rethrow;
    }
  }

  /// Cancel dispatch job
  /// Used when order is cancelled or rider cannot complete
  Future<void> cancelJob(String jobId, String reason) async {
    try {
      await _supabaseClient.from('dispatch_jobs').update({
        'status': 'cancelled',
        'notes': reason,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', jobId);

      print('✅ Job $jobId cancelled: $reason');
    } catch (e) {
      print('❌ Error cancelling job: $e');
      rethrow;
    }
  }
}
