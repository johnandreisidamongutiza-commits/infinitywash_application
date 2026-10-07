import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import '../models/dispatch_job.dart';
import 'order_service.dart';

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

      final jobs = (response as List)
          .map((json) => DispatchJob.fromJson(json as Map<String, dynamic>))
          .toList();
      return await _enrichJobsWithCoordinates(jobs);
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
        final job = DispatchJob.fromJson(response);
        return await _enrichJobCoordinates(job);
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
        final job = DispatchJob.fromJson(response);
        return await _enrichJobCoordinates(job);
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
  ///
  /// [latitude]/[longitude] may be null when the customer never dropped a
  /// map pin — riders then see the address with a "no pin" notice instead of
  /// being routed to a fake fallback location.
  Future<DispatchJob> createDispatchJob({
    required String orderId,
    String? riderId,  // Nullable to allow unassigned jobs
    required String jobType,
    double? latitude,
    double? longitude,
    String? address,
    String? landmark,
    String? customerName,  // Customer full name for display
    String? notes,
    DateTime? scheduledAt,
  }) async {
    try {
      // Generate job number (JOB-YYMMDD-NNN format)
      final jobNumber = await _generateJobNumber();
      
      final data = {
        'job_number': jobNumber,
        'order_id': orderId,
        'rider_id': riderId,  // Can be NULL for unassigned
        'job_type': jobType,
        'status': 'pending',  // Start as pending, becomes assigned when rider accepts
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'landmark': landmark,
        'customer_name': customerName,  // Store customer name
        'notes': notes,
        'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
        'assigned_at': riderId != null ? DateTime.now().toUtc().toIso8601String() : null,
      };
      
      final response = await client
          .from('dispatch_jobs')
          .insert(data)
          .select()
          .single();
      
      print('✅ Created dispatch job: ${response['id']} ($jobNumber) for ${customerName ?? "unknown customer"}');
      return DispatchJob.fromJson(response);
    } catch (e) {
      print('❌ Error creating dispatch job: $e');
      rethrow;
    }
  }
  
  /// Generate unique job number (JOB-YYMMDD-001, up to 999/day)
  Future<String> _generateJobNumber() async {
    try {
      final now = DateTime.now();
      final yy = (now.year % 100).toString().padLeft(2, '0');
      final mm = now.month.toString().padLeft(2, '0');
      final dd = now.day.toString().padLeft(2, '0');
      final dateStr = '$yy$mm$dd';
      final prefix = 'JOB-$dateStr-';
      
      final response = await client
          .from('dispatch_jobs')
          .select('job_number')
          .like('job_number', '$prefix%')
          .order('job_number', ascending: false)
          .limit(1);

      if (response.isEmpty) {
        return '${prefix}001';
      }

      final lastJobNumber = response.first['job_number'] as String;
      final sequencePart = lastJobNumber.replaceAll(prefix, '');
      final lastSequence = int.tryParse(sequencePart) ?? 0;
      final nextSequence = lastSequence + 1;
      
      return '$prefix${nextSequence.toString().padLeft(3, '0')}';
    } catch (e) {
      print('⚠️ Error generating job number: $e');
      // Fallback to timestamp-based
      final now = DateTime.now();
      final yy = (now.year % 100).toString().padLeft(2, '0');
      final mm = now.month.toString().padLeft(2, '0');
      final dd = now.day.toString().padLeft(2, '0');
      return 'JOB-$yy$mm$dd-${(now.millisecondsSinceEpoch % 1000).toString().padLeft(3, '0')}';
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
  /// in_progress (delivery job) → orders.status = 'out_for_delivery'
  Future<void> syncOrderStatus({
    required String orderId,
    required String dispatchJobStatus,
    String? jobType, // Optional: needed for 'in_progress' status to distinguish pickup vs delivery
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
        case 'in_progress':
          // Only update order status if this is a delivery job
          if (jobType == 'delivery') {
            orderStatus = 'out_for_delivery';
          } else {
            // Pickup jobs going in_progress don't change order status
            return;
          }
          break;
        // Other statuses don't trigger order status changes
        default:
          return;
      }

      await client.from('orders').update({
        'status': orderStatus,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderId);
      
      print('✅ Synced order $orderId status to $orderStatus (dispatch job: $dispatchJobStatus, type: $jobType)');
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

      if (actionStatus == 'delivery_done') {
        // Completing a delivery completes the ORDER — and must award loyalty
        // points. OrderService.completeOrder() is the shared, idempotent path
        // used by both staff and rider completions, so points are never lost.
        await OrderService().completeOrder(orderId);
      } else {
        // Sync order status (pickup_done → processing, etc.)
        await syncOrderStatus(
          orderId: orderId,
          dispatchJobStatus: actionStatus,
        );
      }
      
      print('✅ Completed action $actionStatus for job $dispatchJobId');
    } catch (e) {
      print('❌ Error completing dispatch job action: $e');
      rethrow;
    }
  }

  /// Enrich a single dispatch job with coordinates if missing
  Future<DispatchJob> _enrichJobCoordinates(DispatchJob job) async {
    if (job.latitude != null && job.longitude != null) return job;
    try {
      final orderRes = await client
          .from('orders')
          .select('customers(pin_latitude, pin_longitude, first_name, last_name)')
          .eq('id', job.orderId)
          .maybeSingle();
      if (orderRes != null) {
        final cust = orderRes['customers'] as Map<String, dynamic>?;
        final lat = (cust?['pin_latitude'] as num?)?.toDouble();
        final lng = (cust?['pin_longitude'] as num?)?.toDouble();
        final first = cust?['first_name'] as String? ?? '';
        final last = cust?['last_name'] as String? ?? '';
        final fullName = last.isNotEmpty ? '$first $last'.trim() : first;
        if (lat != null && lng != null) {
          client
              .from('dispatch_jobs')
              .update({'latitude': lat, 'longitude': lng})
              .eq('id', job.id)
              .then((_) => print('✅ Auto-healed coordinates for dispatch job ${job.id}'))
              .catchError((_) {});
          return job.copyWith(
            latitude: lat,
            longitude: lng,
            customerName: (job.customerName == null || job.customerName!.trim().isEmpty) && fullName.isNotEmpty
                ? fullName
                : job.customerName,
          );
        }
      }
    } catch (e) {
      print('⚠️ Notice: Could not enrich single job coordinates: $e');
    }
    return job;
  }

  /// Enrich a list of dispatch jobs with coordinates if missing
  Future<List<DispatchJob>> _enrichJobsWithCoordinates(List<DispatchJob> jobs) async {
    final jobsNeedingCoords = jobs.where((j) => j.latitude == null || j.longitude == null).toList();
    if (jobsNeedingCoords.isEmpty) return jobs;

    try {
      final orderIds = jobsNeedingCoords.map((j) => j.orderId).toSet().toList();
      final ordersResponse = await client
          .from('orders')
          .select('''
            id,
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
            client
                .from('dispatch_jobs')
                .update({'latitude': lat, 'longitude': lng})
                .eq('id', job.id)
                .catchError((_) {});
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
      print('⚠️ Notice: Could not enrich jobs coordinates: $e');
      return jobs;
    }
  }

}
