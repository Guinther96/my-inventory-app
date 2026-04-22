import 'package:flutter_test/flutter_test.dart';
import 'package:my_inventory_app/data/models/company_model.dart';

void main() {
  group('Company.normalizeStatus', () {
    test('normalise actif/active vers active', () {
      expect(Company.normalizeStatus('actif'), CompanyStatus.active);
      expect(Company.normalizeStatus('active'), CompanyStatus.active);
    });

    test('normalise suspendu/suspended vers suspended', () {
      expect(Company.normalizeStatus('suspendu'), CompanyStatus.suspended);
      expect(Company.normalizeStatus('suspended'), CompanyStatus.suspended);
    });

    test('invalide -> suspended (fail-safe)', () {
      expect(Company.normalizeStatus('trial'), CompanyStatus.suspended);
      expect(Company.normalizeStatus(null), CompanyStatus.suspended);
    });
  });
}
