import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/input_formatters.dart';
import '../../../utils/validators.dart';
import '../../../widgets/custom_text_field.dart';
import '../../../models/supply.dart';

enum ManageSupplyMode { add, update }

class ManageSupplyScreen extends StatefulWidget {
  final ManageSupplyMode mode;
  final Supply? supply;

  const ManageSupplyScreen({super.key, required this.mode, this.supply});

  @override
  State<ManageSupplyScreen> createState() => _ManageSupplyScreenState();
}

class _ManageSupplyScreenState extends State<ManageSupplyScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _unitController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.mode == ManageSupplyMode.update && widget.supply != null) {
      _nameController.text = widget.supply!.name;
      _amountController.text = widget.supply!.currentAmount.toString();
      _unitController.text = widget.supply!.unit;
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isUpdate = widget.mode == ManageSupplyMode.update;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(isUpdate ? 'Update Supply' : 'Add Supply'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              CustomTextField(
                label: 'Supply Name',
                hint: 'e.g., Liquid Detergent',
                prefixIcon: Icons.inventory_2_outlined,
                controller: _nameController,
                validator: Validators.supplyName,
                maxLength: Validators.supplyNameMax,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 20),
              CustomTextField(
                label: isUpdate ? 'Current Amount' : 'Initial Amount',
                hint: 'e.g., 5.0',
                prefixIcon: Icons.add_circle_outline,
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: Validators.supplyAmount,
                inputFormatters: InputFormatters.decimal(maxDecimals: 2, maxLength: 10),
              ),
              const SizedBox(height: 20),
              CustomTextField(
                label: 'Unit',
                hint: 'e.g., L or units',
                prefixIcon: Icons.straighten_outlined,
                controller: _unitController,
                validator: Validators.supplyUnit,
                maxLength: Validators.supplyUnitMax,
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _submit,
                child: Text(isUpdate ? 'Confirm Update' : 'Confirm Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;

    final bool isUpdate = widget.mode == ManageSupplyMode.update;

    // Mock logic for notification check
    double amount = double.tryParse(_amountController.text) ?? 0;
    if (isUpdate && widget.supply != null) {
      if (amount < widget.supply!.maxAmount * 0.2) {
        _showLowStockNotification();
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Supply ${isUpdate ? 'Updated' : 'Added'} Successfully!')),
    );
    Navigator.pop(context);
  }

  void _showLowStockNotification() {
    // In a real app, this would be a push notification or an admin alert.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('NOTICE: Supply is low! Admin has been notified.'),
        backgroundColor: AppTheme.errorRed,
      ),
    );
  }
}
