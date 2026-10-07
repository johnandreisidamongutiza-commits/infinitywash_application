import 'package:meta/meta.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import '../models/dispatch_job.dart';
import '../utils/app_error.dart';
import '../config/cache_config.dart';
import 'cache/job_cache_service.dart';
import 'supabase_service.dart';
import 'dispatch_job_adapter.dart';

/// Thrown when a rider tries to start a job that another rider has already
/// claimed. UI should show a friendly message and refresh the job list.
class JobClaimedException implements Exception {
  final String message;
  JobClaimedException([this.message = 'This job was already taken by another rider.']);

  @override
  String toString() => message;
}

/// Pure decision points extracted from [RiderService.startJob] so the
/// double-claim guard logic can be unit tested without a Supabase backend.
@visibleForTesting
abstract final class StartJobGuards {
  /// True when a fetched job's current state blocks a START attempt outright.
  /// Mirrors the pre-checks in [RiderService.startJob]: another rider holds
  /// the claim, or the job is already done/cancelled.
  static bool shouldBlockStart({
    required String? jobRiderId,
    required String? jobStatus,
    required String myEmployeeId,
  }) {
    if (jobRiderId != null && jobRiderId != myEmployeeId) return true;
    if (jobStatus == 'pickup_done' ||
        jobStatus == 'delivery_done' ||
        jobStatus == 'cancelled') {
      return true;
    }
    return false;
  }

  /// Whether the atomic claim UPDATE is permitted for this job state.
  /// The service encodes this as `.or('rider_id.is.null,rider_id.eq.<me>')`
  /// plus `.neq('status', ...)` filters — this function is its truth table.
  static bool claimUpdateAllowed({
    required String? jobRiderId,
    required String? jobStatus,
    required String myEmployeeId,
  }) {
    return (jobRiderId == null || jobRiderId == myEmployeeId) &&
        jobStatus != 'pickup_done' &&
        jobStatus != 'delivery_done' &&
        jobStatus != 'cancelled';
  }

  /// Builds the payload the service writes in the atomic claim update.
  static Map<String, dynamic> claimUpdatePayload({
    required String riderEmployeeId,
    required bool wasUnclaimed,
    DateTime? now,
  }) {
    final ts = (now ?? DateTime.now()).toUtc().toIso8601String();
    return {
      'rider_id': riderEmployeeId,
      'status': 'in_progress',
      'started_at': ts,
      'updated_at': ts,
      if (wasUnclaimed) 'assigned_at': ts,
    };
  }

  /// True when the given claim response means the current rider WON the claim.
  static bool claimWon(List<dynamic> claimedRows) => claimedRows.isNotEmpty;
}

class RiderService {
  final SupabaseClient _client = SupabaseService.client;
  final _supabaseClient = SupabaseService.client;
  final SupabaseService _supabaseService = SupabaseService();
  final DispatchJobAdapter _adapter = DispatchJobAdapter();

