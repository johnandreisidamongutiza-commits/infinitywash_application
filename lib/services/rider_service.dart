import '../services/supabase_service.dart';
import '../services/cache/job_cache_service.dart';
import '../models/dispatch_job.dart';
import '../models/order.dart';

/// Service for managing rider operations
class RiderService {
  final _supabaseClient = SupabaseService.client;
  final SupabaseService _supabaseService = SupabaseService();

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

  /// Fetch pickup orders (jobs with job_type = 'pickup')
  /// Returns LaundryOrder for compatibility with existing rider screens
  Future<List<LaundryOrder>> fetchPickupOrders() async {
    try {
      // TODO: Implement fetching LaundryOrder from orders table
      // For now, return empty list to avoid errors
      print('⚠️ fetchPickupOrders returning empty - implement LaundryOrder fetch from orders table');
      return [];
    } catch (e) {
      print('❌ Error fetching pickup orders: $e');
      return [];
    }
  }

  /// Fetch delivery orders (jobs with job_type = 'delivery')
  /// Returns LaundryOrder for compatibility with existing rider screens
  Future<List<LaundryOrder>> fetchDeliveryOrders() async {
    try {
      // TODO: Implement fetching LaundryOrder from orders table
      // For now, return empty list to avoid errors
      print('⚠️ fetchDeliveryOrders returning empty - implement LaundryOrder fetch from orders table');
      return [];
    } catch (e) {
      print('❌ Error fetching delivery orders: $e');
      return [];
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

  /// Update order status (legacy method for compatibility)
  /// Prefer using completePickup() or completeDelivery() instead
  Future<void> updateOrderStatus(String orderId, String status) async {
    try {
      await _supabaseClient
          .from('orders')
          .update({
            'status': status,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', orderId);
      
      print('✅ Order status updated: $orderId -> $status');
    } catch (e) {
      print('❌ Error updating order status: $e');
      rethrow;
    }
  }
}
