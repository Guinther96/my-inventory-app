import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../data/models/provider_earning_model.dart';

class EarningCard extends StatelessWidget {
  final ProviderEarning earning;

  const EarningCard({Key? key, required this.earning}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(earning.createdAt);
    final amountStr = NumberFormat.currency(symbol: '', decimalDigits: 2)
        .format(earning.amount);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.green,
          child: Icon(Icons.attach_money, color: Colors.white),
        ),
        title: Text(
          amountStr,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text('Gagné le $dateStr'),
      ),
    );
  }
}
