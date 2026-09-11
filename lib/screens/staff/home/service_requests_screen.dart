import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import '../../../services/mock_data_service.dart';

class ServiceRequestsScreen extends StatefulWidget {
  const ServiceRequestsScreen({super.key});

  @override
  State<ServiceRequestsScreen> createState() => _ServiceRequestsScreenState();
}

class _ServiceRequestsScreenState extends State<ServiceRequestsScreen> {
  @override
  Widget build(BuildContext context) {
    final requests = MockDataService().pendingRequests;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Online Requests'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: requests.isEmpty
          ? _buildEmptyState()
          : ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: requests.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) => _buildRequestCard(requests[index]),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.online_prediction, size: 80, color: AppTheme.textLight.withOpacity(0.2)),
          const SizedBox(height: 16),
          const Text('No pending online requests', style: TextStyle(color: AppTheme.textLight)),
        ],
      ),
    );
  }

  Widget _buildRequestCard(LaundryOrder request) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(request.id, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
              Row(
                children: [
                  _buildBadge(request.collectionText, AppTheme.accentBlue),
                  const SizedBox(width: 6),
                  _buildBadge(request.returnText, Colors.green),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(request.customerName, style: AppTheme.lightTheme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (request.instructions != null && request.instructions!.isNotEmpty)
            Text(
              'Note: ${request.instructions}',
              style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      MockDataService().declineRequest(request.id);
                    });
                  },
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.errorRed, side: const BorderSide(color: AppTheme.errorRed)),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _showApproveDialog(request),
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showApproveDialog(LaundryOrder request) {
    final weightController = TextEditingController(text: '5.0');
    String? selectedRfidTag;
    String selectedCategory = 'Regular Clothing';
    final availableTags = MockDataService().availableRfidTags;

    final Map<String, double> categoryLimits = {
      'Regular Clothing': 8.0,
      'Heavy Clothing': 6.0,
      'Beddings & Towels': 5.0,
      'Heavy Bedding': 1.0,
    };

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final double weight = double.tryParse(weightController.text) ?? 0.0;
          final double limit = categoryLimits[selectedCategory]!;
          final bool isOver = weight > limit;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Accept & Verify Request', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Confirm scale weight, category, and RFID tag to send bill to customer.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
                  const SizedBox(height: 16),

                  // Category Dropdown
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Laundry Category',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: categoryLimits.entries.map((e) {
                      return DropdownMenuItem<String>(
                        value: e.key,
                        child: Text('${e.key} (≤ ${e.value.toStringAsFixed(0)} ${e.key == 'Heavy Bedding' ? 'pc' : 'kg'})',
                            style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedCategory = val);
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  // Scale Weight Input
                  TextField(
                    controller: weightController,
                    keyboardType: TextInputType.number,
                    onChanged: (v) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Scale Weight (kg)',
                      border: const OutlineInputBorder(),
                      suffixIcon: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Text(
                          isOver ? 'EXCEEDS' : 'OK',
                          style: TextStyle(
                            color: isOver ? Colors.red : Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (isOver)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Limit is $limit kg for this category.',
                          style: const TextStyle(fontSize: 10, color: Colors.red)),
                    ),

                  const SizedBox(height: 14),

                  // RFID Tag
                  if (availableTags.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.errorRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: AppTheme.errorRed, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No RFID tags available',
                              style: TextStyle(color: AppTheme.errorRed, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: selectedRfidTag,
                      decoration: const InputDecoration(
                        labelText: 'Assign RFID Tag',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.nfc_outlined),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: availableTags.map((tag) {
                        return DropdownMenuItem<String>(
                          value: tag,
                          child: Text(tag, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedRfidTag = value);
                      },
                    ),

                  const SizedBox(height: 18),

                  // Official ₱170 Bill Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.softGray,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Full Service (Wash, Dry, Fold):', style: TextStyle(fontSize: 12, color: AppTheme.textDark)),
                            Text('₱170.00', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Detergent + Fab Con:', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
                            Text('INCLUDED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                        SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Pick Up & Delivery:', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
                            Text('INCLUDED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                        Divider(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total Bill Sent to App:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            Text('₱170.00', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: (selectedRfidTag == null || availableTags.isEmpty)
                    ? null
                    : () {
                        final double verifiedWeight = double.tryParse(weightController.text) ?? 1.0;
                        setState(() {
                          MockDataService().approveRequest(request.id, verifiedWeight, selectedRfidTag!);
                        });
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Order #${request.id} accepted! ₱170.00 bill sent to customer.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                child: const Text('Accept & Push Bill (₱170.00)'),
              ),
            ],
          );
        },
      ),
    );
  }
}
