import 'package:flutter_test/flutter_test.dart';
import 'package:my_inventory_app/services/printer/printer_service.dart';

void main() {
  group('PrinterService currency formatting', () {
    test('formats sale amounts with HTG currency', () {
      expect(PrinterService.formatCurrency(12.5), '12.50 HTG');
      expect(PrinterService.formatCurrency(0), '0.00 HTG');
    });

    test('formats sale amounts with an explicit currency', () {
      expect(PrinterService.formatCurrency(2, 'USD'), '2.00 USD');
    });
  });
}
