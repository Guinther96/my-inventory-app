import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/providers/feature_access_provider.dart';
import '../../data/providers/user_profile_provider.dart';
import '../features/reports/screens/user_roles_screen.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({Key? key}) : super(key: key);

  void _openUsers(BuildContext context) {
    try {
      context.go('/users');
    } catch (_) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const UserRolesScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentRoute = GoRouterState.of(context).uri.toString();
    final profile = context.watch<UserProfileProvider>();
    final featureAccess = context.watch<FeatureAccessProvider>();
    final isManager = profile.isManager;
  final isProvider = profile.isProvider;

    return Container(
      width: 250,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'BiznisPlus',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                subtitle: Text(
                  isManager
                      ? 'Role: Manager'
                      : isProvider
                          ? 'Role: Prestataire'
                          : 'Role: Vendeur',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            if (isProvider && featureAccess.canAccess('provider')) ...[
              ListTile(
                leading: const Icon(Icons.dashboard_customize),
                title: const Text('Mon tableau de bord'),
                selected: currentRoute == '/provider/dashboard',
                onTap: () => context.go('/provider/dashboard'),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('Mes réservations'),
                selected: currentRoute.startsWith('/provider/reservations'),
                onTap: () => context.go('/provider/reservations'),
              ),
            ],
            if (!isProvider && featureAccess.canAccess('dashboard'))
              ListTile(
                leading: const Icon(Icons.dashboard),
                title: const Text('Tableau de bord'),
                selected: currentRoute == '/',
                onTap: () => context.go('/'),
              ),
            if (isManager && featureAccess.canAccess('inventory'))
              ListTile(
                leading: const Icon(Icons.inventory),
                title: const Text('Produits'),
                selected: currentRoute == '/products',
                onTap: () => context.go('/products'),
              ),
            if (isManager && featureAccess.canAccess('inventory'))
              ListTile(
                leading: const Icon(Icons.category),
                title: const Text('Categories'),
                selected: currentRoute == '/categories',
                onTap: () => context.go('/categories'),
              ),
            if (isManager && featureAccess.canAccess('inventory'))
              ListTile(
                leading: const Icon(Icons.sync_alt),
                title: const Text('Mouvements'),
                selected: currentRoute == '/movements',
                onTap: () => context.go('/movements'),
              ),
            if (featureAccess.canAccess('sales'))
              ListTile(
                leading: const Icon(Icons.point_of_sale),
                title: const Text('Ventes'),
                selected: currentRoute == '/sales',
                onTap: () => context.go('/sales'),
              ),
            if (featureAccess.canAccess('services'))
              ListTile(
                leading: const Icon(Icons.spa),
                title: const Text('Services'),
                selected: currentRoute == '/beauty/services',
                onTap: () => context.go('/beauty/services'),
              ),
            if (featureAccess.canAccess('services'))
              ListTile(
                leading: const Icon(Icons.event_available),
                title: const Text('Reservations'),
                selected: currentRoute == '/beauty/reservations',
                onTap: () => context.go('/beauty/reservations'),
              ),
            if (isManager && featureAccess.canAccess('reports'))
              ListTile(
                leading: const Icon(Icons.bar_chart),
                title: const Text('Rapports'),
                selected: currentRoute == '/reports',
                onTap: () => context.go('/reports'),
              ),
            if (isManager && featureAccess.canAccess('users'))
              ListTile(
                leading: const Icon(Icons.manage_accounts),
                title: const Text('Utilisateurs'),
                selected: currentRoute == '/users',
                onTap: () => _openUsers(context),
              ),
            const Divider(height: 24),
            if (featureAccess.canAccess('settings'))
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Parametres'),
                selected: currentRoute == '/settings',
                onTap: () => context.go('/settings'),
              ),
          ],
        ),
      ),
    );
  }
}
