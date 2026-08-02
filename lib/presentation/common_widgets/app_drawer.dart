import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/providers/feature_access_provider.dart';
import '../../data/providers/user_profile_provider.dart';
import '../features/reports/screens/user_roles_screen.dart';
import 'side_menu_item.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  void _goToRoute(BuildContext context, String route) {
    context.go(route);
  }

  void _openUsers(BuildContext context) {
    try {
      _goToRoute(context, '/users');
    } catch (_) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const UserRolesScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentRoute = GoRouterState.of(context).uri.toString();
    final profile = context.watch<UserProfileProvider>();
    final featureAccess = context.watch<FeatureAccessProvider>();
    final isManager = profile.isManager;
    final email = profile.profile?.email ?? '';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';

    return Drawer(
      backgroundColor: colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.shopping_bag_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BiznisPlus',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Gestion de stock',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Divider(height: 1),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  if (featureAccess.canAccess('dashboard'))
                    SideMenuItem(
                      icon: Icons.dashboard,
                      label: 'Tableau de bord',
                      selected: currentRoute == '/',
                      onTap: () => _goToRoute(context, '/'),
                    ),
                  if (isManager && featureAccess.canAccess('inventory'))
                    SideMenuItem(
                      icon: Icons.inventory,
                      label: 'Produits',
                      selected: currentRoute == '/products',
                      onTap: () => _goToRoute(context, '/products'),
                    ),
                  if (isManager && featureAccess.canAccess('inventory'))
                    SideMenuItem(
                      icon: Icons.category,
                      label: 'Categories',
                      selected: currentRoute == '/categories',
                      onTap: () => _goToRoute(context, '/categories'),
                    ),
                  if (isManager && featureAccess.canAccess('inventory'))
                    SideMenuItem(
                      icon: Icons.sync_alt,
                      label: 'Mouvements',
                      selected: currentRoute == '/movements',
                      onTap: () => _goToRoute(context, '/movements'),
                    ),
                  if (featureAccess.canAccess('sales'))
                    SideMenuItem(
                      icon: Icons.point_of_sale,
                      label: 'Ventes',
                      selected: currentRoute == '/sales',
                      onTap: () => _goToRoute(context, '/sales'),
                    ),
                  if (featureAccess.canAccess('services'))
                    SideMenuItem(
                      icon: Icons.spa,
                      label: 'Services',
                      selected: currentRoute == '/beauty/services',
                      onTap: () => _goToRoute(context, '/beauty/services'),
                    ),
                  if (isManager && featureAccess.canAccess('services'))
                    SideMenuItem(
                      icon: Icons.category_outlined,
                      label: 'Categories de services',
                      selected: currentRoute == '/beauty/service-categories',
                      onTap: () =>
                          _goToRoute(context, '/beauty/service-categories'),
                    ),
                  if (featureAccess.canAccess('services'))
                    SideMenuItem(
                      icon: Icons.event_available,
                      label: 'Reservations',
                      selected: currentRoute == '/beauty/reservations',
                      onTap: () => _goToRoute(context, '/beauty/reservations'),
                    ),
                  if (isManager && featureAccess.canAccess('reports'))
                    SideMenuItem(
                      icon: Icons.bar_chart,
                      label: 'Rapports',
                      selected: currentRoute == '/reports',
                      onTap: () => _goToRoute(context, '/reports'),
                    ),
                  if (isManager && featureAccess.canAccess('users'))
                    SideMenuItem(
                      icon: Icons.manage_accounts,
                      label: 'Utilisateurs',
                      selected: currentRoute == '/users',
                      onTap: () => _openUsers(context),
                    ),
                  if (featureAccess.canAccess('settings'))
                    SideMenuItem(
                      icon: Icons.settings,
                      label: 'Parametres',
                      selected: currentRoute == '/settings',
                      onTap: () => _goToRoute(context, '/settings'),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Divider(height: 1),
            ),
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                    child: Text(
                      initial,
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      email.isEmpty ? 'Utilisateur' : email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
