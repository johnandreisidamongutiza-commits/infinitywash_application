import 'package:flutter/material.dart';
import '../../../models/laundry_intake.dart';
import '../../../models/order.dart';
import '../../../services/order_service.dart';
import '../../../services/service_catalog_service.dart';
import '../../../services/supabase_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/order_check_in_form.dart';

class CheckInRequestScreen extends StatefulWidget {
  final LaundryOrder order;

  const CheckInRequestScreen({super.key, required this.order});

  @override
  State<CheckInRequestScreen> createState() {
    print('🔍 CheckInRequestScreen: createState called for order ${order.id}');
    return _CheckInRequestScreenState();
  }
}

class _CheckInRequestScreenState extends State<CheckInRequestScreen> {
  final GlobalKey<OrderCheckInFormState> _formKey = GlobalKey<OrderCheckInFormState>();
  final OrderService _orderService = OrderService();
  final ServiceCatalogService _catalogService = ServiceCatalogService();
  bool _isSubmitting = false;

  // Collapsible section state
  int? _expandedStep = 1; // 1 = Laundry, 2 = Add-ons, null = all collapsed
  
  // Scroll controller & section keys for auto-scroll
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _step1Key = GlobalKey();
  final GlobalKey _step2Key = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Check if laundry section is complete
  bool get _isStep1Complete {
    final form = _formKey.currentState;
    if (form == null) return false;
    return form.isComplete;
  }

  // Get summary text for collapsed sections
  String get _laundrySummary {
    final form = _formKey.currentState;
    if (form == null) return 'Not started';
    final loadCount = form.loads.length;
    final totalWeight = form.totalWeight;
    return '$loadCount load${loadCount == 1 ? '' : 's'} • ${totalWeight.toStringAsFixed(1)}kg total';
  }

  String get _addonsSummary {
    final form = _formKey.currentState;
    if (form == null) return 'None';
    int count = 0;
    if (form.addExtraFabCon) count++;
    if (form.addExtraDetergent) count++;
    return count == 0 ? 'None' : '$count add-on${count == 1 ? '' : 's'}';
  }

