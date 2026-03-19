import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../data/models/service_order_item_model.dart';

class ThermalTicketService {
  Uint8List buildEscPosTicket({
    required String salonName,
    required DateTime date,
    required String clientName,
    required List<ServiceOrderItem> items,
    required double total,
    required String cashierName,
    String? ticketNumber,
  }) {
    final bytes = BytesBuilder();

    void writeRaw(List<int> value) => bytes.add(value);
    void writeLine(String line) => bytes.add(latin1.encode('$line\n'));

    writeRaw(<int>[0x1B, 0x40]);

    writeRaw(<int>[0x1B, 0x61, 0x01]);
    writeRaw(<int>[0x1B, 0x45, 0x01]);
    writeLine(salonName);
    writeRaw(<int>[0x1B, 0x45, 0x00]);
    writeLine('Ticket service');
    writeLine(DateFormat('dd/MM/yyyy HH:mm').format(date));
    if (ticketNumber != null && ticketNumber.isNotEmpty) {
      writeLine('No: $ticketNumber');
    }
    writeLine('');

    writeRaw(<int>[0x1B, 0x61, 0x00]);
    writeLine('Client: $clientName');
    writeLine('--------------------------------');

    for (final item in items) {
      final lineTotal = item.lineTotal.toStringAsFixed(2);
      final unitPrice = item.unitPrice.toStringAsFixed(2);
      writeLine(item.serviceName);
      writeLine('${item.quantity} x $unitPrice = $lineTotal');
    }

    writeLine('--------------------------------');
    writeRaw(<int>[0x1B, 0x45, 0x01]);
    writeLine('TOTAL: ${total.toStringAsFixed(2)}');
    writeRaw(<int>[0x1B, 0x45, 0x00]);
    writeLine('Caissier: $cashierName');
    writeLine('');

    writeRaw(<int>[0x1B, 0x61, 0x01]);
    writeLine('Merci pour votre visite');
    writeLine('');
    writeLine('');

    writeRaw(<int>[0x1D, 0x56, 0x00]);

    return bytes.toBytes();
  }
}
