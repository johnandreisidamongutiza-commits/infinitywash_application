import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../widgets/location_picker_widget.dart';
import '../config/location_constants.dart';

/// Test screen for Phase 3: Location Picker Widget
/// 
/// Tests:
/// - Pin drop functionality
/// - Coordinate display
/// - Distance calculation
/// - Delivery range validation
/// - Dialog mode
class TestLocationPickerScreen extends StatefulWidget {
  const TestLocationPickerScreen({super.key});

  @override
  State<TestLocationPickerScreen> createState() => _TestLocationPickerScreenState();
}

class _TestLocationPickerScreenState extends State<TestLocationPickerScreen> {
  LatLng? _selectedLocation;
  String _lastAction = 'No location selected yet';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Picker Test - Phase 3'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Info banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.green.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '✅ Phase 3: Location Picker Test',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Testing: Tap map to drop pin, coordinates returned correctly',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),

          // Location picker widget
          Expanded(
            child: LocationPickerWidget(
              initialPosition: _selectedLocation,
              enforceDeliveryRadius: true,
              showShopMarker: true,
              onLocationChanged: (latLng) {
                setState(() {
                  _selectedLocation = latLng;
                  _lastAction = 'Location selected: ${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';
                });
              },
            ),
          ),

          // Test controls and info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Test Checklist:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _testDialogMode(),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Test Dialog Mode', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildCheckItem('Tap map places green pin'),
                _buildCheckItem('Coordinates display at bottom'),
                _buildCheckItem('Distance from shop shown'),
                _buildCheckItem('Pin turns red if outside delivery radius'),
                _buildCheckItem('Clear button removes pin'),
                _buildCheckItem('Shop button centers on shop'),
                const SizedBox(height: 12),
                
                // Last action indicator
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedLocation != null ? Icons.check_circle : Icons.info_outline,
                        size: 16,
                        color: _selectedLocation != null ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _lastAction,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selectedLocation != null ? _showTestResultDialog : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                    child: Text(
                      _selectedLocation != null
                          ? 'Phase 3 Complete ✓'
                          : 'Select a location first',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.check_box_outline_blank, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _testDialogMode() async {
    final result = await LocationPickerDialog.show(
      context,
      initialPosition: LocationConstants.infinityWashShop,
      enforceDeliveryRadius: true,
      title: 'Select Delivery Location',
    );

    if (result != null) {
      setState(() {
        _selectedLocation = result;
        _lastAction = 'Dialog returned: ${result.latitude.toStringAsFixed(4)}, ${result.longitude.toStringAsFixed(4)}';
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location selected from dialog: ${result.latitude.toStringAsFixed(4)}, ${result.longitude.toStringAsFixed(4)}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      setState(() {
        _lastAction = 'Dialog cancelled';
      });
    }
  }

  void _showTestResultDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('Phase 3 Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Location picker functionality verified!'),
            const SizedBox(height: 16),
            if (_selectedLocation != null) ...[
              const Text(
                'Selected Location:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'Lat: ${_selectedLocation!.latitude.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
              Text(
                'Lng: ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              Text(
                'Distance from shop: ${LocationHelper.getFormattedDistance(_selectedLocation!)}',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: LocationHelper.isWithinDeliveryRange(_selectedLocation!)
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: LocationHelper.isWithinDeliveryRange(_selectedLocation!)
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      LocationHelper.isWithinDeliveryRange(_selectedLocation!)
                          ? Icons.check_circle
                          : Icons.warning_amber,
                      size: 16,
                      color: LocationHelper.isWithinDeliveryRange(_selectedLocation!)
                          ? Colors.green
                          : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        LocationHelper.isWithinDeliveryRange(_selectedLocation!)
                            ? 'Within delivery range ✓'
                            : 'Outside delivery range',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Next steps:\n'
              '• Phase 4: Job marker (hardcoded)\n'
              '• Phase 5: GPS integration\n'
              '• Phase 6: Rider marker',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
