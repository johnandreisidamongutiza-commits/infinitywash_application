import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import '../models/dispatch_job.dart';

class SupabaseService {
  // Get the Supabase client instance
  static SupabaseClient get client => Supabase.instance.client;
  
  // Get the current user
  static User? get currentUser => client.auth.currentUser;
  
  // Check if user is logged in
  static bool get isLoggedIn => currentUser != null;
  
  // Get auth stream to listen for auth state changes
  static Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;
  
  // ========================================
  // DISPATCH JOBS - Phase 9
  // ========================================
  
  /// Get dispatch jobs for a specific rider
  Future<List<DispatchJob>> getDispatchJobsByRider(String riderId) async {
    try {
      final response = await client
          .from('dispatch_jobs')
          .select()
          .eq('rider_id', riderId)
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => DispatchJob.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Error fetching rider jobs: $e');
      rethrow;
    }
  }
  
  /// Get active (in_progress) dispatch job for a rider
  Future<DispatchJob?> getActiveJobByRider(String riderId) async {
    try {
      final response = await client
          .from('dispatch_jobs')
          .select()
          .eq('rider_id', riderId)
          .eq('status', 'in_progress')
          .maybeSingle();

      if (response != null) {
        return DispatchJob.fromJson(response as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      print('❌ Error fetching active job: $e');
      rethrow;
    }
  }
  
  /// Get dispatch job by order ID (for customer side)
  Future<DispatchJob?> getDispatchJobByOrder(String orderId) async {
    try {
      final response = await client
          .from('dispatch_jobs')
          .select()
          .eq('order_id', orderId)
          .eq('status', 'in_progress')
          .maybeSingle();

      if (response != null) {
        return DispatchJob.fromJson(response as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      print('❌ Error fetching job by order: $e');
      rethrow;
    }
  }
  
  /// Update dispatch job status
  Future<void> updateDispatchJobStatus(
    String jobId,
    String newStatus, {
    DateTime? startedAt,
    DateTime? completedAt,
  }) async {
    try {
      final updates = <String, dynamic>{
        'status': newStatus,
      };
      
      if (startedAt != null) {
        updates['started_at'] = startedAt.toUtc().toIso8601String();
      }
      
      if (completedAt != null) {
        updates['completed_at'] = completedAt.toUtc().toIso8601String();
      }
      
      await client
          .from('dispatch_jobs')
          .update(updates)
          .eq('id', jobId);
      
      print('✅ Updated job $jobId status to $newStatus');
    } catch (e) {
      print('❌ Error updating job status: $e');
      rethrow;
    }
  }
  
  /// Create a new dispatch job
  Future<DispatchJob> createDispatchJob({
    required String orderId,
    required String riderId,
    required String jobType,
    required double latitude,
    required double longitude,
    String? address,
    String? landmark,
    String? notes,
    DateTime? scheduledAt,
  }) async {
    try {
      final data = {
        'order_id': orderId,
        'rider_id': riderId,
        'job_type': jobType,
        'status': 'assigned',
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'landmark': landmark,
        'notes': notes,
        'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
        'assigned_at': DateTime.now().toUtc().toIso8601String(),
      };
      
      final response = await client
          .from('dispatch_jobs')
          .insert(data)
          .select()
          .single();
      
      print('✅ Created dispatch job: ${response['id']}');
      return DispatchJob.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      print('❌ Error creating dispatch job: $e');
      rethrow;
    }
  }
  
  // ========================================
  // RIDER LOCATION - Phase 10
  // ========================================
  
  /// Update rider location in Supabase
  Future<void> updateRiderLocation({
    required String riderId,
    required String? dispatchJobId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await client.from('rider_locations').upsert({
        'rider_id': riderId,
        'dispatch_job_id': dispatchJobId,
        'latitude': latitude,
        'longitude': longitude,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      
      print('✅ Updated rider location: $latitude, $longitude');
    } catch (e) {
      print('❌ Error updating rider location: $e');
      rethrow;
    }
  }
  
  /// Subscribe to rider location updates (for customer side)
  Stream<LatLng?> subscribeToRiderLocation(String riderId) {
    return client
        .from('rider_locations')
        .stream(primaryKey: ['rider_id'])
        .eq('rider_id', riderId)
        .map((data) {
          if (data.isEmpty) return null;
          
          final location = data.first;
          final lat = location['latitude'] as num?;
          final lng = location['longitude'] as num?;
          
          if (lat != null && lng != null) {
            return LatLng(lat.toDouble(), lng.toDouble());
          }
          
          return null;
        });
  }
  
  /// Get rider's current location (one-time fetch)
  Future<LatLng?> getRiderLocation(String riderId) async {
    try {
      final response = await client
          .from('rider_locations')
          .select()
          .eq('rider_id', riderId)
          .maybeSingle();
      
      if (response != null) {
        final lat = response['latitude'] as num?;
        final lng = response['longitude'] as num?;
        
        if (lat != null && lng != null) {
          return LatLng(lat.toDouble(), lng.toDouble());
        }
      }
      
      return null;
    } catch (e) {
      print('❌ Error getting rider location: $e');
      rethrow;
    }
  }
  
  // ========================================
  // ORDER STATUS SYNC - Phase 11.5
  // ========================================
  
  /// Sync order status based on dispatch job status
  /// pickup_done → orders.status = 'processing'
  /// delivery_done → orders.status = 'completed'
  Future<void> syncOrderStatus({
    required String orderId,
    required String dispatchJobStatus,
  }) async {
    try {
      String? orderStatus;

      // Map dispatch job status to order status
      switch (dispatchJobStatus) {
        case 'pickup_done':
          orderStatus = 'processing';
          break;
        case 'delivery_done':
          orderStatus = 'completed';
          break;
        // Other statuses don't trigger order status changes
        default:
          return;
      }

      if (orderStatus != null) {
        await client.from('orders').update({
          'status': orderStatus,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', orderId);
        
        print('✅ Synced order $orderId status to $orderStatus');
      }
    } catch (e) {
      print('❌ Error syncing order status: $e');
      rethrow;
    }
  }

  /// Complete dispatch job action (pickup or delivery) and sync order status
  /// This is the main method riders will call when completing pickup/delivery
  Future<void> completeDispatchJobAction({
    required String dispatchJobId,
    required String orderId,
    required String actionStatus, // 'pickup_done' or 'delivery_done'
  }) async {
    try {
      // Update dispatch job status
      await updateDispatchJobStatus(
        dispatchJobId,
        actionStatus,
        completedAt: DateTime.now(),
      );

      // Sync order status
      await syncOrderStatus(
        orderId: orderId,
        dispatchJobStatus: actionStatus,
      );
      
      print('✅ Completed action $actionStatus for job $dispatchJobId');
    } catch (e) {
      print('❌ Error completing dispatch job action: $e');
      rethrow;
    }
  }
}
