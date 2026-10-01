import 'package:flutter/material.dart';
import '../widgets/map_widget.dart';
import '../config/location_constants.dart';

/// Test Screen - Delivery Area Visualization
/// 
/// Shows the 10km delivery radius around Infinity Wash shop
/// Location: Bubukal, Sta Cruz, Laguna, Philippines
class TestDeliveryAreaScreen extends StatelessWidget {
  const TestDeliveryAreaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Area (10km Radius)'),
        backgroundColor: Colors.green,
      ),
      body: Column(
        children: [
          // Info Card
          Container(
            color: Colors.green.shade50,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      'Infinity Wash Delivery Zone',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.green.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '📍 Shop Location: Bubukal, Sta Cruz, Laguna',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text('🔵 Blue Circle: 10km delivery radius'),
                const SizedBox(height: 4),
                const Text('Lat: 14.2499596, Lng: 121.4027956'),
              ],
            ),
          ),

          // Map
          Expanded(
            child: MapWidget(
              center: LocationConstants.infinityWashShop,
              zoom: 12.0, // Zoom out to see full 10km radius
              showDeliveryRadius: true, // Show the 10km circle
              markers: [
                // Shop Marker
                MapMarkers.createShopMarker(
                  id: 'infinity-wash-shop',
                  position: LocationConstants.infinityWashShop,
                  label: 'Infinity Wash',
                ),
              ],
            ),
          ),

          // Legend
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Legend',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _buildLegendItem(
                  Icons.storefront,
                  Colors.blue,
                  'Shop Location',
                  'Infinity Wash Hub',
                ),
                _buildLegendItem(
                  Icons.circle,
                  Colors.blue.withValues(alpha: 0.3),
                  'Delivery Area',
                  '10km radius from shop',
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Orders within the blue circle are eligible for delivery',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(IconData icon, Color color, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
