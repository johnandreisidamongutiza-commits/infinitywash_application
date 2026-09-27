import 'package:flutter/material.dart';

/// Customer Loyalty Card Screen
/// Shows customer loyalty points and rewards
class CustomerLoyaltyCardScreen extends StatelessWidget {
  const CustomerLoyaltyCardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loyalty Card'),
        backgroundColor: Colors.purple,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Loyalty Card
            Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.purple, Colors.deepPurple],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Infinity Wash',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Loyalty Member',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Points Balance',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '0',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Member since',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          DateTime.now().year.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // How to Earn Points
            const Text(
              'How to Earn Points',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildPointsInfo(
                      icon: Icons.shopping_bag,
                      title: 'Complete Orders',
                      description: 'Earn 1 point for every ₱100 spent',
                    ),
                    const Divider(),
                    _buildPointsInfo(
                      icon: Icons.stars,
                      title: 'Leave Reviews',
                      description: 'Earn 10 points for each review',
                    ),
                    const Divider(),
                    _buildPointsInfo(
                      icon: Icons.card_giftcard,
                      title: 'Referrals',
                      description: 'Earn 50 points for each referral',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Rewards
            const Text(
              'Available Rewards',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: Icon(Icons.local_offer, color: Colors.white),
                ),
                title: const Text('10% Discount'),
                subtitle: const Text('Requires 100 points'),
                trailing: ElevatedButton(
                  onPressed: null, // Disabled for now
                  child: const Text('Redeem'),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.card_giftcard, color: Colors.white),
                ),
                title: const Text('Free Delivery'),
                subtitle: const Text('Requires 50 points'),
                trailing: ElevatedButton(
                  onPressed: null, // Disabled for now
                  child: const Text('Redeem'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPointsInfo({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.purple.shade100,
            child: Icon(icon, color: Colors.purple),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
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
