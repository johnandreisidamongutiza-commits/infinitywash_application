import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../services/supabase_service.dart';
import '../models/dispatch_job.dart';
import 'dart:async';

/// Provider for managing rider location updates to Supabase
/// Handles periodic location uploads and real-time subscriptions
/// 
/// Phase 12: Tracking Gate Logic
/// - Automatically enables tracking when job status = 'in_progress'
/// - Automatically disables tracking for other statuses
class RiderLocationProvider with ChangeNotifier {
  final SupabaseService _supabaseService = SupabaseService();

  StreamSubscription<LatLng>? _locationSubscription;
  LatLng? _lastUploadedLocation;
  DateTime? _lastUploadTime;
  bool _isUploading = false;
  String? _errorMessage;
  int _uploadCount = 0;
  
  // Phase 12: Current job tracking
  String? _currentJobId;
  String? _currentJobStatus;

  // Configuration
  static const Duration _uploadInterval = Duration(seconds: 30);
  static const double _minimumDistanceMeters = 50.0;

  // Getters
  bool get isUploading => _isUploading;
  String? get errorMessage => _errorMessage;
  LatLng? get lastUploadedLocation => _lastUploadedLocation;
  DateTime? get lastUploadTime => _lastUploadTime;
  int get uploadCount => _uploadCount;
  bool get isTracking => _locationSubscription != null;
  String? get currentJobId => _currentJobId;
  String? get currentJobStatus => _currentJobStatus;
  
  /// Phase 12: Check if tracking should be enabled based on job status
  bool get shouldTrack => _currentJobStatus == 'in_progress';

  /// Phase 12: Update job status and manage tracking automatically
  /// Enables tracking when status = 'in_progress'
  /// Disables tracking for other statuses
  Future<void> updateJobStatus({
    required String jobId,
    required String status,
    required String riderId,
    required String? dispatchJobId,
    required Stream<LatLng> locationStream,
  }) async {
    _currentJobId = jobId;
    _currentJobStatus = status;
    
    print('📊 Job status updated: $status');
    
    // Check if tracking should be enabled/disabled
    if (status == 'in_progress') {
      // Enable tracking
      if (!isTracking) {
        print('✅ Enabling tracking (status: in_progress)');
        await startUploading(
          riderId: riderId,
          dispatchJobId: dispatchJobId,
          locationStream: locationStream,
        );
      }
    } else {
      // Disable tracking
      if (isTracking) {
        print('🛑 Disabling tracking (status: $status)');
        await stopUploading();
      }
    }
    
    notifyListeners();
  }
  
  /// Phase 12: Start tracking for a specific job
  /// Automatically checks if tracking should be enabled based on status
  Future<void> startTrackingForJob({
    required DispatchJob job,
    required String riderId,
    required Stream<LatLng> locationStream,
  }) async {
    await updateJobStatus(
      jobId: job.id,
      status: job.status,
      riderId: riderId,
      dispatchJobId: job.id,
      locationStream: locationStream,
    );
  }

  /// Start uploading rider location to Supabase
  /// Updates every 30 seconds OR 50 meters, whichever comes first
  Future<void> startUploading({
    required String riderId,
    required String? dispatchJobId,
    required Stream<LatLng> locationStream,
  }) async {
    await stopUploading();

    print('📡 Starting location uploads for rider: $riderId');
    _uploadCount = 0;
    _errorMessage = null;
    notifyListeners();

    // Listen to location stream
    _locationSubscription = locationStream.listen(
      (currentLocation) async {
        if (_shouldUpload(currentLocation)) {
          await _uploadLocation(
            riderId: riderId,
            dispatchJobId: dispatchJobId,
            location: currentLocation,
          );
        }
      },
      onError: (error) {
        _errorMessage = 'Location stream error: $error';
        print('❌ Location stream error: $error');
        notifyListeners();
      },
    );
  }

  /// Check if we should upload based on time/distance thresholds
  bool _shouldUpload(LatLng currentLocation) {
    // Always upload if this is the first upload
    if (_lastUploadedLocation == null || _lastUploadTime == null) {
      return true;
    }

    // Check time threshold
    final timeSinceLastUpload = DateTime.now().difference(_lastUploadTime!);
    if (timeSinceLastUpload >= _uploadInterval) {
      print('⏰ Time threshold reached: ${timeSinceLastUpload.inSeconds}s');
      return true;
    }

    // Check distance threshold
    final distance = _calculateDistance(_lastUploadedLocation!, currentLocation);
    if (distance >= _minimumDistanceMeters) {
      print('📏 Distance threshold reached: ${distance.toStringAsFixed(1)}m');
      return true;
    }

    return false;
  }

  /// Upload location to Supabase
  Future<void> _uploadLocation({
    required String riderId,
    required String? dispatchJobId,
    required LatLng location,
  }) async {
    if (_isUploading) return;

    _isUploading = true;
    notifyListeners();

    try {
      await _supabaseService.updateRiderLocation(
        riderId: riderId,
        dispatchJobId: dispatchJobId,
        latitude: location.latitude,
        longitude: location.longitude,
      );

      _lastUploadedLocation = location;
      _lastUploadTime = DateTime.now();
      _uploadCount++;
      _errorMessage = null;
      
      print('✅ Upload #$_uploadCount: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}');
    } catch (e) {
      _errorMessage = 'Failed to upload location: ${e.toString()}';
      print('❌ Upload failed: $e');
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  /// Stop uploading locations
  Future<void> stopUploading() async {
    if (_locationSubscription != null) {
      print('🛑 Stopping location uploads');
      await _locationSubscription?.cancel();
      _locationSubscription = null;
      _lastUploadedLocation = null;
      _lastUploadTime = null;
      _uploadCount = 0;
      notifyListeners();
    }
  }
  
  /// Phase 12: Clear job tracking state
  void clearJobTracking() {
    _currentJobId = null;
    _currentJobStatus = null;
    notifyListeners();
  }

  /// Calculate distance between two points in meters
  double _calculateDistance(LatLng point1, LatLng point2) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Meter, point1, point2);
  }

  /// Subscribe to rider location updates (customer side)
  Stream<LatLng?> subscribeToRiderLocation(String riderId) {
    return _supabaseService.subscribeToRiderLocation(riderId);
  }

  /// Get formatted stats
  String getUploadStats() {
    if (_uploadCount == 0) {
      return 'No uploads yet';
    }
    
    final timeSinceLastUpload = _lastUploadTime != null
        ? DateTime.now().difference(_lastUploadTime!)
        : Duration.zero;
    
    return 'Uploads: $_uploadCount • Last: ${timeSinceLastUpload.inSeconds}s ago';
  }

  @override
  void dispose() {
    stopUploading();
    super.dispose();
  }
}
