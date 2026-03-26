import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../data/providers/inventory_provider.dart';
import '../../../../data/providers/user_profile_provider.dart';
import '../../../../services/auth_service.dart';
import '../../../common_widgets/app_drawer.dart';
import '../../../common_widgets/app_sidebar.dart';
import 'user_roles_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _openUsers(BuildContext context) {
    try {
      context.go('/users');
    } catch (_) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const UserRolesScreen()));
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Se deconnecter'),
          content: const Text('Voulez-vous vraiment vous deconnecter ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Se deconnecter'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) {
      return;
    }

    try {
      await AuthService().signOut();
      if (!context.mounted) {
        return;
      }
      context.read<UserProfileProvider>().clear();
      await context.read<InventoryProvider>().initialize(forceRefresh: true);
      if (!context.mounted) {
        return;
      }
      context.go('/login');
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la deconnexion.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 950;
    final horizontalPadding = isDesktop ? 24.0 : 14.0;
    final isManager = context.watch<UserProfileProvider>().isManager;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: isDesktop ? null : AppBar(title: const Text('Parametres')),
      drawer: isDesktop ? null : const AppDrawer(),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) const AppSidebar(),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                20,
                horizontalPadding,
                18,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Parametres',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 14),
                    _SettingsBlock(
                      title: 'Maintenance des donnees',
                      description:
                          'Reinitialiser les donnees efface les elements saisis et recharge un jeu de demonstration.',
                      icon: Icons.build_circle_outlined,
                      iconColor: const Color(0xFFD97706),
                      child: FilledButton.tonalIcon(
                        onPressed: () async {
                          await context
                              .read<InventoryProvider>()
                              .clearAllData();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Donnees reinitialisees.'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.delete_sweep),
                        label: const Text('Reinitialiser les donnees'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (isManager)
                      _SettingsBlock(
                        title: 'Gestion equipe',
                        description:
                            'Attribuez les roles manager/seller aux utilisateurs de votre entreprise.',
                        icon: Icons.manage_accounts_outlined,
                        iconColor: const Color(0xFF0A8A4B),
                        child: FilledButton.tonalIcon(
                          onPressed: () => _openUsers(context),
                          icon: const Icon(Icons.groups_2),
                          label: const Text('Gerer les utilisateurs'),
                        ),
                      ),
                    if (isManager) const SizedBox(height: 14),
                    _SettingsBlock(
                      title: 'Securite du compte',
                      description:
                          'Changez votre mot de passe pour renforcer la securite de votre compte.',
                      icon: Icons.lock_outline,
                      iconColor: const Color(0xFF7C3AED),
                      child: FilledButton.tonalIcon(
                        onPressed: () => context.go('/change-password'),
                        icon: const Icon(Icons.password),
                        label: const Text('Changer le mot de passe'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SettingsBlock(
                      title: 'Compte',
                      description:
                          'Vous pouvez vous deconnecter et revenir a l ecran de connexion.',
                      icon: Icons.verified_user_outlined,
                      iconColor: const Color(0xFF0C7EA5),
                      child: FilledButton.icon(
                        onPressed: () => _handleLogout(context),
                        icon: const Icon(Icons.logout),
                        label: const Text('Se deconnecter'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsBlock extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;
  final Widget child;

  const _SettingsBlock({
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: iconColor.withValues(alpha: 0.14),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(description),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
