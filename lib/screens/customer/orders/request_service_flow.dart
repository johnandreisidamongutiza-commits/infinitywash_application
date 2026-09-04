import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/custom_text_field.dart';
import 'customer_payment_screen.dart';

class RequestServiceFlow extends StatefulWidget {
  const RequestServiceFlow({super.key});

  @override
  State<RequestServiceFlow> createState() => _RequestServiceFlowState();
}

class _RequestServiceFlowState extends State<RequestServiceFlow> {
  int _currentStep = 1;
  String _serviceType = 'Drop-off';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Request Service'),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _buildStepContent(),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 1: return _buildServiceSelection();
      case 2: return _buildDetailsForm();
      case 3: return _buildWaitingApproval();
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildServiceSelection() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How would you like to proceed?', style: AppTheme.lightTheme.textTheme.headlineMedium),
          const SizedBox(height: 30),
          _buildSelectableCard('Drop-off', 'Bring your laundry to our shop', Icons.store),
          const SizedBox(height: 16),
          _buildSelectableCard('Pick-up', 'We will pick up from your address', Icons.delivery_dining),
          const Spacer(),
          ElevatedButton(
            onPressed: () => setState(() => _currentStep = 2),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectableCard(String title, String subtitle, IconData icon) {
    bool isSelected = _serviceType == title;
    return GestureDetector(
      onTap: () => setState(() => _serviceType = title),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: isSelected ? AppStyles.selectedCardDecoration : AppStyles.cardDecoration,
        child: Row(
          children: [
            Icon(icon, color: isSelected ? AppTheme.accentBlue : AppTheme.textLight, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text(subtitle, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            if (isSelected) const Icon(Icons.check_circle, color: AppTheme.accentBlue),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CustomTextField(label: 'Full Name', hint: 'Enter your name', prefixIcon: Icons.person_outline),
          const SizedBox(height: 20),
          const CustomTextField(label: 'Phone Number', hint: '09XX-XXX-XXXX', prefixIcon: Icons.phone_android),
          const SizedBox(height: 20),
          const CustomTextField(label: 'Address', hint: 'Enter pick-up address', prefixIcon: Icons.location_on_outlined),
          const SizedBox(height: 20),
          Text('Special Instructions', style: AppTheme.lightTheme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'e.g. No fabric softener, delicate items',
              hintStyle: TextStyle(color: AppTheme.textLight.withOpacity(0.5)),
              filled: true,
              fillColor: AppTheme.softGray,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () => setState(() => _currentStep = 3),
            child: const Text('Submit Request'),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingApproval() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppTheme.accentBlue),
            const SizedBox(height: 40),
            Text('Waiting for Approval', style: AppTheme.lightTheme.textTheme.headlineMedium),
            const SizedBox(height: 12),
            const Text(
              'A staff member is reviewing your request. This usually takes less than 2 minutes.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const CustomerPaymentScreen()),
                );
              },
              child: const Text('Proceed to Payment (Demo)'),
            ),
          ],
        ),
      ),
    );
  }
}
