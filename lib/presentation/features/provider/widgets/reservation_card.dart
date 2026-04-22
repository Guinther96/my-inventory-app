import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../data/models/provider_reservation_model.dart';

class ReservationCard extends StatelessWidget {
  final ProviderReservation reservation;
  final VoidCallback? onMarkCompleted;
  final VoidCallback? onMarkCancelled;
  final VoidCallback? onDelete;

  const ReservationCard({
    Key? key,
    required this.reservation,
    this.onMarkCompleted,
    this.onMarkCancelled,
    this.onDelete,
  }) : super(key: key);

  Color _statusColor(BuildContext context) {
    switch (reservation.status) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  String _statusLabel() {
    switch (reservation.status) {
      case 'completed':
        return 'Terminé';
      case 'cancelled':
        return 'Annulé';
      default:
        return 'En attente';
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('dd/MM/yyyy').format(reservation.date);
    final priceStr = NumberFormat.currency(
      symbol: 'HTG ',
      decimalDigits: 2,
    ).format(reservation.price);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        title: Text(
          reservation.clientName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${reservation.serviceName} — $dateStr à ${reservation.time}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  priceStr,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(context).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _statusLabel(),
                    style: TextStyle(
                      fontSize: 11,
                      color: _statusColor(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (reservation.status == 'pending') ...[
              IconButton(
                icon: const Icon(Icons.check_circle_outline),
                tooltip: 'Marquer terminé',
                color: Colors.green,
                onPressed: onMarkCompleted,
              ),
              IconButton(
                icon: const Icon(Icons.cancel_outlined),
                tooltip: 'Annuler',
                color: Colors.red,
                onPressed: onMarkCancelled,
              ),
            ],
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Supprimer',
              color: Colors.grey,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