  // Auto-scroll to expanded section
  void _scrollToStep(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.endOfFrame.then((_) {
        final ctx = key.currentContext;
        if (!mounted || ctx == null) return;
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          alignment: 0.0,
        );
      });
    });
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.softGray.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildProgressStep(1, 'Laundry', _isStep1Complete),
          Expanded(child: _buildProgressConnector(_isStep1Complete)),
          _buildProgressStep(2, 'Add-ons', false),
          Expanded(child: Container(height: 2, color: Colors.transparent)),
          _buildProgressStep(3, 'Summary', false),
        ],
      ),
    );
  }

  Widget _buildProgressStep(int stepNumber, String label, bool isComplete) {
    Color color;
    if (isComplete) {
      color = Colors.green;
    } else if (stepNumber <= 2) {
      color = AppTheme.accentBlue;
    } else {
      color = AppTheme.textLight.withValues(alpha: 0.3);
    }

    return SizedBox(
      width: 60,
      child: Column(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isComplete ? Colors.green : Colors.transparent,
              border: Border.all(color: color, width: 2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isComplete
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : Text(
                '$stepNumber',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.normal,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressConnector(bool isComplete) {
    return Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: isComplete ? Colors.green : AppTheme.borderGray,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  // Build the fixed order info card (non-collapsible)
  Widget _buildOrderInfoCard() {
    final order = widget.order;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.receipt_long, size: 20, color: AppTheme.accentBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Order Information',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                    ),
                    Text(
                      order.displayNumber,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          _buildInfoRow(Icons.person_outline, 'Customer', order.customerName),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.local_shipping_outlined, 'Collection', order.collectionText),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.home_outlined, 'Return', order.returnText),
          if (order.instructions != null && order.instructions!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildInfoRow(Icons.note_outlined, 'Instructions', order.instructions!),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppTheme.textLight),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: const TextStyle(fontSize: 13, color: AppTheme.textLight, fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
          ),
        ),
      ],
    );
  }

  // Build collapsible laundry section
  Widget _buildLaundrySection() {
    final isExpanded = _expandedStep == 1;

    return Container(
      key: _step1Key,
      clipBehavior: Clip.antiAlias,
      decoration: AppStyles.cardDecoration.copyWith(
        border: Border.all(
          color: isExpanded ? AppTheme.accentBlue.withValues(alpha: 0.3) : AppTheme.borderGray,
          width: isExpanded ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Header - always visible and clickable
          InkWell(
            onTap: () {
              setState(() => _expandedStep = isExpanded ? null : 1);
              if (!isExpanded) _scrollToStep(_step1Key);
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Step indicator
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _isStep1Complete
                          ? Colors.green.withValues(alpha: 0.12)
                          : AppTheme.accentBlue.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: _isStep1Complete
                        ? const Icon(Icons.check, size: 16, color: Colors.green)
                        : const Text('1', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
                  ),
                  const SizedBox(width: 12),

                  // Title and summary
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Laundry Weight & Categories',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                        ),
                        if (!isExpanded && _isStep1Complete) ...[
                          const SizedBox(height: 2),
                          Text(
                            _laundrySummary,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Status indicators
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isStep1Complete)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Complete',
                              style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      const SizedBox(width: 8),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: AppTheme.textLight,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Content - expandable
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OrderCheckInForm(
                key: _formKey,
                onChanged: () => setState(() {}), // Refresh to update summary
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Build collapsible add-ons section
  Widget _buildAddOnsSection() {
    final isExpanded = _expandedStep == 2;

    return Container(
      key: _step2Key,
      clipBehavior: Clip.antiAlias,
      decoration: AppStyles.cardDecoration.copyWith(
        border: Border.all(
          color: isExpanded ? AppTheme.accentBlue.withValues(alpha: 0.3) : AppTheme.borderGray,
          width: isExpanded ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Header - always visible and clickable
          InkWell(
            onTap: () {
              setState(() => _expandedStep = isExpanded ? null : 2);
              if (!isExpanded) _scrollToStep(_step2Key);
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Step indicator
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.accentBlue.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Text('2', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
                  ),
                  const SizedBox(width: 12),

                  // Title and summary
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Optional Add-ons',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                        ),
                        if (!isExpanded) ...[
                          const SizedBox(height: 2),
                          Text(
                            _addonsSummary,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Expand/collapse icon
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppTheme.textLight,
                  ),
                ],
              ),
            ),
          ),

          // Content - expandable (only show add-ons part, form handles laundry)
          if (isExpanded) ...[
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Add-ons are integrated in the laundry section above.',
                style: TextStyle(fontSize: 13, color: AppTheme.textLight, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Build fixed order summary card
  Widget _buildOrderSummary() {
    final form = _formKey.currentState;
    final totalPrice = form?.totalPrice ?? 0.0;
    final loadCount = form?.loads.length ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppStyles.cardDecoration.copyWith(
        color: Colors.green.withValues(alpha: 0.05),
        border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_outlined, size: 20, color: Colors.green),
              SizedBox(width: 8),
              Text(
                'Order Summary',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total ($loadCount load${loadCount == 1 ? '' : 's'})',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              Text(
                '₱${totalPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Confirm Check-in',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _currentEmployeeId() async {
    final currentUser = SupabaseService.currentUser;
    if (currentUser == null) return null;

    final profile = await SupabaseService.client
        .from('profiles')
        .select('id')
        .eq('supabase_user_id', currentUser.id)
        .maybeSingle();
    if (profile == null) return null;

    final employee = await SupabaseService.client
        .from('employees')
        .select('id')
        .eq('profile_id', profile['id'])
        .maybeSingle();
    return employee?['id'] as String?;
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final form = _formKey.currentState;
    if (form == null) return;

    final error = await form.validate();
    if (error != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final result = form.collect();
      final addons = <Map<String, dynamic>>[];

      if (result.extraFabCon) {
        final fabConAddon = await _catalogService.getAddonByName('Extra Fab Con');
        addons.add({
          'addon_id': fabConAddon['id'],
          'addon_name': fabConAddon['addon_name'],
          'quantity': 1,
          'unit_price': (fabConAddon['price'] as num).toDouble(),
          'line_total': (fabConAddon['price'] as num).toDouble(),
        });
      }
      if (result.extraDetergent) {
        final detergentAddon = await _catalogService.getAddonByName('Extra Detergent');
        addons.add({
          'addon_id': detergentAddon['id'],
          'addon_name': detergentAddon['addon_name'],
          'quantity': 1,
          'unit_price': (detergentAddon['price'] as num).toDouble(),
          'line_total': (detergentAddon['price'] as num).toDouble(),
        });
      }

      final staffNotes = [
        if (result.loads.length > 1)
          '${result.loads.length} loads: ${result.loads.map((l) => '${l.weight}${l.unit} ${l.category}').join(', ')}'
        else
          'Load: ${result.loads[0].weight}${result.loads[0].unit} ${result.loads[0].category}',
        if (result.extraFabCon) 'Extra Fab Con (+₱${LaundryIntake.addonPrice.toStringAsFixed(0)})',
        if (result.extraDetergent) 'Extra Detergent (+₱${LaundryIntake.addonPrice.toStringAsFixed(0)})',
        if (result.notes.isNotEmpty) result.notes,
      ].join(' | ');

      await _orderService.checkInExistingOrder(
        orderId: widget.order.id,
        loads: result.loads,
        subtotal: result.subtotal,
        totalAmount: result.subtotal,
        loyaltyCardUid: result.loyaltyCardUid,
        addons: addons,
        staffNotes: staffNotes,
        assignedStaffId: await _currentEmployeeId(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Checked in ${widget.order.displayNumber}: ${result.loads.length} load(s)${result.loyaltyCardUid != null ? ', Card ${result.loyaltyCardUid}' : ''}.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to check in: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🔍 CheckInRequestScreen: Building screen for order ${widget.order.id}');
    final order = widget.order;
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Check in ${order.displayNumber}'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Progress Indicator
              _buildProgressIndicator(),
              const SizedBox(height: 20),
              
              // Order Info Card (Fixed, non-collapsible)
              _buildOrderInfoCard(),
              const SizedBox(height: 16),
              
              // Laundry Section (Collapsible)
              _buildLaundrySection(),
              const SizedBox(height: 16),
              
              // Add-ons Section (Collapsible) - commented out for now since integrated in form
              // _buildAddOnsSection(),
              // const SizedBox(height: 16),
              
              // Order Summary (Fixed)
              _buildOrderSummary(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
