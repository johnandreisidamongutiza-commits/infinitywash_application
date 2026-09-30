import 'package:flutter/foundation.dart';
import '../models/dispatch_job.dart';
import '../services/supabase_service.dart';

/// Provider for managing dispatch jobs state
/// Handles fetching, updating, and filtering dispatch jobs
class DispatchJobProvider with ChangeNotifier {
  final SupabaseService _supabaseService = SupabaseService();

  List<DispatchJob> _allJobs = [];
  DispatchJob? _activeJob;
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  List<DispatchJob> get allJobs => _allJobs;
  DispatchJob? get activeJob => _activeJob;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasActiveJob => _activeJob != null;

  /// Get jobs filtered by status
  List<DispatchJob> getJobsByStatus(String status) {
    return _allJobs.where((job) => job.status == status).toList();
  }

  /// Get pending jobs (not started yet)
  List<DispatchJob> get pendingJobs {
    return _allJobs
        .where((job) => job.status == 'pending')
        .toList();
  }

  /// Get in-progress jobs
  List<DispatchJob> get inProgressJobs {
    return _allJobs.where((job) => job.status == 'in_progress').toList();
  }

  /// Fetch dispatch jobs for a specific rider
  Future<void> fetchRiderJobs(String riderId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _allJobs = await _supabaseService.getDispatchJobsByRider(riderId);
      
      // Set active job (first in_progress job, or first pending job)
      _activeJob = _allJobs.firstWhere(
        (job) => job.status == 'in_progress',
        orElse: () {
          // If no in_progress, get first pending
          try {
            return _allJobs.firstWhere(
              (job) => job.status == 'pending',
            );
          } catch (_) {
            // If no pending either, return first job or null
            return _allJobs.isNotEmpty ? _allJobs.first : throw StateError('No jobs');
          }
        },
      );
    } catch (e) {
      if (e is StateError) {
        // No jobs found, this is OK
        _allJobs = [];
        _activeJob = null;
      } else {
        _errorMessage = 'Failed to load jobs: ${e.toString()}';
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch dispatch job for a specific order (customer side)
  Future<void> fetchJobByOrder(String orderId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final job = await _supabaseService.getDispatchJobByOrder(orderId);
      if (job != null) {
        _activeJob = job;
        _allJobs = [job];
      }
    } catch (e) {
      _errorMessage = 'Failed to load delivery info: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update job status
  Future<void> updateJobStatus(String jobId, String newStatus) async {
    try {
      await _supabaseService.updateDispatchJobStatus(jobId, newStatus);
      
      // Update local state
      final index = _allJobs.indexWhere((job) => job.id == jobId);
      if (index != -1) {
        _allJobs[index] = _allJobs[index].copyWith(status: newStatus);
        if (_activeJob?.id == jobId) {
          _activeJob = _allJobs[index];
        }
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Failed to update job: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Set active job manually
  void setActiveJob(DispatchJob? job) {
    _activeJob = job;
    notifyListeners();
  }

  /// Clear all jobs
  void clearJobs() {
    _allJobs = [];
    _activeJob = null;
    _errorMessage = null;
    notifyListeners();
  }
}
