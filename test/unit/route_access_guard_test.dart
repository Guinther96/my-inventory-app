import 'package:flutter_test/flutter_test.dart';
import 'package:my_inventory_app/core/security/route_access_guard.dart';
import 'package:my_inventory_app/data/models/company_model.dart';
import 'package:my_inventory_app/data/models/user_profile_model.dart';
import 'package:my_inventory_app/services/features/feature_access_service.dart';

void main() {
  setUp(() {
    FeatureAccessService.instance.debugSetSnapshot(
      FeatureAccessSnapshot(
        company: const Company(id: 'c1', status: CompanyStatus.active),
        features: const <String, bool>{
          'sales': true,
          'services': true,
          'settings': true,
        },
      ),
    );
  });

  test('active + enabled => OK', () {
    final decision = RouteAccessGuard.evaluateSync(
      route: '/sales',
      role: AppRole.seller,
    );

    expect(decision.allowed, isTrue);
  });

  test('active + disabled => KO', () {
    FeatureAccessService.instance.debugSetSnapshot(
      FeatureAccessSnapshot(
        company: const Company(id: 'c1', status: CompanyStatus.active),
        features: const <String, bool>{'sales': false, 'settings': true},
      ),
    );

    final decision = RouteAccessGuard.evaluateSync(
      route: '/sales',
      role: AppRole.seller,
    );

    expect(decision.allowed, isFalse);
    expect(decision.message, contains('Fonctionnalite desactivee'));
  });

  test('suspended => KO global', () {
    FeatureAccessService.instance.debugSetSnapshot(
      FeatureAccessSnapshot(
        company: const Company(id: 'c1', status: CompanyStatus.suspended),
        features: const <String, bool>{
          'sales': true,
          'services': true,
          'settings': true,
        },
      ),
    );

    final salesDecision = RouteAccessGuard.evaluateSync(
      route: '/sales',
      role: AppRole.seller,
    );
    final settingsDecision = RouteAccessGuard.evaluateSync(
      route: '/settings',
      role: AppRole.manager,
    );

    expect(salesDecision.allowed, isFalse);
    expect(settingsDecision.allowed, isFalse);
    expect(salesDecision.message, contains('Entreprise suspendue'));
  });
}
