import 'package:flutter/material.dart';
import 'package:location/location.dart';
import '../services/location_service.dart';
import 'dart:async';

/// Test screen for Phase 5: GPS Integration
/// 
/// Tests:
/// - Permission request flow
/// - Service enabled check
/// - Current location retrieval
/// - Location updates stream
/// - Error handling (denied, disabled, timeout)
class TestGpsScreen extends StatefulWidget {
  const TestGpsScreen({super.key});

  @override
  State<TestGpsScreen> createState() => _TestGpsScreenState();
}

class _TestGpsScreenState extends State<TestGpsScreen> {
  final LocationService _locationService = LocationService();
  
  LocationData? _currentLocation;
  bool _isTracking = false;
  bool _hasPermission = false;
  bool _isServiceEnabled = false;
  String _statusMessage = 'Not initialized';
  List<String> _locationLog = [];
  int _updateCount = 0;

  @override
  void initState() {
    super.initState();
    _checkInitialStatus();
  }

  @override
  void dispose() {
    _locationService.stopLocationUpdates();
    super.dispose();
  }

  Future<void> _checkInitialStatus() async {
    setState(() {
      _statusMessage = 'Checking GPS status...';
    });

    try {
      _hasPermission = await _locationService.hasPermission();
      _isServiceEnabled = await _locationService.isServiceEnabled();
      
      setState(() {
        _statusMessage = 'Ready to test';
        _addLog('✅ Initial check complete');
        _addLog('Permission: ${_hasPermission ? "✓ Granted" : "✗ Not granted"}');
        _addLog('Service: ${_isServiceEnabled ? "✓ Enabled" : "✗ Disabled"}');
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
        _addLog('❌ Error checking status: $e');
      });
    }
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    setState(() {
      _locationLog.insert(0, '[$timestamp] $message');
      if (_locationLog.length > 20) {
        _locationLog = _locationLog.sublist(0, 20);
      }
    });
  }

  Future<void> _testRequestPermission() async {
    setState(() {
      _statusMessage = 'Requesting permission...';
    });
    
    _addLog('🔑 Requesting location permission...');
    
    try {
      final granted = await _locationService.requestPermission();
      setState(() {
        _hasPermission = granted;
        _statusMessage = granted ? 'Permission granted' : 'Permission denied';
      });
      _addLog(granted ? '✅ Permission granted' : '❌ Permission denied');
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
      });
      _addLog('❌ Error requesting permission: $e');
    }
  }

  Future<void> _testEnableService() async {
    setState(() {
      _statusMessage = 'Requesting service...';
    });
    
    _addLog('📡 Requesting location service...');
    
    try {
      final enabled = await _locationService.requestService();
      setState(() {
        _isServiceEnabled = enabled;
        _statusMessage = enabled ? 'Service enabled' : 'Service disabled';
      });
      _addLog(enabled ? '✅ Service enabled' : '❌ Service disabled');
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
      });
      _addLog('❌ Error requesting service: $e');
    }
  }

  Future<void> _testGetCurrentLocation() async {
    setState(() {
      _statusMessage = 'Getting current location...';
    });
    
    _addLog('📍 Getting current location...');
    
    try {
      final location = await _locationService.getCurrentLocation();
      
      if (location != null) {
        setState(() {
          _currentLocation = location;
          _statusMessage = 'Location obtained';
        });
        _addLog('✅ Got location: ${location.latitude?.toStringAsFixed(6)}, ${location.longitude?.toStringAsFixed(6)}');
        _addLog('   Accuracy: ${location.accuracy?.toStringAsFixed(1)}m');
        _addLog('   Speed: ${location.speed?.toStringAsFixed(1)}m/s');
      } else {
        setState(() {
          _statusMessage = 'Failed to get location';
        });
        _addLog('❌ Failed to get location');
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
      });
      _addLog('❌ Error getting location: $e');
    }
  }

  Future<void> _testStartTracking() async {
    if (_isTracking) {
      setState(() {
        _statusMessage = 'Stopping tracking...';
      });
      _addLog('🛑 Stopping location tracking...');
      
      await _locationService.stopLocationUpdates();
      
      setState(() {
        _isTracking = false;
        _statusMessage = 'Tracking stopped';
      });
      _addLog('✅ Tracking stopped');
      return;
    }

    setState(() {
      _statusMessage = 'Starting tracking...';
      _updateCount = 0;
    });
    
    _addLog('📡 Starting location tracking...');
    
    try {
      await _locationService.startLocationUpdates(
        (locationData) {
          setState(() {
            _currentLocation = locationData;
            _updateCount++;
          });
          _addLog('📍 Update #$_updateCount: ${locationData.latitude?.toStringAsFixed(6)}, ${locationData.longitude?.toStringAsFixed(6)}');
        },
        intervalMillis: 5000, // 5 seconds
        distanceFilterMeters: 10, // 10 meters
      );
      
      setState(() {
        _isTracking = true;
        _statusMessage = 'Tracking active';
      });
      _addLog('✅ Tracking started (5s interval, 10m distance filter)');
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
      });
      _addLog('❌ Error starting tracking: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS Test - Phase 5'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Info banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.purple.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '✅ Phase 5: GPS Integration Test',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Testing: Permissions, service checks, location updates, error handling',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),

          // Status indicators
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatusCard(
                    'Permission',
                    _hasPermission ? 'Granted' : 'Not Granted',
                    _hasPermission ? Colors.green : Colors.red,
                    Icons.security,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatusCard(
                    'GPS Service',
                    _isServiceEnabled ? 'Enabled' : 'Disabled',
                    _isServiceEnabled ? Colors.green : Colors.red,
                    Icons.gps_fixed,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatusCard(
                    'Tracking',
                    _isTracking ? 'Active' : 'Stopped',
                    _isTracking ? Colors.blue : Colors.grey,
                    Icons.my_location,
                  ),
                ),
              ],
            ),
          ),

          // Current location display
          if (_currentLocation != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Current Location',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      if (_isTracking) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Updates: $_updateCount',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Lat: ${_currentLocation!.latitude?.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                  Text(
                    'Lng: ${_currentLocation!.longitude?.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                  if (_currentLocation!.accuracy != null)
                    Text(
                      'Accuracy: ±${_currentLocation!.accuracy!.toStringAsFixed(1)}m',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Test buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Test Actions:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _testRequestPermission,
                        icon: const Icon(Icons.security, size: 16),
                        label: const Text('Permission', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _testEnableService,
                        icon: const Icon(Icons.gps_fixed, size: 16),
                        label: const Text('Service', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _testGetCurrentLocation,
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text('Get Current Location'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _testStartTracking,
                  icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow, size: 18),
                  label: Text(_isTracking ? 'Stop Tracking' : 'Start Tracking'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isTracking ? Colors.red : Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Log
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Activity Log',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _locationLog.clear();
                            });
                          },
                          child: const Text('Clear', style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _locationLog.isEmpty
                        ? const Center(
                            child: Text(
                              'No activity yet',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _locationLog.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  _locationLog[index],
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          Text(
            value,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
