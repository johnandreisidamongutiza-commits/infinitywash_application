import 'package:flutter/material.dart';
import '../../../models/order.dart';
import 'create_order_flow.dart';

class EditWalkInOrderScreen extends StatelessWidget {
  final LaundryOrder order;
  const EditWalkInOrderScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    return CreateOrderFlow(orderToEdit: order);
  }
}
