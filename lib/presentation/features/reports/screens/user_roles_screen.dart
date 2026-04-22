import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../data/models/user_profile_model.dart';
import '../../../../data/providers/user_profile_provider.dart';
import '../../../../services/auth/auth_service.dart';
import '../../../../services/user/user_profile_service.dart';
import '../../../common_widgets/app_drawer.dart';
import '../../../common_widgets/app_sidebar.dart';

class UserRolesScreen extends StatefulWidget {
  const UserRolesScreen({super.key});

  @override
  State<UserRolesScreen> createState() => _UserRolesScreenState();
}

class _UserRolesScreenState extends State<UserRolesScreen> {
  final UserProfileService _service = UserProfileService();
  final TextEditingController _emailController = TextEditingController();

  final TextEditingController _newStaffEmailController =
      TextEditingController();

  List<UserProfile> _users = const <UserProfile>[];
  bool _isLoading = true;
  bool _isUpdating = false;
  bool _isAdding = false;
  bool _isDeleting = false;
  bool _isCreatingStaff = false;
  String? _error;
  AppRole _selectedNewRole = AppRole.seller;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _newStaffEmailController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final users = await _service.fetchCompanyUsers();
      if (!mounted) {
        return;
      }
      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _changeRole(UserProfile user, AppRole newRole) async {
    if (_isUpdating || user.role == newRole) {
      return;
    }

    setState(() => _isUpdating = true);

    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      final isSelfRoleUpdate =
          currentUserId != null && currentUserId == user.id;

      await _service.updateUserRole(userId: user.id, role: newRole);

      if (!mounted) {
        return;
      }

      await context.read<UserProfileProvider>().initialize(forceRefresh: true);

      // If the current user becomes seller, /users is no longer accessible.
      // Navigate immediately to avoid ending in a transient blank screen state.
      if (isSelfRoleUpdate && newRole == AppRole.seller) {
        if (!mounted) {
          return;
        }
        context.go('/sales');
        return;
      }

      await _loadUsers();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Role mis a jour pour ${user.email}.')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _createStaffAndShowCode() async {
    if (_isCreatingStaff) return;

    final email = _newStaffEmailController.text.trim().toLowerCase();
    if (email.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Email requis.')));
      return;
    }

    setState(() => _isCreatingStaff = true);

    try {
      final authService = AuthService();
      final inviteCode = authService.generateInviteCode();

      // Create the auth account with the code as temporary password
      await authService.signUpStaffAccountWithCode(
        email: email,
        tempPassword: inviteCode,
      );

      // Assign to the company as seller
      await _service.addUserToCompanyByEmail(
        email: email,
        role: AppRole.seller,
      );

      // Mark the account as requiring a password change
      await Supabase.instance.client.rpc(
        'set_must_change_password',
        params: {'p_email': email},
      );

      if (!mounted) return;

      _newStaffEmailController.clear();
      await _loadUsers();

      if (!mounted) return;

      // Show dialog with the invite code
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Compte employe cree'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Compte cree pour : $email'),
                const SizedBox(height: 16),
                const Text(
                  'Code d\'acces temporaire :',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F6FC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFD0E4F0)),
                  ),
                  child: Text(
                    inviteCode,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Partagez ce code avec l\'employe. Il devra d abord confirmer l email recu, puis se connecter avec son email et ce code avant de definir un nouveau mot de passe.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copier le code'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: inviteCode));
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Code copie dans le presse-papier.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Fermer'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isCreatingStaff = false);
    }
  }

  Future<void> _addUserByEmail() async {
    if (_isAdding) {
      return;
    }

    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Email requis.')));
      return;
    }

    setState(() => _isAdding = true);

    try {
      await _service.addUserToCompanyByEmail(
        email: email,
        role: _selectedNewRole,
      );

      if (!mounted) {
        return;
      }

      _emailController.clear();
      await _loadUsers();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Compte $email ajoute avec role ${_selectedNewRole.name}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
  }

  Future<void> _removeManagedUser(UserProfile user) async {
    if (_isDeleting) {
      return;
    }

    final roleLabel = user.role == AppRole.provider
        ? 'prestataire'
        : 'caissier';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Supprimer le compte $roleLabel'),
          content: Text('Supprimer ${user.email} de votre compagnie ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _isDeleting = true);

    try {
      await _service.removeUserFromCompany(userId: user.id);

      if (!mounted) {
        return;
      }

      await _loadUsers();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Compte $roleLabel ${user.email} supprime.')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 950;
    final profile = context.watch<UserProfileProvider>();

    if (profile.isSeller) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gestion des roles')),
        body: const Center(child: Text('Acces reserve aux managers.')),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: isDesktop ? null : AppBar(title: const Text('Gestion des roles')),
      drawer: isDesktop ? null : const AppDrawer(),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) const AppSidebar(),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 24 : 14,
                20,
                isDesktop ? 24 : 14,
                18,
              ),
              child: RefreshIndicator(
                onRefresh: _loadUsers,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gestion des roles',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Attribuez les roles manager, caissier ou provider aux utilisateurs de votre entreprise. Le compte employe/prestataire doit exister avant son ajout.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 14),
                          _buildCreateStaffCard(),
                          const SizedBox(height: 12),
                          _buildAddUserCard(),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                    _buildSliverContent(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverContent() {
    if (_isLoading) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadUsers,
                child: const Text('Reessayer'),
              ),
            ],
          ),
        ),
      );
    }

    if (_users.isEmpty) {
      return const SliverFillRemaining(
        child: Center(child: Text('Aucun utilisateur trouve.')),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final user = _users[index];
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        final canDeleteManagedUser =
            (user.role == AppRole.seller || user.role == AppRole.provider) &&
            user.id != currentUserId;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _UserRoleTile(
            user: user,
            isUpdating: _isUpdating,
            onRoleChanged: (value) => _changeRole(user, value),
            canDeleteSeller: canDeleteManagedUser,
            onDeleteSeller: canDeleteManagedUser
                ? () => _removeManagedUser(user)
                : null,
          ),
        );
      }, childCount: _users.length),
    );
  }

  Widget _buildCreateStaffCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_add, color: colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Creer un compte employe',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Cree un nouveau compte employe et genere un code d\'acces temporaire. Partagez ce code avec votre employe pour qu\'il puisse se connecter et definir son mot de passe.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newStaffEmailController,
                  decoration: const InputDecoration(
                    labelText: 'Email de l\'employe',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _isCreatingStaff ? null : _createStaffAndShowCode,
                icon: const Icon(Icons.key),
                label: Text(
                  _isCreatingStaff ? 'Creation...' : 'Generer le code',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddUserCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ajouter un compte existant',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Etape 1: l utilisateur cree son compte depuis Connexion > Creer un nouveau compte (employe ou prestataire). Etape 2: le manager saisit ici le meme email pour rattacher ce compte a la compagnie.',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email du compte',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 140,
                child: DropdownButtonFormField<AppRole>(
                  initialValue: _selectedNewRole,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: AppRole.manager,
                      child: Text('manager'),
                    ),
                    DropdownMenuItem(
                      value: AppRole.seller,
                      child: Text('caissier'),
                    ),
                    DropdownMenuItem(
                      value: AppRole.provider,
                      child: Text('provider'),
                    ),
                  ],
                  onChanged: _isAdding
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _selectedNewRole = value;
                            });
                          }
                        },
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _isAdding ? null : _addUserByEmail,
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(_isAdding ? 'Ajout...' : 'Ajouter'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UserRoleTile extends StatelessWidget {
  final UserProfile user;
  final bool isUpdating;
  final ValueChanged<AppRole> onRoleChanged;
  final bool canDeleteSeller;
  final VoidCallback? onDeleteSeller;

  const _UserRoleTile({
    required this.user,
    required this.isUpdating,
    required this.onRoleChanged,
    required this.canDeleteSeller,
    required this.onDeleteSeller,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: Text(
              user.email.isNotEmpty ? user.email[0].toUpperCase() : '?',
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              user.email,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<AppRole>(
              initialValue: user.role,
              decoration: const InputDecoration(
                labelText: 'Role',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: AppRole.manager,
                  child: Text('manager'),
                ),
                DropdownMenuItem(
                  value: AppRole.seller,
                  child: Text('caissier'),
                ),
                DropdownMenuItem(
                  value: AppRole.provider,
                  child: Text('provider'),
                ),
              ],
              onChanged: isUpdating
                  ? null
                  : (value) {
                      if (value != null) {
                        onRoleChanged(value);
                      }
                    },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: canDeleteSeller
                ? 'Supprimer ce compte caissier/prestataire'
                : 'Suppression reservee aux caissiers/prestataires',
            onPressed: canDeleteSeller && !isUpdating ? onDeleteSeller : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}
