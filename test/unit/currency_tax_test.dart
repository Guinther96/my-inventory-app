import 'package:flutter_test/flutter_test.dart';
import 'package:my_inventory_app/core/utils/currency.dart';

void main() {
  group('calculateTax', () {
    test('taxe desactivee -> pas de taxe, total = sous-total', () {
      final result = calculateTax(
        subtotal: 100,
        taxEnabled: false,
        taxType: 'percentage',
        taxValue: 10,
        paymentCurrency: 'HTG',
      );

      expect(result, isNotNull);
      expect(result!.subtotal, 100);
      expect(result.taxAmount, 0);
      expect(result.total, 100);
    });

    test('pourcentage simple sur sous-total HTG', () {
      final result = calculateTax(
        subtotal: 100,
        taxEnabled: true,
        taxType: 'percentage',
        taxValue: 10,
        paymentCurrency: 'HTG',
      );

      expect(result, isNotNull);
      expect(result!.taxAmount, 10.00);
      expect(result.total, 110.00);
    });

    test('pourcentage sur sous-total USD', () {
      final result = calculateTax(
        subtotal: 25,
        taxEnabled: true,
        taxType: 'percentage',
        taxValue: 8,
        paymentCurrency: 'USD',
      );

      expect(result, isNotNull);
      expect(result!.taxAmount, 2.00);
      expect(result.total, 27.00);
    });

    test('montant fixe, meme devise que le paiement', () {
      final result = calculateTax(
        subtotal: 500,
        taxEnabled: true,
        taxType: 'fixed',
        taxValue: 25,
        taxCurrency: 'HTG',
        paymentCurrency: 'HTG',
      );

      expect(result, isNotNull);
      expect(result!.taxAmount, 25.00);
      expect(result.total, 525.00);
    });

    test('montant fixe, devise differente, taux configure', () {
      // Taxe de 1 USD fixe, paiement en HTG, taux 1 USD = 130 HTG.
      final result = calculateTax(
        subtotal: 500,
        taxEnabled: true,
        taxType: 'fixed',
        taxValue: 1,
        taxCurrency: 'USD',
        paymentCurrency: 'HTG',
        usdToHtgRate: 130,
      );

      expect(result, isNotNull);
      expect(result!.taxAmount, 130.00);
      expect(result.total, 630.00);
    });

    test('montant fixe, devise differente, taux absent -> null', () {
      final result = calculateTax(
        subtotal: 500,
        taxEnabled: true,
        taxType: 'fixed',
        taxValue: 1,
        taxCurrency: 'USD',
        paymentCurrency: 'HTG',
        usdToHtgRate: null,
      );

      expect(result, isNull);
    });

    test('arrondi a 2 decimales sur des montants impairs', () {
      final result = calculateTax(
        subtotal: 99.999,
        taxEnabled: true,
        taxType: 'percentage',
        taxValue: 10,
        paymentCurrency: 'HTG',
      );

      expect(result, isNotNull);
      expect(result!.subtotal, 100.00);
      expect(result.taxAmount, 10.00);
      expect(result.total, 110.00);
    });
  });
}
