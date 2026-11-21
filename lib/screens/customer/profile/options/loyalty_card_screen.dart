import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';
import '../../../../utils/app_error.dart';
import '../../../../utils/input_formatters.dart';
import '../../../../utils/validators.dart';
import '../../../../services/loyalty_service.dart';
import '../../../../services/customer_service.dart';
import '../../../../widgets/skeleton_loading.dart';

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
  List<LoyaltyHistoryEntry> _history = [];
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
      List<LoyaltyHistoryEntry> history = [];
      if (card != null) {
        history = await _loyaltyService.getPointsHistory(card.cardId, limit: 10);
      }
      
      if (mounted) {
        setState(() {
          _linkedCard = card;
          _history = history;
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
    
    // Charset + length rule (6–20, letters/numbers/hyphen).
    final codeError = Validators.cardUid(code);
    if (codeError != null) {
      _showMessage(codeError, isError: true);
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
          ? const LoyaltyCardScreenSkeleton()
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
          inputFormatters: InputFormatters.uppercaseCardUid,
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

  Widget _buildHowItWorksRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: AppTheme.accentBlue, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: AppTheme.textDark),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                    ],
                  ),
                  if (_linkedCard!.freeLoadsAvailable > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.loyalty_outlined, size: 16, color: Colors.green.shade700),
                          const SizedBox(width: 6),
                          Text(
                            '${_linkedCard!.freeLoadsAvailable} Free Load${_linkedCard!.freeLoadsAvailable > 1 ? "s" : ""}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              // Progress toward next free load
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_linkedCard!.currentPoints % 10) / 10.0,
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _linkedCard!.freeLoadsAvailable > 0
                    ? '${_linkedCard!.pointsToNextRedemption == 0 ? 10 : _linkedCard!.pointsToNextRedemption} more load${(_linkedCard!.pointsToNextRedemption == 0 ? 10 : _linkedCard!.pointsToNextRedemption) > 1 ? "s" : ""} to earn another Free Load'
                    : '${_linkedCard!.pointsToNextRedemption} more load${_linkedCard!.pointsToNextRedemption > 1 ? "s" : ""} to earn your 1st Free Load (10 pts = 1 Free Load)',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
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
        const SizedBox(height: 20),
        
        // How to Redeem Section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.softGray,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderGray),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, color: AppTheme.accentBlue, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'How Free Loads Work',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppTheme.textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildHowItWorksRow('1 completed walk-in load = 1 loyalty point'),
              _buildHowItWorksRow('10 points = 1 Free Load (worth ₱170.00 off your wash)'),
              _buildHowItWorksRow('In-Store: Tap your physical RFID card at the counter when dropping off laundry'),
              _buildHowItWorksRow('Redemption & point earning apply exclusively to in-store walk-in orders'),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Points Activity Ledger
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Points Activity',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 12),
            if (_history.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppTheme.softGray.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderGray),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.history, color: AppTheme.textLight, size: 32),
                    SizedBox(height: 8),
                    Text(
                      'No points activity yet',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textLight,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Complete orders to start earning points!',
                      style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                    ),
                  ],
                ),
              )
            else
              ...List.generate(_history.length, (index) {
                final entry = _history[index];
                final isEarned = entry.transactionType == 'earned';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.borderGray),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isEarned
                              ? Colors.green.withValues(alpha: 0.12)
                              : Colors.orange.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isEarned ? Icons.add : Icons.card_giftcard,
                          size: 16,
                          color: isEarned ? Colors.green : Colors.orange.shade800,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.description.isNotEmpty
                                  ? entry.description
                                  : (isEarned ? 'Points Earned' : 'Points Redeemed'),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${entry.createdAt.month}/${entry.createdAt.day}/${entry.createdAt.year}',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        isEarned ? '+${entry.points} pt${entry.points > 1 ? "s" : ""}' : '${entry.points} pts',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isEarned ? Colors.green : Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ],
    );
  }
}
