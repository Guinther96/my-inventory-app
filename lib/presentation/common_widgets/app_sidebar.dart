import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers/feature_access_provider.dart';
import '../../data/providers/user_profile_provider.dart';
import '../features/reports/screens/user_roles_screen.dart';
import 'side_menu_item.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key});

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
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.shopping_bag_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BiznisPlus',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Gestion de stock',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'MENU PRINCIPAL',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppColors.textSecondary.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  if (isProvider && featureAccess.canAccess('provider')) ...[
                    SideMenuItem(
                      icon: Icons.dashboard_customize,
                      label: 'Mon tableau de bord',
                      selected: currentRoute == '/provider/dashboard',
                      onTap: () => context.go('/provider/dashboard'),
                    ),
                    SideMenuItem(
                      icon: Icons.calendar_month,
                      label: 'Mes réservations',
                      selected: currentRoute.startsWith('/provider/reservations'),
                      onTap: () => context.go('/provider/reservations'),
                    ),
                  ],
                  if (!isProvider && featureAccess.canAccess('dashboard'))
                    SideMenuItem(
                      icon: Icons.dashboard,
                      label: 'Tableau de bord',
                      selected: currentRoute == '/',
                      onTap: () => context.go('/'),
                    ),
                  if (isManager && featureAccess.canAccess('inventory'))
                    SideMenuItem(
                      icon: Icons.inventory,
                      label: 'Produits',
                      selected: currentRoute == '/products',
                      onTap: () => context.go('/products'),
                    ),
                  if (isManager && featureAccess.canAccess('inventory'))
                    SideMenuItem(
                      icon: Icons.category,
                      label: 'Categories',
                      selected: currentRoute == '/categories',
                      onTap: () => context.go('/categories'),
                    ),
                  if (isManager && featureAccess.canAccess('inventory'))
                    SideMenuItem(
                      icon: Icons.sync_alt,
                      label: 'Mouvements',
                      selected: currentRoute == '/movements',
                      onTap: () => context.go('/movements'),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    child: Divider(height: 1),
                  ),
                  if (featureAccess.canAccess('sales'))
                    SideMenuItem(
                      icon: Icons.point_of_sale,
                      label: 'Ventes',
                      selected: currentRoute == '/sales',
                      onTap: () => context.go('/sales'),
                    ),
                  if (featureAccess.canAccess('services'))
                    SideMenuItem(
                      icon: Icons.spa,
                      label: 'Services',
                      selected: currentRoute == '/beauty/services',
                      onTap: () => context.go('/beauty/services'),
                    ),
                  if (isManager && featureAccess.canAccess('services'))
                    SideMenuItem(
                      icon: Icons.category_outlined,
                      label: 'Categories de services',
                      selected: currentRoute == '/beauty/service-categories',
                      onTap: () => context.go('/beauty/service-categories'),
                    ),
                  if (featureAccess.canAccess('services'))
                    SideMenuItem(
                      icon: Icons.event_available,
                      label: 'Reservations',
                      selected: currentRoute == '/beauty/reservations',
                      onTap: () => context.go('/beauty/reservations'),
                    ),
                  if (isManager &&
                      (featureAccess.canAccess('reports') ||
                          featureAccess.canAccess('users'))) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      child: Divider(height: 1),
                    ),
                  ],
                  if (isManager && featureAccess.canAccess('reports'))
                    SideMenuItem(
                      icon: Icons.bar_chart,
                      label: 'Rapports',
                      selected: currentRoute == '/reports',
                      onTap: () => context.go('/reports'),
                    ),
                  if (isManager && featureAccess.canAccess('users'))
                    SideMenuItem(
                      icon: Icons.manage_accounts,
                      label: 'Utilisateurs',
                      selected: currentRoute == '/users',
                      onTap: () => _openUsers(context),
                    ),
                ],
              ),
            ),
            if (featureAccess.canAccess('settings')) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Divider(height: 1),
              ),
              const SizedBox(height: 4),
              SideMenuItem(
                icon: Icons.settings,
                label: 'Parametres',
                selected: currentRoute == '/settings',
                onTap: () => context.go('/settings'),
              ),
              const SizedBox(height: 4),
            ],
            _SidebarUserFooter(profile: profile),
          ],
        ),
      ),
    );
  }
}

/// Bloc profil utilisateur en bas de la sidebar: avatar (initiale de
/// l'email), email et role. Purement presentationnel — profile vient du
/// UserProfileProvider deja watch() par le parent, aucune logique ajoutee.
class _SidebarUserFooter extends StatelessWidget {
  final UserProfileProvider profile;

  const _SidebarUserFooter({required this.profile});

  @override
  Widget build(BuildContext context) {
    final email = profile.profile?.email ?? '';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';
    final roleLabel = profile.isManager
        ? 'Manager'
        : profile.isProvider
        ? 'Prestataire'
        : 'Vendeur';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text(
              initial,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email.isEmpty ? 'Utilisateur' : email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  roleLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}
