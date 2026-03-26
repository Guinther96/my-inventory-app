import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/providers/user_profile_provider.dart';
import '../features/reports/screens/user_roles_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({Key? key}) : super(key: key);

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
    final currentRoute = GoRouterState.of(context).uri.toString();
    final profile = context.watch<UserProfileProvider>();
    final isManager = profile.isManager;

    return Drawer(
      child: ListView(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
            ),
            child: const Text(
              'BiznisPlus',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Tableau de bord'),
            selected: currentRoute == '/',
            onTap: () {
              _goToRoute(context, '/');
            },
          ),
          if (isManager)
            ListTile(
              leading: const Icon(Icons.inventory),
              title: const Text('Produits'),
              selected: currentRoute == '/products',
              onTap: () {
                _goToRoute(context, '/products');
              },
            ),
          if (isManager)
            ListTile(
              leading: const Icon(Icons.category),
              title: const Text('Categories'),
              selected: currentRoute == '/categories',
              onTap: () {
                _goToRoute(context, '/categories');
              },
            ),
          if (isManager)
            ListTile(
              leading: const Icon(Icons.sync_alt),
              title: const Text('Mouvements'),
              selected: currentRoute == '/movements',
              onTap: () {
                _goToRoute(context, '/movements');
              },
            ),
          ListTile(
            leading: const Icon(Icons.point_of_sale),
            title: const Text('Ventes'),
            selected: currentRoute == '/sales',
            onTap: () {
              _goToRoute(context, '/sales');
            },
          ),
          ListTile(
            leading: const Icon(Icons.spa),
            title: const Text('Services'),
            selected: currentRoute == '/beauty/services',
            onTap: () {
              _goToRoute(context, '/beauty/services');
            },
          ),
          ListTile(
            leading: const Icon(Icons.event_available),
            title: const Text('Reservations'),
            selected: currentRoute == '/beauty/reservations',
            onTap: () {
              _goToRoute(context, '/beauty/reservations');
            },
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('Rapports'),
            selected: currentRoute == '/reports',
            onTap: () {
              _goToRoute(context, '/reports');
            },
          ),
          if (isManager)
            ListTile(
              leading: const Icon(Icons.manage_accounts),
              title: const Text('Utilisateurs'),
              selected: currentRoute == '/users',
              onTap: () {
                _openUsers(context);
              },
            ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Parametres'),
            selected: currentRoute == '/settings',
            onTap: () {
              _goToRoute(context, '/settings');
            },
          ),
        ],
      ),
    );
  }
}
