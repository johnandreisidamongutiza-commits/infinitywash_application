import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  bool _isOnline = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 30),
              _buildDeliveriesSummary(),
              const SizedBox(height: 30),
              _buildRouteSection(),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 80),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.play_arrow, size: 30),
                    const SizedBox(width: 12),
                    Text('Start Route', style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(color: Colors.white, fontSize: 20)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: AppTheme.softGray,
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(4),
          child: ClipOval(
            child: Image.asset(
              'assets/images/logo.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.person),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Infinity Wash', style: AppTheme.lightTheme.textTheme.titleMedium),
            const Text('RIDER', style: TextStyle(color: AppTheme.accentBlue, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _isOnline ? Colors.green.withOpacity(0.1) : AppTheme.textLight.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _isOnline ? Colors.green : AppTheme.textLight,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(_isOnline ? 'Online' : 'Offline', style: TextStyle(color: _isOnline ? Colors.green : AppTheme.textLight, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(width: 8),
              Switch(
                value: _isOnline,
                onChanged: (value) => setState(() => _isOnline = value),
                activeColor: Colors.white,
                activeTrackColor: AppTheme.accentBlue,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveriesSummary() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppStyles.cardDecoration,
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, color: AppTheme.errorRed, size: 20),
              const SizedBox(width: 12),
              Text('Today\'s Deliveries', style: AppTheme.lightTheme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppTheme.errorRed.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.shopping_bag_outlined, color: AppTheme.errorRed),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('8', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
                        Text('Total Stops', style: TextStyle(color: AppTheme.textLight, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 40, color: AppTheme.borderGray),
              Expanded(
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppTheme.teamMemberIconOrange.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.location_on_outlined, color: AppTheme.teamMemberIconOrange),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('24.5', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
                        Text('Total Distance', style: TextStyle(color: AppTheme.textLight, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRouteSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppStyles.cardDecoration,
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.route_outlined, color: AppTheme.accentBlue, size: 20),
              const SizedBox(width: 12),
              Text('Today\'s Route', style: AppTheme.lightTheme.textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () {},
                child: const Row(
                  children: [
                    Text('View Map', style: TextStyle(color: AppTheme.accentBlue)),
                    Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.accentBlue),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Mock Map Area
          Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.softGray,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderGray),
            ),
            child: Icon(Icons.map_outlined, size: 60, color: AppTheme.textLight.withOpacity(0.1)),
          ),
          const SizedBox(height: 24),
          _buildRouteStop('1', 'Maria Santos', '123 Mango Ave, Cebu City', 'Pickup', '09:00 AM', AppTheme.errorRed),
          _buildRouteStop('2', 'Juan Dela Cruz', '456 Banilad Rd, Cebu City', 'Drop-off', '10:15 AM', AppTheme.teamMemberIconOrange),
          _buildRouteStop('3', 'Ana Reyes', '789 Parkmall, Mandaue City', 'Pickup', '11:30 AM', AppTheme.errorRed),
        ],
      ),
    );
  }

  Widget _buildRouteStop(String number, String name, String address, String type, String time, Color typeColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(color: AppTheme.accentBlue, shape: BoxShape.circle),
            child: Center(child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(address, style: TextStyle(color: AppTheme.textLight, fontSize: 10), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: typeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(type, style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Text(time, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
