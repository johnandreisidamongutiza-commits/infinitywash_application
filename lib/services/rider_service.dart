import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import '../models/dispatch_job.dart';
import 'cache/job_cache_service.dart';
import 'supabase_service.dart';

class RiderService {
  final SupabaseClient _client = SupabaseService.client;
  final _supabaseClient = SupabaseService.client;
  final SupabaseService _supabaseService = SupabaseService();

  /// Fetch orders that need pickup by rider
  /// Filters: pickup_requested = true AND status = 'pending_pickup'
  Future<List<LaundryOrder>> fetchPickupOrders({
    String? assignedRiderId,
    int limit = 50,
  }) async {
    try {
      print('📦 Fetching rider pickup orders...');
      
      // Build query for orders that need pickup
      var query = _client
          .from('orders')
          .select('''
            id,
            order_number,
            customer_id,
            source,
            service_id,
            service_name,
            weight_kg,
            loads_count,
            customer_notes,
            staff_notes,
            assigned_staff_id,
            assigned_rider_id,
            pickup_requested,
            delivery_requested,
            pickup_address,
            delivery_address,
            landmark,
            subtotal,
            delivery_fee,
            total_amount,
            payment_status,
            status,
            received_at,
            processing_at,
            ready_at,
            out_for_delivery_at,
            completed_at,
            created_at,
            updated_at,
            laundry_photo_urls,
            customer_description,
            estimated_loads,
            rejection_reason,
            reviewed_at,
            reviewed_by,
            expires_at,
            order_loads(*),
            customers(first_name, last_name, customer_code, phone, address, landmark)
          ''')
          .eq('pickup_requested', true)
          .eq('status', 'pending_pickup');

      // Filter by assigned rider if provided
      if (assignedRiderId != null) {
        query = query.or('assigned_rider_id.is.null,assigned_rider_id.eq.$assignedRiderId');
      } else {
        // Show all unassigned orders or orders assigned to any rider (for now)
        // Later can add rider assignment logic
      }

      final response = await query
          .order('created_at', ascending: true) // FIFO - oldest first
          .limit(limit);

      print('📦 Query returned ${response.length} pickup orders');

      return _parseOrdersFromResponse(response);
    } catch (e) {
      print('❌ Error fetching pickup orders: $e');
      rethrow;
    }
  }

  /// Fetch orders that need delivery by rider
  /// Filters: delivery_requested = true AND status IN ('ready', 'out_for_delivery')
  Future<List<LaundryOrder>> fetchDeliveryOrders({
    String? assignedRiderId,
    int limit = 50,
  }) async {
    try {
      print('📦 Fetching rider delivery orders...');
      
      // Build query for orders that need delivery
      var query = _client
          .from('orders')
          .select('''
            id,
            order_number,
            customer_id,
            source,
            service_id,
            service_name,
            weight_kg,
            loads_count,
            customer_notes,
            staff_notes,
            assigned_staff_id,
            assigned_rider_id,
            pickup_requested,
            delivery_requested,
            pickup_address,
            delivery_address,
            landmark,
            subtotal,
            delivery_fee,
            total_amount,
            payment_status,
            status,
            received_at,
            processing_at,
            ready_at,
            out_for_delivery_at,
            completed_at,
            created_at,
            updated_at,
            laundry_photo_urls,
            customer_description,
            estimated_loads,
            rejection_reason,
            reviewed_at,
            reviewed_by,
            expires_at,
            order_loads(*),
            customers(first_name, last_name, customer_code, phone, address, landmark)
          ''')
          .eq('delivery_requested', true)
          .inFilter('status', ['ready', 'out_for_delivery']);

      // Filter by assigned rider if provided
      if (assignedRiderId != null) {
        query = query.or('assigned_rider_id.is.null,assigned_rider_id.eq.$assignedRiderId');
      }

      final response = await query
          .order('ready_at', ascending: true) // Oldest ready orders first
          .limit(limit);

      print('📦 Query returned ${response.length} delivery orders');

      return _parseOrdersFromResponse(response);
    } catch (e) {
      print('❌ Error fetching delivery orders: $e');
      rethrow;
    }
  }

