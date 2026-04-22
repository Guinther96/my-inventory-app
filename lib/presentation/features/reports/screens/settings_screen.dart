import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../data/providers/inventory_provider.dart';
import '../../../../data/providers/user_profile_provider.dart';
import '../../../../services/auth/auth_service.dart';
import '../../../../services/printer/printer_models.dart';
import '../../../../services/printer/printer_service.dart';
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

                    if (isManager)
                      _SettingsBlock(
                        title: 'Gestion equipe',
                        description:
                            'Attribuez les roles manager/caissier aux utilisateurs de votre entreprise.',
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
                      title: 'Imprimante Bluetooth',
                      description:
                          'Connectez une imprimante pour les tickets de vente et de service.',
                      icon: Icons.print_outlined,
                      iconColor: const Color(0xFF0A7D6D),
                      child: _PrinterSettingsPanel(
                        companyName: context
                            .read<InventoryProvider>()
                            .companyName,
                      ),
                    ),
                    const SizedBox(height: 14),
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

class _PrinterSettingsPanel extends StatefulWidget {
  final String companyName;

  const _PrinterSettingsPanel({required this.companyName});

  @override
  State<_PrinterSettingsPanel> createState() => _PrinterSettingsPanelState();
}

class _PrinterSettingsPanelState extends State<_PrinterSettingsPanel> {
  bool _isLoading = true;
  bool _isBusy = false;
  bool _isConnected = false;
  List<PrinterDeviceInfo> _devices = const <PrinterDeviceInfo>[];
  PrinterDeviceInfo? _selectedDevice;

  @override
  void initState() {
    super.initState();
    _refreshPrinterState();
  }

  Future<void> _refreshPrinterState() async {
    setState(() => _isLoading = true);
    try {
      final devices = await PrinterService.getPairedBluetoothDevices();
      final connected = await PrinterService.isConnected();
      final saved = await PrinterService.getPreferredPrinter();

      PrinterDeviceInfo? selected;
      if (saved != null) {
        for (final device in devices) {
          if (device.address == saved.address) {
            selected = device;
            break;
          }
        }
      }

      setState(() {
        _devices = devices;
        _isConnected = connected;
        _selectedDevice = selected;
      });
    } catch (e, st) {
      debugPrint('Refresh printer state failed: $e');
      debugPrint('$st');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _connectSelected() async {
    final device = _selectedDevice;
    if (device == null) {
      _show('Selectionnez une imprimante.');
      return;
    }

    setState(() => _isBusy = true);
    try {
      final connected = await PrinterService.connectBluetoothPrinter(device);
      if (connected) {
        _show('Imprimante connectee.');
      } else {
        _show('Impossible de connecter l imprimante.');
      }
      await _refreshPrinterState();
    } catch (e, st) {
      debugPrint('Connect printer failed: $e');
      debugPrint('$st');
      _show('Erreur de connexion imprimante.');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _testPrint() async {
    setState(() => _isBusy = true);
    try {
      if (!await PrinterService.isConnected()) {
        _show('Imprimante non connectee.');
        return;
      }

      await PrinterService.printTestReceipt(companyName: widget.companyName);
      _show('Ticket test envoye.');
    } catch (e, st) {
      debugPrint('Test print failed: $e');
      debugPrint('$st');
      _show('Erreur pendant le test impression.');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _disconnect() async {
    setState(() => _isBusy = true);
    try {
      await PrinterService.disconnect();
      _show('Imprimante deconnectee.');
      await _refreshPrinterState();
    } catch (e, st) {
      debugPrint('Disconnect printer failed: $e');
      debugPrint('$st');
      _show('Erreur de deconnexion imprimante.');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  void _show(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!PrinterService.supportsPrinting) {
      return const Text(
        'Impression Bluetooth disponible uniquement sur Android.',
      );
    }

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              color: _isConnected ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            Text(_isConnected ? 'Etat: connectee' : 'Etat: non connectee'),
          ],
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<PrinterDeviceInfo>(
          initialValue: _selectedDevice,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Imprimante appairee',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: _devices
              .map(
                (device) => DropdownMenuItem<PrinterDeviceInfo>(
                  value: device,
                  child: Text(
                    device.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: _isBusy
              ? null
              : (value) {
                  setState(() => _selectedDevice = value);
                },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _isBusy ? null : _refreshPrinterState,
              icon: const Icon(Icons.refresh),
              label: const Text('Scanner'),
            ),
            FilledButton.tonalIcon(
              onPressed: _isBusy ? null : _connectSelected,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Connecter'),
            ),
            FilledButton.tonalIcon(
              onPressed: _isBusy ? null : _testPrint,
              icon: const Icon(Icons.receipt_long),
              label: const Text('Test impression'),
            ),
            TextButton.icon(
              onPressed: _isBusy ? null : _disconnect,
              icon: const Icon(Icons.link_off),
              label: const Text('Deconnecter'),
            ),
          ],
        ),
      ],
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
