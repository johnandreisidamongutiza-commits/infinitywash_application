import 'package:flutter/material.dart';
import '../models/laundry_intake.dart';
import '../models/order.dart';
import '../services/rfid_service.dart';
import '../theme/app_theme.dart';

class OrderCheckInForm extends StatefulWidget {
  const OrderCheckInForm({
    super.key,
    this.onChanged,
  });

  final VoidCallback? onChanged;

  @override
  State<OrderCheckInForm> createState() => OrderCheckInFormState();
}

class OrderCheckInFormState extends State<OrderCheckInForm> {
  final RfidService _rfidService = RfidService();
  final TextEditingController notesController = TextEditingController();
  final List<LoadDraft> _loads = [LoadDraft(initialWeight: '5.0')];

  List<String> _availableRfidTags = [];
  bool _loadingRfidTags = false;
  String? _selectedRfidTag;
  bool _addExtraFabCon = false;
  bool _addExtraDetergent = false;

  @override
  void initState() {
    super.initState();
    _loadAvailableRfidTags();
  }

  @override
  void dispose() {
    notesController.dispose();
    for (final load in _loads) {
      load.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAvailableRfidTags() async {
    setState(() => _loadingRfidTags = true);
    try {
      final tags = await _rfidService.getAvailableRfidTags();
      if (!mounted) return;
      setState(() {
        _availableRfidTags = tags;
        _loadingRfidTags = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _availableRfidTags = [];
        _loadingRfidTags = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading RFID tags: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _notifyChanged() => widget.onChanged?.call();

  void _addLoad() {
    setState(() => _loads.add(LoadDraft()));
    _notifyChanged();
  }

  void _removeLoad(int index) {
    if (_loads.length <= 1) return;
    setState(() {
      _loads[index].dispose();
      _loads.removeAt(index);
    });
    _notifyChanged();
  }

  double get _totalWeight =>
      _loads.fold(0.0, (sum, load) => sum + LaundryIntake.weightOf(load));

  double get _totalPrice =>
      (LaundryIntake.basePricePerLoad * _loads.length) +
      (_addExtraFabCon ? LaundryIntake.addonPrice : 0) +
      (_addExtraDetergent ? LaundryIntake.addonPrice : 0);

  bool get isComplete =>
      _selectedRfidTag != null &&
      _loads.isNotEmpty &&
      _loads.every((load) => LaundryIntake.weightOf(load) > 0);

  Future<String?> validate() async {
    if (_selectedRfidTag == null || _availableRfidTags.isEmpty) {
      return 'Please select an RFID tag before confirming.';
    }
    if (_loads.isEmpty) return 'Please add at least one load.';
    for (int i = 0; i < _loads.length; i++) {
      final weight = LaundryIntake.weightOf(_loads[i]);
      if (weight <= 0) {
        return 'Load ${i + 1} must have a weight greater than 0.';
      }
      if (weight > 50) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm Weight'),
            content: Text('Load ${i + 1} has ${weight}kg. Is this correct? This seems unusually high.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
            ],
          ),
        );
        if (confirmed != true) return 'Check-in cancelled.';
      }
    }
    final stillAvailable = await _rfidService.isRfidTagAvailable(_selectedRfidTag!);
    if (!stillAvailable) {
      await _loadAvailableRfidTags();
      setState(() => _selectedRfidTag = null);
      return 'RFID tag is no longer available. Please select another tag.';
    }
    return null;
  }

  CheckInFormResult collect() {
    return CheckInFormResult(
      loads: LaundryIntake.toOrderLoads(_loads),
      rfidTag: _selectedRfidTag!,
      extraFabCon: _addExtraFabCon,
      extraDetergent: _addExtraDetergent,
      notes: notesController.text.trim(),
    );
  }

  void _showAutoSplitDialog(int loadIndex) {
    final load = _loads[loadIndex];
    final weight = LaundryIntake.weightOf(load);
    final limit = LaundryIntake.limitOf(load.category);
    final unit = LaundryIntake.unitOf(load.category);
    if (weight <= limit) return;

    final suggestedLoads = (weight / limit).ceil();
    final weightPerLoad = weight / suggestedLoads;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text('Weight Exceeds Limit', style: TextStyle(fontSize: 17)),
          ],
        ),
        content: Text(
          'Split into $suggestedLoads loads × ${weightPerLoad.toStringAsFixed(1)} $unit each '
          '(₱${(LaundryIntake.basePricePerLoad * suggestedLoads).toStringAsFixed(0)}).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep Single Load')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                load.weightController.text = weightPerLoad.toStringAsFixed(1);
                for (int i = 1; i < suggestedLoads; i++) {
                  _loads.add(LoadDraft(
                    category: load.category,
                    initialWeight: weightPerLoad.toStringAsFixed(1),
                  ));
                }
              });
              _notifyChanged();
            },
            child: const Text('Auto-Split'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(_loads.length, _buildLoadCard),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: _addLoad,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Another Load', style: TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                side: BorderSide(color: AppTheme.accentBlue.withValues(alpha: 0.5)),
              ),
            ),
          ],
        ),
        const Divider(height: 24),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.accentBlue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Weight:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text(
                '${_totalWeight.toStringAsFixed(1)}kg across ${_loads.length} load(s)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.accentBlue),
              ),
            ],
          ),
        ),
        const Divider(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.nfc_outlined, size: 16, color: AppTheme.accentBlue),
                SizedBox(width: 6),
                Text(
                  'RFID Tag Assignment (Shared)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _availableRfidTags.isEmpty
                    ? AppTheme.errorRed.withValues(alpha: 0.1)
                    : AppTheme.accentBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_availableRfidTags.length} Available',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _availableRfidTags.isEmpty ? AppTheme.errorRed : AppTheme.accentBlue,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _selectedRfidTag,
          hint: Text(
            _loadingRfidTags
                ? 'Loading RFID tags...'
                : _availableRfidTags.isEmpty
                    ? 'No RFID tags available'
                    : 'Select RFID Tag',
            style: const TextStyle(fontSize: 13),
          ),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.borderGray),
            ),
          ),
          items: _loadingRfidTags
              ? []
              : _availableRfidTags
                  .map((tag) => DropdownMenuItem(value: tag, child: Text(tag, style: const TextStyle(fontSize: 13))))
                  .toList(),
          onChanged: (_loadingRfidTags || _availableRfidTags.isEmpty)
              ? null
              : (value) {
                  setState(() => _selectedRfidTag = value);
                  _notifyChanged();
                },
        ),
        const Divider(height: 24),
        const Text(
          'Optional Add-ons',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _addExtraFabCon,
          onChanged: (value) {
            setState(() => _addExtraFabCon = value ?? false);
            _notifyChanged();
          },
          title: const Text('Extra Fabric Conditioner', style: TextStyle(fontSize: 13)),
          subtitle: Text(
            '+₱${LaundryIntake.addonPrice.toStringAsFixed(0)}.00',
            style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
          ),
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: AppTheme.accentBlue,
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _addExtraDetergent,
          onChanged: (value) {
            setState(() => _addExtraDetergent = value ?? false);
            _notifyChanged();
          },
          title: const Text('Extra Detergent', style: TextStyle(fontSize: 13)),
          subtitle: Text(
            '+₱${LaundryIntake.addonPrice.toStringAsFixed(0)}.00',
            style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
          ),
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: AppTheme.accentBlue,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: notesController,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Staff notes from check-in (optional)',
            hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textLight),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total (${_loads.length} load${_loads.length == 1 ? '' : 's'})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                '₱${_totalPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoadCard(int index) {
    final load = _loads[index];
    final isOver = LaundryIntake.isOverLimit(load);
    final weight = LaundryIntake.weightOf(load);
    final limit = LaundryIntake.limitOf(load.category);
    final unit = LaundryIntake.unitOf(load.category);
    final categoriesList = LaundryIntake.categories.entries.toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.softGray.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Load ${index + 1} of ${_loads.length}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
              ),
              if (_loads.length > 1)
                InkWell(
                  onTap: () => _removeLoad(index),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.close, size: 16, color: Colors.red),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text('Category:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLight)),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 2.2,
            children: [
              for (final entry in categoriesList) _buildCategoryTile(entry, load),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Weight:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: load.weightController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) {
                    setState(() {});
                    _notifyChanged();
                  },
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: '5.0',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(unit, style: const TextStyle(fontSize: 13, color: AppTheme.textLight, fontWeight: FontWeight.w500)),
              const Spacer(),
              if (weight > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isOver ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isOver ? Colors.red : Colors.green, width: 1.5),
                  ),
                  child: Text(
                    isOver ? 'Over' : 'OK',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isOver ? Colors.red : Colors.green),
                  ),
                ),
            ],
          ),
          if (isOver) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Exceeds ${limit.toStringAsFixed(1)} $unit limit by ${(weight - limit).toStringAsFixed(1)} $unit',
                    style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.w500),
                  ),
                ),
                TextButton(
                  onPressed: () => _showAutoSplitDialog(index),
                  child: const Text('Auto-Split', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryTile(MapEntry<String, Map<String, dynamic>> entry, LoadDraft load) {
    final isSelected = load.category == entry.key;
    return InkWell(
      onTap: () {
        setState(() => load.category = entry.key);
        _notifyChanged();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentBlue.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.accentBlue : AppTheme.borderGray.withValues(alpha: 0.4),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            entry.key,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isSelected ? AppTheme.accentBlue : AppTheme.textDark,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