  /// Parse Supabase response into LaundryOrder objects
  List<LaundryOrder> _parseOrdersFromResponse(List<dynamic> response) {
    final orders = <LaundryOrder>[];

    for (var orderData in response) {
      try {
        // Parse loads
        final loadsData = orderData['order_loads'] as List?;
        final loads = loadsData?.map((loadJson) {
          return OrderLoad.fromJson(loadJson as Map<String, dynamic>);
        }).toList() ?? [];

        // Extract customer information
        final customerData = orderData['customers'] as Map<String, dynamic>?;
        final firstName = customerData?['first_name'] as String? ?? '';
        final lastName = customerData?['last_name'] as String? ?? '';
        final customerName = lastName.isNotEmpty 
            ? '$firstName $lastName' 
            : firstName.isNotEmpty 
                ? firstName 
                : 'Unknown Customer';
        final customerPhone = customerData?['phone'] as String?;

        // Determine collection and return methods based on flags
        final pickupRequested = orderData['pickup_requested'] as bool? ?? false;
        final deliveryRequested = orderData['delivery_requested'] as bool? ?? false;
        
        final collectionMethod = pickupRequested 
            ? CollectionMethod.riderPickup 
            : CollectionMethod.dropOff;
        
        final returnMethod = deliveryRequested 
            ? ReturnMethod.delivery 
            : ReturnMethod.shopPickup;

        // Determine order channel
        final source = orderData['source'] as String?;
        final channel = source == 'walk_in' 
            ? OrderChannel.walkIn 
            : OrderChannel.online;

        // Parse status
        final statusStr = orderData['status'] as String? ?? 'pending_approval';
        final status = _mapDatabaseStatus(statusStr);

        // Parse payment status
        final paymentStatusStr = orderData['payment_status'] as String? ?? 'pending';
        final paymentStatus = paymentStatusStr == 'paid' 
            ? PaymentStatus.paid 
            : PaymentStatus.unpaid;

        // Get addresses - prioritize order-specific addresses, fallback to customer default
        final pickupAddress = orderData['pickup_address'] as String?;
        final deliveryAddress = orderData['delivery_address'] as String?;
        final landmarkFromOrder = orderData['landmark'] as String?;
        final landmarkFromCustomer = customerData?['address'] as String?;
        final landmark = landmarkFromOrder ?? landmarkFromCustomer;
        
        // Use appropriate address based on pickup/delivery flags
        final customerAddress = customerData?['address'] as String?;
        final finalPickupAddress = pickupAddress ?? (pickupRequested ? customerAddress : null);
        final finalDeliveryAddress = deliveryAddress ?? (deliveryRequested ? customerAddress : null);

        // Create order object
        final order = LaundryOrder(
          id: orderData['id'] as String,
          orderNumber: orderData['order_number'] as String?,
          customerName: customerName,
          customerPhone: customerPhone,
          deliveryAddress: finalDeliveryAddress ?? finalPickupAddress, // Use either address
          deliveryLandmark: landmark,
          channel: channel,
          collectionMethod: collectionMethod,
          returnMethod: returnMethod,
          status: status,
          paymentStatus: paymentStatus,
          loads: loads,
          instructions: orderData['customer_notes'] as String?,
          staffMessage: orderData['staff_notes'] as String?,
          createdAt: DateTime.parse(orderData['created_at'] as String),
          totalAmount: (orderData['total_amount'] as num?)?.toDouble(),
          laundryPhotoUrls: (orderData['laundry_photo_urls'] as List?)
              ?.map((e) => e as String)
              .toList(),
          customerDescription: orderData['customer_description'] as String?,
          estimatedLoads: orderData['estimated_loads'] as int?,
          rejectionReason: orderData['rejection_reason'] as String?,
          reviewedAt: orderData['reviewed_at'] != null 
              ? DateTime.parse(orderData['reviewed_at'] as String) 
              : null,
          reviewedBy: orderData['reviewed_by'] as String?,
          expiresAt: orderData['expires_at'] != null 
              ? DateTime.parse(orderData['expires_at'] as String) 
              : null,
        );

        orders.add(order);
      } catch (e) {
        print('⚠️ Error parsing order: $e');
        // Continue processing other orders
      }
    }

    print('✅ Parsed ${orders.length} orders');
    return orders;
  }

