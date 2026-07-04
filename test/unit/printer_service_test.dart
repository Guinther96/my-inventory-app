import 'package:flutter_test/flutter_test.dart';
import 'package:my_inventory_app/services/printer/printer_service.dart';

void main() {
  group('PrinterService currency formatting', () {
    test('formats sale amounts with HTG currency', () {
      expect(PrinterService.formatCurrency(12.5), 'HTG 12.50');
      expect(PrinterService.formatCurrency(0), 'HTG 0.00');
    });
  });
}
