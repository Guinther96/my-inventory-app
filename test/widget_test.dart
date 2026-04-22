import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_inventory_app/data/models/company_model.dart';
import 'package:my_inventory_app/data/providers/feature_access_provider.dart';
import 'package:my_inventory_app/data/providers/user_profile_provider.dart';
import 'package:my_inventory_app/presentation/common_widgets/app_drawer.dart';
import 'package:my_inventory_app/services/features/feature_access_service.dart';

import 'package:provider/provider.dart';

void main() {
  testWidgets('disparition UI immediate quand feature desactivee', (
    WidgetTester tester,
  ) async {
    final featureProvider = FeatureAccessProvider();
    final userProvider = UserProfileProvider();

    featureProvider.debugSetSnapshot(
      FeatureAccessSnapshot(
        company: const Company(id: 'c1', status: CompanyStatus.active),
        features: const <String, bool>{
          'dashboard': true,
          'sales': true,
          'services': true,
          'settings': true,
        },
      ),
    );

    final router = GoRouter(
      initialLocation: '/sales',
      routes: [
        GoRoute(
          path: '/sales',
          builder: (_, __) => const Scaffold(body: AppDrawer()),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProfileProvider>.value(
            value: userProvider,
          ),
          ChangeNotifierProvider<FeatureAccessProvider>.value(
            value: featureProvider,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Services'), findsOneWidget);

    featureProvider.debugSetSnapshot(
      FeatureAccessSnapshot(
        company: const Company(id: 'c1', status: CompanyStatus.active),
        features: const <String, bool>{
          'dashboard': true,
          'sales': true,
          'services': false,
          'settings': true,
        },
      ),
    );

    await tester.pump();
    expect(find.text('Services'), findsNothing);
  });
}
