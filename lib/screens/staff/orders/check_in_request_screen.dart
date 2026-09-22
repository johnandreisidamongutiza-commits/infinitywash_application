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
  State<CheckInRequestScreen> createState() => _CheckInRequestScreenState();
}

class _CheckInRequestScreenState extends State<CheckInRequestScreen> {
  final GlobalKey<OrderCheckInFormState> _formKey = GlobalKey<OrderCheckInFormState>();
  final OrderService _orderService = OrderService();
  final ServiceCatalogService _catalogService = ServiceCatalogService();
  bool _isSubmitting = false;

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
    final order = widget.order;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Check in ${order.displayNumber}'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppStyles.cardDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.customerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 6),
                Text(
                  '${order.collectionText} • ${order.returnText}',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textLight),
                ),
                if (order.customerDescription != null && order.customerDescription!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(order.customerDescription!, style: const TextStyle(fontSize: 13)),
                ],
                if (order.instructions != null && order.instructions!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Notes: ${order.instructions}', style: const TextStyle(fontSize: 12, color: AppTheme.textLight)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Laundry & Loyalty Card',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
          ),
          const SizedBox(height: 12),
          OrderCheckInForm(key: _formKey),
          const SizedBox(height: 24),
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
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