  /// Fetch orders that need pickup by rider
  /// Filters: pickup_requested = true AND status = 'pending_pickup'
  /// Shows ALL pickup orders to ALL riders (no rider assignment filtering)
  Future<List<LaundryOrder>> fetchPickupOrders({
    String? assignedRiderId,  // Kept for backwards compatibility, but not used for filtering
    int limit = 50,
  }) async {
    try {
      print('📦 Fetching ALL rider pickup orders (no filtering by rider)...');
      
      // Build query for ALL orders that need pickup - no rider filtering
      final response = await _client
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
          .eq('status', 'pending_pickup')
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
  /// Shows ALL delivery orders to ALL riders (no rider assignment filtering)
  Future<List<LaundryOrder>> fetchDeliveryOrders({
    String? assignedRiderId,  // Kept for backwards compatibility, but not used for filtering
    int limit = 50,
  }) async {
    try {
      print('📦 Fetching ALL rider delivery orders (no filtering by rider)...');
      
      // Build query for ALL orders that need delivery - no rider filtering
      final response = await _client
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
          .inFilter('status', ['ready', 'out_for_delivery'])
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
  /// Uses cache for faster loading and offline support.
  /// Also includes unassigned jobs (NULL rider_id) so all riders see them.
  /// Background refresh only fires when the cache is older than
  /// [CacheConfig.backgroundRefreshMinAge] — a cache hit no longer costs
  /// a Supabase call every time.
  Future<List<DispatchJob>> getRiderJobs(String riderId) async {
    try {
      // Try cache first (fast)
      final cachedJobs = await JobCacheService.getCachedJobs(riderId);
      if (cachedJobs != null) {
        print('📦 Using cached jobs (${cachedJobs.length} jobs)');

        // Stale-while-revalidate: refresh in background only if stale enough.
        final age = await JobCacheService.getCacheAge(riderId);
        final minAgeSeconds = CacheConfig.backgroundRefreshMinAge.inSeconds;
        if (age == null || age >= minAgeSeconds) {
          print('🔄 Cache is stale (${age ?? '?'}s), refreshing in background');
          _refreshJobsInBackground(riderId);
        }
        return cachedJobs;
      }

      // Cache miss - fetch from Supabase
      print('🌐 Fetching jobs from Supabase...');
      
      // Fetch jobs assigned to this rider OR unassigned jobs (NULL rider_id)
      final response = await _supabaseClient
          .from('dispatch_jobs')
          .select()
          .or('rider_id.eq.$riderId,rider_id.is.null')  // NULL for unassigned
          .order('created_at', ascending: true);

      final jobs = (response as List)
          .map((json) => DispatchJob.fromJson(Map<String, dynamic>.from(json as Map)))
          .toList();

      print('✅ Fetched ${jobs.length} jobs (assigned + unassigned)');

      // Cache for next time
      await JobCacheService.cacheJobs(riderId, jobs);

      return jobs;
    } catch (e) {
      print('❌ Error getting rider jobs: $e');

      // Try to return stale cache as fallback
      try {
        final stale = await JobCacheService.getCachedJobs(riderId);
        if (stale != null) {
          print('⚠️ Using stale cache as fallback');
          return stale;
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
      // Fetch jobs assigned to this rider OR unassigned (NULL)
      final response = await _supabaseClient
          .from('dispatch_jobs')
          .select()
          .or('rider_id.eq.$riderId,rider_id.is.null')
          .order('created_at', ascending: true);

      final jobs = (response as List)
          .map((json) => DispatchJob.fromJson(Map<String, dynamic>.from(json as Map)))
          .toList();

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

  /// Get pending jobs (not yet started)
  /// Includes jobs assigned to this rider AND unassigned jobs (NULL rider_id)
  Future<List<DispatchJob>> getPendingJobs(String riderId) async {
    try {
      final response = await _supabaseClient
          .from('dispatch_jobs')
          .select()
          .eq('status', 'pending')
          .or('rider_id.eq.$riderId,rider_id.is.null')  // Include unassigned (NULL)
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => DispatchJob.fromJson(Map<String, dynamic>.from(json as Map)))
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
          .or('status.eq.pickup_done,status.eq.delivery_done')
          .order('completed_at', ascending: false);

      return (response as List)
          .map((json) => DispatchJob.fromJson(Map<String, dynamic>.from(json as Map)))
          .toList();
    } catch (e) {
      print('❌ Error getting completed jobs: $e');
      rethrow;
    }
  }

  /// Start (claim) a job.
  ///
  /// Atomically assigns the current rider's employee ID to the job and marks
  /// it in_progress. If another rider claimed it first, the update matches no
  /// rows and a [JobClaimedException] is thrown — so two riders can never both
  /// work the same job.
  ///
  /// Note: dispatch_jobs.rider_id references employees.id (NOT auth.users.id),
  /// so we resolve the rider's employee record first.
  Future<void> startJob(String jobId) async {
    try {
      // Fetch job details to get order ID, job type and current claim state
      final jobResponse = await _supabaseClient
          .from('dispatch_jobs')
          .select('order_id, job_type, rider_id, status')
          .eq('id', jobId)
          .single();

      final orderId = jobResponse['order_id'] as String;
      final jobType = jobResponse['job_type'] as String;
      final currentRiderId = jobResponse['rider_id'] as String?;
      final status = jobResponse['status'] as String?;

      print('🚀 Starting job $jobId...');
      print('   Current rider_id in DB: $currentRiderId');
      print('   Current status: $status');
      print('   Job type: $jobType');

      // Resolve the real employee ID (dispatch_jobs.rider_id -> employees.id).
      final riderEmployeeId = await getCurrentRiderEmployeeId();
      if (riderEmployeeId == null) {
        throw const AppError(
          'No employee record was found for your account. Ask an admin to link your rider profile.',
          type: AppErrorType.notFound,
        );
      }

      // Fast pre-checks for a friendly error message. The atomic guard below
      // is what actually prevents double-claiming.
      if (StartJobGuards.shouldBlockStart(
        jobRiderId: currentRiderId,
        jobStatus: status,
        myEmployeeId: riderEmployeeId,
      )) {
        if (currentRiderId != null && currentRiderId != riderEmployeeId) {
          throw JobClaimedException();
        }
        throw AppError(
          'This job is no longer available. Refresh your job list to see the latest jobs.',
          type: AppErrorType.notFound,
        );
      }

      // Atomic claim: the WHERE clause only matches if the job is still
      // unclaimed (or already claimed by THIS rider). If another rider claimed
      // it in the meantime, 0 rows are updated and we throw.
      final claimUpdate = StartJobGuards.claimUpdatePayload(
        riderEmployeeId: riderEmployeeId,
        wasUnclaimed: currentRiderId == null,
      );

      final claimedRows = await _supabaseClient
          .from('dispatch_jobs')
          .update(claimUpdate)
          .eq('id', jobId)
          .or('rider_id.is.null,rider_id.eq.$riderEmployeeId')
          .neq('status', 'pickup_done')
          .neq('status', 'delivery_done')
          .neq('status', 'cancelled')
          .select('id');

      if (!StartJobGuards.claimWon(claimedRows)) {
        // Someone else claimed (or completed/cancelled) the job first.
        throw JobClaimedException();
      }

      print('✅ Job claimed by employee $riderEmployeeId: $jobId');

      // Sync order status (if delivery job, order becomes 'out_for_delivery')
      await _supabaseService.syncOrderStatus(
        orderId: orderId,
        dispatchJobStatus: 'in_progress',
        jobType: jobType,
      );

      print('✅ Job started: $jobId (type: $jobType, order: $orderId)');
    } on JobClaimedException {
      rethrow;
    } on AppError {
      rethrow;
    } catch (e) {
      print('❌ Error starting job: $e');
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  /// Check whether a job is still claimable (pending, unclaimed, not done).
  /// Used when a rider opens a job's details so stale screens fail fast with a
  /// clear message instead of a confusing error on Start.
  Future<bool> isJobStillAvailable(String jobId) async {
    try {
      final job = await _supabaseClient
          .from('dispatch_jobs')
          .select('status, rider_id')
          .eq('id', jobId)
          .maybeSingle();

      if (job == null) return false;

      final status = job['status'] as String?;
      if (status == 'pickup_done' ||
          status == 'delivery_done' ||
          status == 'cancelled') {
        return false;
      }

      // Unclaimed jobs are always available; claimed jobs are only available
      // to the rider who holds them.
      final riderId = job['rider_id'] as String?;
      if (riderId == null) return true;

      final myEmployeeId = await getCurrentRiderEmployeeId();
      return riderId == myEmployeeId;
    } catch (e) {
      print('⚠️ Could not verify job availability: $e');
      return true; // Don't block the UI on verification failures.
    }
  }

  /// Complete pickup
  Future<void> completePickup(String jobId, String orderId) async {
    try {
      print('📦 Completing pickup...');
      print('   Job ID: $jobId');
      print('   Order ID: $orderId');

      // Don't update rider_id here - it should already be set when job was started
      // Updating it can cause foreign key errors if using wrong ID

      await _supabaseService.completeDispatchJobAction(
        dispatchJobId: jobId,
        orderId: orderId,
        actionStatus: 'pickup_done',
      );
      
      // Verify the completion was saved
      final verifyResponse = await _supabaseClient
          .from('dispatch_jobs')
          .select('status, rider_id, completed_at')
          .eq('id', jobId)
          .single();
      
      print('✅ Pickup completed: $jobId');
      print('   Final status: ${verifyResponse['status']}');
      print('   Final rider_id: ${verifyResponse['rider_id']}');
      print('   Completed at: ${verifyResponse['completed_at']}');
    } on AppError {
      rethrow;
    } catch (e) {
      print('❌ Error completing pickup: $e');
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  /// Complete delivery
  Future<void> completeDelivery(String jobId, String orderId) async {
    try {
      print('🚚 Completing delivery...');
      print('   Job ID: $jobId');
      print('   Order ID: $orderId');

      // Don't update rider_id here - it should already be set when job was started
      // Updating it can cause foreign key errors if using wrong ID

      await _supabaseService.completeDispatchJobAction(
        dispatchJobId: jobId,
        orderId: orderId,
        actionStatus: 'delivery_done',
      );
      
      // Verify the completion was saved
      final verifyResponse = await _supabaseClient
          .from('dispatch_jobs')
          .select('status, rider_id, completed_at')
          .eq('id', jobId)
          .single();
      
      print('✅ Delivery completed: $jobId');
      print('   Final status: ${verifyResponse['status']}');
      print('   Final rider_id: ${verifyResponse['rider_id']}');
      print('   Completed at: ${verifyResponse['completed_at']}');
    } on AppError {
      rethrow;
    } catch (e) {
      print('❌ Error completing delivery: $e');
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  /// Get rider statistics
  Future<Map<String, int>> getRiderStats(String riderId) async {
    try {
      final allJobs = await getRiderJobs(riderId);

      return {
        'total': allJobs.length,
        'pending': allJobs.where((j) => j.status == 'pending').length,
        'in_progress': allJobs.where((j) => j.status == 'in_progress').length,
        'completed': allJobs.where((j) => j.status == 'pickup_done' || j.status == 'delivery_done').length,
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
          .map((json) => DispatchJob.fromJson(Map<String, dynamic>.from(json as Map)))
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
          .map((json) => DispatchJob.fromJson(Map<String, dynamic>.from(json as Map)))
          .toList();
    } catch (e) {
      print('❌ Error fetching delivery dispatch jobs: $e');
      return [];
    }
  }

  // =========================================================================
  // NEW METHODS FOR DISPATCH JOBS-BASED FETCHING (TASK 1)
  // =========================================================================

  /// Fetch active pickup jobs (pending or in_progress)
  /// Shows ALL unassigned jobs (for now, until rider assignment is properly implemented)
  Future<List<DispatchJob>> fetchActivePickupJobs({int limit = 50}) async {
    try {
      print('📦 Fetching active pickup jobs...');

      // For now, just fetch all active pickup jobs (unassigned OR any rider_id)
      // This is because the rider assignment system needs to be properly set up
      final response = await _supabaseClient
          .from('dispatch_jobs')
          .select()
          .eq('job_type', 'pickup')
          .inFilter('status', ['pending', 'in_progress'])
          .order('created_at', ascending: true)  // FIFO - oldest first
          .limit(limit);

      final jobs = (response as List)
          .map((json) => DispatchJob.fromJson(Map<String, dynamic>.from(json as Map)))
          .toList();

      final enrichedJobs = await _enrichJobsWithCoordinates(jobs);
      print('✅ Fetched ${enrichedJobs.length} active pickup jobs (all unfiltered)');
      return enrichedJobs;
    } catch (e) {
      print('❌ Error fetching active pickup jobs: $e');
      rethrow;
    }
  }

  /// Fetch active delivery jobs (pending or in_progress)
  /// Shows ALL unassigned jobs (for now, until rider assignment is properly implemented)
  Future<List<DispatchJob>> fetchActiveDeliveryJobs({int limit = 50}) async {
    try {
      print('📦 Fetching active delivery jobs...');

      // For now, just fetch all active delivery jobs (unassigned OR any rider_id)
      // This is because the rider assignment system needs to be properly set up
      final response = await _supabaseClient
          .from('dispatch_jobs')
          .select()
          .eq('job_type', 'delivery')
          .inFilter('status', ['pending', 'in_progress'])
          .order('created_at', ascending: true)  // FIFO - oldest first
          .limit(limit);

      final jobs = (response as List)
          .map((json) => DispatchJob.fromJson(Map<String, dynamic>.from(json as Map)))
          .toList();

      final enrichedJobs = await _enrichJobsWithCoordinates(jobs);
      print('✅ Fetched ${enrichedJobs.length} active delivery jobs (all unfiltered)');
      return enrichedJobs;
    } catch (e) {
      print('❌ Error fetching active delivery jobs: $e');
      rethrow;
    }
  }

  /// Fetch completed pickup jobs (completed today only)
  /// Shows all completed pickup jobs for debugging (until rider assignment is fixed)
  Future<List<DispatchJob>> fetchCompletedPickupJobs({int limit = 50}) async {
    try {
      print('📦 Fetching completed pickup jobs (today only)...');

      // Calculate midnight today in LOCAL time, then convert to UTC
      final now = DateTime.now();
      final todayMidnightLocal = DateTime(now.year, now.month, now.day);
      final todayMidnightUtc = todayMidnightLocal.toUtc();
      final todayMidnightUtcString = todayMidnightUtc.toIso8601String();
      
      print('   Today midnight LOCAL: $todayMidnightLocal');
      print('   Today midnight UTC: $todayMidnightUtcString');
      print('   Current time LOCAL: $now');
      print('   Current time UTC: ${now.toUtc().toIso8601String()}');
      
      // First, check if ANY completed pickup jobs exist (ignoring date and rider)
      final testResponse = await _supabaseClient
          .from('dispatch_jobs')
          .select()
          .eq('job_type', 'pickup')
          .eq('status', 'pickup_done')
          .order('completed_at', ascending: false)
          .limit(5);
      
      print('   TEST: Found ${(testResponse as List).length} total completed pickups (any rider, any date)');
      if ((testResponse as List).isNotEmpty) {
        final firstJob = testResponse.first;
        print('   TEST: First job completed_at = ${firstJob['completed_at']}');
        print('   TEST: First job status = ${firstJob['status']}');
        print('   TEST: First job rider_id = ${firstJob['rider_id']}');
      }

      // For now, fetch ALL completed pickup jobs from today (any rider)
      final response = await _supabaseClient
          .from('dispatch_jobs')
          .select()
          .eq('job_type', 'pickup')
          .eq('status', 'pickup_done')
          .gte('completed_at', todayMidnightUtcString)  // Today only
          .order('completed_at', ascending: false)  // Most recent first
          .limit(limit);

      final rawJobs = (response as List)
          .map((json) => DispatchJob.fromJson(Map<String, dynamic>.from(json as Map)))
          .toList();
      final jobs = await _enrichJobsWithCoordinates(rawJobs);

      print('✅ Fetched ${jobs.length} completed pickup jobs (today, all riders)');
      if (jobs.isEmpty) {
        print('⚠️ No completed pickup jobs found. Check:');
        print('   - status = "pickup_done"?');
        print('   - completed_at >= "$todayMidnightUtcString"?');
      }
      return jobs;
    } catch (e) {
      print('❌ Error fetching completed pickup jobs: $e');
      rethrow;
    }
  }

  /// Fetch completed delivery jobs (completed today only)
  /// Shows all completed delivery jobs for debugging (until rider assignment is fixed)
  Future<List<DispatchJob>> fetchCompletedDeliveryJobs({int limit = 50}) async {
    try {
      print('📦 Fetching completed delivery jobs (today only)...');

      // Calculate midnight today in LOCAL time, then convert to UTC
      final now = DateTime.now();
      final todayMidnightLocal = DateTime(now.year, now.month, now.day);
      final todayMidnightUtc = todayMidnightLocal.toUtc();
      final todayMidnightUtcString = todayMidnightUtc.toIso8601String();
      
      print('   Today midnight LOCAL: $todayMidnightLocal');
      print('   Today midnight UTC: $todayMidnightUtcString');

      // For now, fetch ALL completed delivery jobs from today (any rider)
      final response = await _supabaseClient
          .from('dispatch_jobs')
          .select()
          .eq('job_type', 'delivery')
          .eq('status', 'delivery_done')
          .gte('completed_at', todayMidnightUtcString)  // Today only
          .order('completed_at', ascending: false)  // Most recent first
          .limit(limit);

      final rawJobs = (response as List)
          .map((json) => DispatchJob.fromJson(Map<String, dynamic>.from(json as Map)))
          .toList();
      final jobs = await _enrichJobsWithCoordinates(rawJobs);

      print('✅ Fetched ${jobs.length} completed delivery jobs (today, all riders)');
      if (jobs.isEmpty) {
        print('⚠️ No completed delivery jobs found. Check:');
        print('   - status = "delivery_done"?');
        print('   - completed_at >= "$todayMidnightUtcString"?');
      }
      return jobs;
    } catch (e) {
      print('❌ Error fetching completed delivery jobs: $e');
      rethrow;
    }
  }

  // =========================================================================
  // CONVENIENCE METHODS - DISPATCH JOBS TO LAUNDRY ORDERS (TASK 2)
  // =========================================================================

  /// Fetch active pickup jobs as LaundryOrders (for UI compatibility)
  Future<List<LaundryOrder>> fetchActivePickupOrders({int limit = 50}) async {
    final jobs = await fetchActivePickupJobs(limit: limit);
    return await _adapter.toLaundryOrders(jobs);
  }

  /// Fetch active delivery jobs as LaundryOrders (for UI compatibility)
  Future<List<LaundryOrder>> fetchActiveDeliveryOrders({int limit = 50}) async {
    final jobs = await fetchActiveDeliveryJobs(limit: limit);
    return await _adapter.toLaundryOrders(jobs);
  }

  /// Fetch completed pickup jobs as LaundryOrders (for UI compatibility)
  Future<List<LaundryOrder>> fetchCompletedPickupOrders({int limit = 50}) async {
    final jobs = await fetchCompletedPickupJobs(limit: limit);
    return await _adapter.toLaundryOrders(jobs);
  }

  /// Fetch completed delivery jobs as LaundryOrders (for UI compatibility)
  Future<List<LaundryOrder>> fetchCompletedDeliveryOrders({int limit = 50}) async {
    final jobs = await fetchCompletedDeliveryJobs(limit: limit);
    return await _adapter.toLaundryOrders(jobs);
  }

  /// Clear adapter cache (useful when refreshing data)
  void clearAdapterCache() {
    _adapter.clearCache();
  }
  
  /// Get completion time for an order from adapter
  DateTime? getOrderCompletionTime(String orderId) {
    return _adapter.getCompletionTime(orderId);
  }

  // =========================================================================
  // RIDER PAYMENT METHODS
  // =========================================================================

  /// Get current rider's employee ID (from profiles -> employees)
  Future<String?> getCurrentRiderEmployeeId() async {
    try {
      final currentUser = _supabaseClient.auth.currentUser;
      if (currentUser == null) return null;

      final profile = await _supabaseClient
          .from('profiles')
          .select('id')
          .eq('supabase_user_id', currentUser.id)
          .maybeSingle();

      if (profile != null) {
        final employee = await _supabaseClient
            .from('employees')
            .select('id')
            .eq('profile_id', profile['id'])
            .maybeSingle();

        if (employee != null) {
          return employee['id'] as String;
        }
      }
      return null;
    } catch (e) {
      print('❌ Error getting rider employee ID: $e');
      return null;
    }
  }

  /// Fetch order payment status and total amount for a given orderId
  Future<Map<String, dynamic>?> getOrderPaymentInfo(String orderId) async {
    try {
      final row = await _supabaseClient
          .from('orders')
          .select('id, order_number, payment_status, total_amount, subtotal, delivery_fee')
          .eq('id', orderId)
          .maybeSingle();
      return row;
    } catch (e) {
      print('❌ Error fetching order payment info: $e');
      return null;
    }
  }

  /// Fetch single order by ID as LaundryOrder
  Future<LaundryOrder?> fetchOrderById(String orderId) async {
    try {
      final response = await _supabaseClient
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
          .eq('id', orderId)
          .maybeSingle();

      if (response == null) return null;
      final parsed = _parseOrdersFromResponse([response]);
      return parsed.isNotEmpty ? parsed.first : null;
    } catch (e) {
      print('❌ Error fetching order by ID: $e');
      return null;
    }
  }

  /// Fetch one page of orders for the Rider Payment tab.
  ///
  /// [paymentStatus] filters by payment state ('paid' / 'unpaid'); the database
  /// has no 'unpaid' value, so unpaid means "not paid". [offset] + [limit]
  /// drive infinite-scroll pagination.
  Future<List<LaundryOrder>> fetchRiderPaymentOrders({
    String? paymentStatus,
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      print('💳 Fetching rider payment orders '
          '(paymentStatus=$paymentStatus, limit=$limit, offset=$offset)...');
      var query = _supabaseClient
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
          .or('delivery_requested.eq.true,pickup_requested.eq.true')
          .not('status', 'in', '("cancelled","rejected")');

      // The database stores 'paid' / 'pending' / 'refunded' / 'failed' — there
      // is no 'unpaid' value, so unpaid is expressed as "not paid".
      if (paymentStatus == 'paid') {
        query = query.eq('payment_status', 'paid');
      } else if (paymentStatus == 'unpaid') {
        query = query.neq('payment_status', 'paid');
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      print('💳 Fetched ${response.length} rider payment orders');
      return _parseOrdersFromResponse(response);
    } catch (e) {
      print('❌ Error fetching rider payment orders: $e');
      rethrow;
    }
  }

  /// Exact count of a rider payment bucket, used for the Unpaid/Paid tab
  /// badges. Sent as a head count so no rows are transferred.
  ///
  /// Keeps the same base filters as [fetchRiderPaymentOrders].
  Future<int> fetchRiderPaymentOrderCount({
    required String paymentStatus,
  }) async {
    try {
      var query = _supabaseClient
          .from('orders')
          .select('id')
          .or('delivery_requested.eq.true,pickup_requested.eq.true')
          .not('status', 'in', '("cancelled","rejected")');

      query = paymentStatus == 'paid'
          ? query.eq('payment_status', 'paid')
          : query.neq('payment_status', 'paid');

      // limit(0) keeps the response body empty: count() on its own would still
      // return every matching row, which defeats the point of a count query.
      // The exact total still arrives in Content-Range.
      final response = await query.limit(0).count(CountOption.exact);
      return response.count;
    } catch (e) {
      print('❌ Error counting rider payment orders: $e');
      rethrow;
    }
  }

  /// Fallback resolver: if any dispatch job lacks GPS coordinates, resolve them
  /// from the linked customer's profile / address pin (orders -> customers) and
  /// auto-heal the dispatch_jobs record in Supabase.
  Future<List<DispatchJob>> _enrichJobsWithCoordinates(List<DispatchJob> jobs) async {
    final jobsNeedingCoords = jobs.where((j) => j.latitude == null || j.longitude == null).toList();
    if (jobsNeedingCoords.isEmpty) return jobs;

    try {
      final orderIds = jobsNeedingCoords.map((j) => j.orderId).toSet().toList();
      final ordersResponse = await _supabaseClient
          .from('orders')
          .select('''
            id,
            customer_id,
            customers (
              first_name,
              last_name,
              pin_latitude,
              pin_longitude
            )
          ''')
          .inFilter('id', orderIds);

      final Map<String, Map<String, double>> coordsByOrderId = {};
      final Map<String, String> namesByOrderId = {};

      for (final order in (ordersResponse as List)) {
        final orderId = order['id'] as String;
        final customer = order['customers'] as Map<String, dynamic>?;
        final lat = (customer?['pin_latitude'] as num?)?.toDouble();
        final lng = (customer?['pin_longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          coordsByOrderId[orderId] = {'lat': lat, 'lng': lng};
        }
        final first = customer?['first_name'] as String? ?? '';
        final last = customer?['last_name'] as String? ?? '';
        final fullName = last.isNotEmpty ? '$first $last'.trim() : first;
        if (fullName.isNotEmpty) {
          namesByOrderId[orderId] = fullName;
        }
      }

      final enriched = <DispatchJob>[];
      for (final job in jobs) {
        if (job.latitude == null || job.longitude == null) {
          final coords = coordsByOrderId[job.orderId];
          final resolvedName = (job.customerName == null || job.customerName!.trim().isEmpty)
              ? namesByOrderId[job.orderId]
              : job.customerName;

          if (coords != null) {
            final lat = coords['lat']!;
            final lng = coords['lng']!;
            // Auto-heal the database in background so future fetches already have coordinates
            _autoHealJobCoordinates(job.id, lat, lng);
            enriched.add(job.copyWith(
              latitude: lat,
              longitude: lng,
              customerName: resolvedName ?? job.customerName,
            ));
            continue;
          }
        }
        enriched.add(job);
      }
      return enriched;
    } catch (e) {
      print('⚠️ Notice: Could not enrich dispatch jobs with customer coordinates: $e');
      return jobs;
    }
  }

  void _autoHealJobCoordinates(String jobId, double lat, double lng) {
    _supabaseClient
        .from('dispatch_jobs')
        .update({'latitude': lat, 'longitude': lng})
        .eq('id', jobId)
        .then((_) {
          print('✅ Auto-healed coordinates for dispatch job $jobId: ($lat, $lng)');
        })
        .catchError((err) {
          print('⚠️ Auto-heal error for dispatch job $jobId: $err');
        });
  }

}