  /// Map database status string to OrderStatus enum
  OrderStatus _mapDatabaseStatus(String status) {
    switch (status) {
      case 'pending_approval':
        return OrderStatus.pending_approval;
      case 'pending_pickup':
        return OrderStatus.pending_pickup;
      case 'processing':
        return OrderStatus.processing;
      case 'ready':
        return OrderStatus.ready;
      case 'out_for_delivery':
        return OrderStatus.out_for_delivery;
      case 'completed':
        return OrderStatus.completed;
      case 'cancelled':
        return OrderStatus.cancelled;
      default:
        return OrderStatus.pending_approval;
    }
  }

  /// Assign a rider to an order
  Future<void> assignRiderToOrder(String orderId, String riderId) async {
    try {
      await _client
          .from('orders')
          .update({
            'assigned_rider_id': riderId,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);

      print('✅ Assigned rider $riderId to order $orderId');
    } catch (e) {
      print('❌ Error assigning rider: $e');
      rethrow;
    }
  }

  /// Update order status (for rider actions)
  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    try {
      final updates = {
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Add timestamp fields based on status
      switch (newStatus) {
        case 'processing':
          updates['processing_at'] = DateTime.now().toIso8601String();
          break;
        case 'ready':
          updates['ready_at'] = DateTime.now().toIso8601String();
          break;
        case 'out_for_delivery':
          updates['out_for_delivery_at'] = DateTime.now().toIso8601String();
          break;
        case 'completed':
          updates['completed_at'] = DateTime.now().toIso8601String();
          break;
      }

      await _client
          .from('orders')
          .update(updates)
          .eq('id', orderId);

      print('✅ Updated order $orderId status to: $newStatus');
    } catch (e) {
      print('❌ Error updating order status: $e');
      rethrow;
    }
  }

  /// Get all dispatch jobs for a rider
  /// Uses cache for faster loading and offline support
  Future<List<DispatchJob>> getRiderJobs(String riderId) async {
    try {
      // Try cache first (fast)
      final cachedJobs = await JobCacheService.getCachedJobs(riderId);
      if (cachedJobs != null) {
        print('📦 Using cached jobs (${cachedJobs.length} jobs)');
        // Refresh in background
        _refreshJobsInBackground(riderId);
        return cachedJobs;
      }

      // Cache miss - fetch from Supabase
      print('🌐 Fetching jobs from Supabase...');
      final jobs = await _supabaseService.getDispatchJobsByRider(riderId);

      // Cache for next time
      await JobCacheService.cacheJobs(riderId, jobs);

      return jobs;
    } catch (e) {
      print('❌ Error getting rider jobs: $e');

      // Try to return stale cache as fallback
      try {
        final cachedJobs = await JobCacheService.getCachedJobs(riderId);
        if (cachedJobs != null) {
          print('⚠️ Using stale cache as fallback');
          return cachedJobs;
        }
      } catch (cacheError) {
        print('❌ Cache fallback failed: $cacheError');
      }

      rethrow;
    }
  }

  /// Refresh jobs in background (don't wait for result)
  Future<void> _refreshJobsInBackground(String riderId) async {
    try {
      final jobs = await _supabaseService.getDispatchJobsByRider(riderId);
      await JobCacheService.cacheJobs(riderId, jobs);
      print('🔄 Background refresh complete');
    } catch (e) {
      print('⚠️ Background refresh failed: $e');
    }
  }

  /// Get active job for a rider
  Future<DispatchJob?> getActiveJob(String riderId) async {
    try {
      return await _supabaseService.getActiveJobByRider(riderId);
    } catch (e) {
      print('❌ Error getting active job: $e');
      rethrow;
    }
  }

  /// Get pending jobs (assigned but not started)
  Future<List<DispatchJob>> getPendingJobs(String riderId) async {
    try {
      final response = await _supabaseClient
          .from('dispatch_jobs')
          .select()
          .eq('rider_id', riderId)
          .eq('status', 'assigned')
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => DispatchJob.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Error getting pending jobs: $e');
      rethrow;
    }
  }

  /// Get completed jobs for a rider
  Future<List<DispatchJob>> getCompletedJobs(String riderId) async {
    try {
      final response = await _supabaseClient
          .from('dispatch_jobs')
          .select()
          .eq('rider_id', riderId)
          .eq('status', 'delivery_done')
          .order('completed_at', ascending: false);

      return (response as List)
          .map((json) => DispatchJob.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Error getting completed jobs: $e');
      rethrow;
    }
  }

  /// Start a job
  Future<void> startJob(String jobId) async {
    try {
      await _supabaseService.updateDispatchJobStatus(
        jobId,
        'in_progress',
        startedAt: DateTime.now(),
      );
      print('✅ Job started: $jobId');
    } catch (e) {
      print('❌ Error starting job: $e');
      rethrow;
    }
  }

  /// Complete pickup
  Future<void> completePickup(String jobId, String orderId) async {
    try {
      await _supabaseService.completeDispatchJobAction(
        dispatchJobId: jobId,
        orderId: orderId,
        actionStatus: 'pickup_done',
      );
      print('✅ Pickup completed: $jobId');
    } catch (e) {
      print('❌ Error completing pickup: $e');
      rethrow;
    }
  }

  /// Complete delivery
  Future<void> completeDelivery(String jobId, String orderId) async {
    try {
      await _supabaseService.completeDispatchJobAction(
        dispatchJobId: jobId,
        orderId: orderId,
        actionStatus: 'delivery_done',
      );
      print('✅ Delivery completed: $jobId');
    } catch (e) {
      print('❌ Error completing delivery: $e');
      rethrow;
    }
  }

  /// Get rider statistics
  Future<Map<String, int>> getRiderStats(String riderId) async {
    try {
      final allJobs = await getRiderJobs(riderId);

      return {
        'total': allJobs.length,
        'pending': allJobs.where((j) => j.status == 'assigned').length,
        'in_progress': allJobs.where((j) => j.status == 'in_progress').length,
        'completed': allJobs.where((j) => j.status == 'delivery_done').length,
      };
    } catch (e) {
      print('❌ Error getting rider stats: $e');
      return {'total': 0, 'pending': 0, 'in_progress': 0, 'completed': 0};
    }
  }

  /// Fetch pickup dispatch jobs (NEW - for delivery tracking)
  Future<List<DispatchJob>> fetchPickupDispatchJobs() async {
    try {
      final riderId = _supabaseClient.auth.currentUser?.id;
      if (riderId == null) {
        print('❌ No authenticated rider');
        return [];
      }

      final response = await _supabaseClient
          .from('dispatch_jobs')
          .select()
          .eq('rider_id', riderId)
          .eq('job_type', 'pickup')
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => DispatchJob.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Error fetching pickup dispatch jobs: $e');
      return [];
    }
  }

  /// Fetch delivery dispatch jobs (NEW - for delivery tracking)
  Future<List<DispatchJob>> fetchDeliveryDispatchJobs() async {
    try {
      final riderId = _supabaseClient.auth.currentUser?.id;
      if (riderId == null) {
        print('❌ No authenticated rider');
        return [];
      }

      final response = await _supabaseClient
          .from('dispatch_jobs')
          .select()
          .eq('rider_id', riderId)
          .eq('job_type', 'delivery')
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => DispatchJob.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Error fetching delivery dispatch jobs: $e');
      return [];
    }
  }

}
