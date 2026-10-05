import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';
import '../../../../utils/app_error.dart';
import '../../../../services/loyalty_service.dart';
import '../../../../services/customer_service.dart';

class CustomerLoyaltyCardScreen extends StatefulWidget {
  const CustomerLoyaltyCardScreen({super.key});

  @override
  State<CustomerLoyaltyCardScreen> createState() => _CustomerLoyaltyCardScreenState();
}

class _CustomerLoyaltyCardScreenState extends State<CustomerLoyaltyCardScreen> {
  final LoyaltyService _loyaltyService = LoyaltyService();
  final CustomerService _customerService = CustomerService();
  final TextEditingController _cardCodeController = TextEditingController();
  
  LoyaltyCardInfo? _linkedCard;
  bool _isLoading = true;
  bool _isLinking = false;

  @override
  void initState() {
    super.initState();
    _loadLinkedCard();
  }

  @override
  void dispose() {
    _cardCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadLinkedCard() async {
    setState(() => _isLoading = true);
    
    try {
      final customerId = await _customerService.getCurrentAuthenticatedCustomerId();
      final card = await _loyaltyService.getLinkedCard(customerId);
      
      if (mounted) {
        setState(() {
          _linkedCard = card;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading linked card: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _linkCard() async {
    final code = _cardCodeController.text.trim().toUpperCase();
    
    if (code.isEmpty) {
      _showMessage('Please enter a card code', isError: true);
      return;
    }
    
    setState(() => _isLinking = true);
    
    try {
      final customerId = await _customerService.getCurrentAuthenticatedCustomerId();
      await _loyaltyService.linkCardToCustomer(
        cardUid: code,
        customerId: customerId,
      );
      
      _showMessage('Loyalty card linked successfully!', isError: false);
      _cardCodeController.clear();
      await _loadLinkedCard();
    } catch (e) {
      _showMessage(mapErrorToMessage(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLinking = false);
      }
    }
  }

  Future<void> _unlinkCard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Unlink Loyalty Card?'),
        content: const Text('Are you sure you want to unlink this loyalty card? You can re-link it later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      try {
        await _loyaltyService.unlinkCard(_linkedCard!.uid);
        _showMessage('Card unlinked successfully', isError: false);
        await _loadLinkedCard();
      } catch (e) {
        _showMessage(mapErrorToMessage(e), isError: true);
      }
    }
  }

  void _showMessage(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Loyalty Card'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_linkedCard == null) ...[
                    _buildLinkCardSection(),
                  ] else ...[
                    _buildLinkedCardSection(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildLinkCardSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.softGray,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.card_membership_outlined,
              size: 60,
              color: AppTheme.accentBlue,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Link Your Loyalty Card',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter the code printed on your physical loyalty card to start earning points.',
          style: TextStyle(fontSize: 14, color: AppTheme.textLight),
        ),
        const SizedBox(height: 24),
        
        // Card Code Input
        TextField(
          controller: _cardCodeController,
          decoration: InputDecoration(
            labelText: 'Card Code',
            hintText: 'e.g., RFID-0001',
            prefixIcon: const Icon(Icons.qr_code),
            filled: true,
            fillColor: AppTheme.softGray,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          textCapitalization: TextCapitalization.characters,
          enabled: !_isLinking,
        ),
        const SizedBox(height: 16),
        
        // Link Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLinking ? null : _linkCard,
            child: _isLinking
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Link Card'),
          ),
        ),
        const SizedBox(height: 24),
        
        // Info Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.accentBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, color: AppTheme.accentBlue, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'How it works',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildInfoRow('Earn 1 point for every load completed'),
              _buildInfoRow('Points are automatically added to your account'),
              _buildInfoRow('Redeem points for discounts and rewards'),
              _buildInfoRow('Track your points anytime in this screen'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: AppTheme.accentBlue)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildLinkedCardSection() {
    return Column(
      children: [
        // Card Display
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.accentBlue, AppTheme.accentBlue.withValues(alpha: 0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentBlue.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
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
                    'LOYALTY CARD',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'POINTS BALANCE',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_linkedCard!.currentPoints}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CARD NUMBER',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _linkedCard!.uid,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'TOTAL LOADS',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_linkedCard!.totalLoadsCompleted}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        
        // Info Section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade700, size: 24),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Your loyalty card is linked! Points will be automatically added when you complete orders.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        
        // Unlink Button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _unlinkCard,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
            child: const Text('Unlink Card'),
          ),
        ),
      ],
    );
  }
}
