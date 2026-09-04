import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class RiderRouteScreen extends StatefulWidget {
  const RiderRouteScreen({super.key});

  @override
  State<RiderRouteScreen> createState() => _RiderRouteScreenState();
}

class _RiderRouteScreenState extends State<RiderRouteScreen> {
  String _currentStatus = 'Idle';
  bool _isPickup = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Navigation'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            _buildActiveTaskCard(),
            const SizedBox(height: 30),
            _buildNavigationMock(),
            const Spacer(),
            if (_currentStatus == 'Idle')
              ElevatedButton(
                onPressed: () => setState(() => _currentStatus = 'On the way'),
                child: const Text('Start Navigation'),
              )
            else if (_currentStatus == 'On the way')
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _currentStatus = 'Idle'),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => setState(() => _currentStatus = 'Arrived'),
                      child: const Text('Mark as Arrived'),
                    ),
                  ),
                ],
              )
            else
              ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(_isPickup ? 'Laundry Picked Up!' : 'Laundry Delivered!')),
                  );
                  setState(() {
                    _currentStatus = 'Idle';
                    _isPickup = !_isPickup;
                  });
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: Text(_isPickup ? 'Confirm Pickup' : 'Confirm Delivery'),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTaskCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isPickup ? AppTheme.errorRed.withOpacity(0.1) : AppTheme.teamMemberIconOrange.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isPickup ? Icons.shopping_bag_outlined : Icons.delivery_dining,
              color: _isPickup ? AppTheme.errorRed : AppTheme.teamMemberIconOrange,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_isPickup ? 'Navigate: Pick-up' : 'Navigate: Delivery', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const Text('Maria Santos • 123 Mango Ave', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: AppTheme.softGray, borderRadius: BorderRadius.circular(12)),
            child: Text(_currentStatus, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationMock() {
    return Container(
      height: 300,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.softGray,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.navigation_outlined, size: 80, color: AppTheme.textLight.withOpacity(0.2)),
            const SizedBox(height: 20),
            const Text('Mock Map View', style: TextStyle(color: AppTheme.textLight, fontWeight: FontWeight.bold)),
            if (_currentStatus == 'On the way')
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Text('Arriving in 5 mins...', style: TextStyle(color: AppTheme.accentBlue, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }
}
