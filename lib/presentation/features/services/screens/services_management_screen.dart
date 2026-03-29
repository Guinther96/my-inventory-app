import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../../data/models/service_model.dart';
import '../../../../../data/models/service_order_model.dart';
import '../../../../../data/providers/user_profile_provider.dart';
import '../../../../../services/service_service.dart';
import '../../../../../services/service_order_service.dart';
import '../../../common_widgets/app_drawer.dart';
import '../../../common_widgets/app_sidebar.dart';

class ServicesManagementScreen extends StatefulWidget {
  const ServicesManagementScreen({super.key});

  @override
  State<ServicesManagementScreen> createState() =>
      _ServicesManagementScreenState();
}

class _ServicesManagementScreenState extends State<ServicesManagementScreen> {
  final ServiceService _service = ServiceService();
  final ServiceOrderService _orderService = ServiceOrderService();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _recentOrdersExpanded = false;
  String? _error;
  List<Service> _services = const <Service>[];
  List<ServiceOrder> _recentOrders = const <ServiceOrder>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait<dynamic>([
        _service.fetchServices(activeOnly: false),
        _orderService.fetchRecentOrders(limit: 100),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _services = results[0] as List<Service>;
        _recentOrders = results[1] as List<ServiceOrder>;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openEditor({Service? initial}) async {
    final isManager = context.read<UserProfileProvider>().isManager;
    if (!isManager) {
      _showMessage('Seul le manager peut modifier les services.');
      return;
    }

    final nameCtrl = TextEditingController(text: initial?.name ?? '');
    final descCtrl = TextEditingController(text: initial?.description ?? '');
    final priceCtrl = TextEditingController(
      text: (initial?.price ?? 0).toStringAsFixed(2),
    );
    final durationCtrl = TextEditingController(
      text: initial?.durationMinutes?.toString() ?? '',
    );
    var active = initial?.isActive ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text(
                initial == null
                    ? 'Nouveau service (manager)'
                    : 'Modifier service (manager)',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Nom'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Prix'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: durationCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Duree (minutes, optionnel)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      value: active,
                      onChanged: (value) => setLocalState(() => active = value),
                      title: const Text('Actif'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) {
      return;
    }

    final name = nameCtrl.text.trim();
    final price = double.tryParse(priceCtrl.text.replaceAll(',', '.'));
    final duration = int.tryParse(durationCtrl.text.trim());
    if (name.isEmpty || price == null) {
      _showMessage('Nom et prix valides obligatoires.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final upserted = await _service.upsertService(
        Service(
          id: initial?.id ?? '',
          companyId: initial?.companyId ?? '',
          name: name,
          description: descCtrl.text.trim().isEmpty
              ? null
              : descCtrl.text.trim(),
          price: price,
          durationMinutes: duration,
          createdBy: initial?.createdBy,
          isActive: active,
          createdAt: initial?.createdAt ?? DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        final idx = _services.indexWhere((s) => s.id == upserted.id);
        if (idx >= 0) {
          _services = [..._services]..[idx] = upserted;
        } else {
          _services = [..._services, upserted];
        }
        _services.sort((a, b) => a.name.compareTo(b.name));
      });
    } catch (e) {
      _showMessage('Erreur sauvegarde: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteService(Service service) async {
    final isManager = context.read<UserProfileProvider>().isManager;
    if (!isManager) {
      _showMessage('Seul le manager peut supprimer les services.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer service'),
        content: Text('Confirmer la suppression de "${service.name}" ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _service.deleteService(service.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _services = _services.where((s) => s.id != service.id).toList();
      });
    } catch (e) {
      _showMessage('Erreur suppression: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.go('/sales');
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1120;
    final isManager = context.watch<UserProfileProvider>().isManager;

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              leading: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
              title: const Text('Gestion des services'),
            ),
      drawer: isDesktop ? null : const AppDrawer(),
      floatingActionButton: isManager
          ? FloatingActionButton.extended(
              onPressed: _isSaving ? null : () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Nouveau service'),
            )
          : FloatingActionButton.extended(
              onPressed: () => context.go('/beauty/orders/new'),
              icon: const Icon(Icons.receipt_long),
              label: const Text('Paiement + ticket'),
            ),
      body: Row(
        children: [
          if (isDesktop) const AppSidebar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (isDesktop)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _goBack,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Retour'),
                      ),
                    ),
                  if (!isManager)
                    const Card(
                      color: Color(0xFFE3F2FD),
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Mode caissier: consultation des services. Pour un client, utilisez le bouton Paiement + ticket.',
                        ),
                      ),
                    ),
                  if (_error != null)
                    Card(
                      color: const Color(0xFFFFF3E0),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!),
                      ),
                    ),
                  if (isManager) ...[
                    const SizedBox(height: 8),
                    Card(
                      child: ExpansionTile(
                        key: const PageStorageKey<String>(
                          'services_recent_orders_tile',
                        ),
                        initiallyExpanded: _recentOrdersExpanded,
                        onExpansionChanged: (expanded) {
                          setState(() => _recentOrdersExpanded = expanded);
                        },
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          12,
                          0,
                          12,
                          12,
                        ),
                        title: Text(
                          'Tickets clients effectues (services seller)',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        subtitle: Text(
                          _recentOrders.isEmpty
                              ? 'Aucun ticket service trouve.'
                              : '${_recentOrders.length} ticket(s) enregistre(s)',
                        ),
                        children: _recentOrders.isEmpty
                            ? const [
                                Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text('Aucun ticket service trouve.'),
                                  ),
                                ),
                              ]
                            : _recentOrders.map((order) {
                                final servicesLabel = order.items.isEmpty
                                    ? 'Sans details services'
                                    : order.items
                                          .map((item) => item.serviceName)
                                          .join(', ');

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    title: Text(
                                      '${order.clientName} | ${order.totalAmount.toStringAsFixed(2)}',
                                    ),
                                    subtitle: Text(
                                      '${DateFormat('dd/MM/yyyy HH:mm').format(order.createdAt)} | Caissier: ${order.cashierName ?? '-'}\n$servicesLabel',
                                    ),
                                    isThreeLine: true,
                                    trailing: Text(order.ticketNumber ?? '-'),
                                  ),
                                );
                              }).toList(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Catalogue des services',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (_services.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aucun service configure.'),
                      ),
                    )
                  else
                    ..._services.map(
                      (service) => Card(
                        child: ListTile(
                          title: Text(service.name),
                          subtitle: Text(
                            '${service.price.toStringAsFixed(2)} | ${service.durationMinutes ?? '-'} min | ${service.description ?? 'Sans description'}',
                          ),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              Chip(
                                label: Text(
                                  service.isActive ? 'Actif' : 'Inactif',
                                ),
                              ),
                              if (isManager)
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: _isSaving
                                      ? null
                                      : () => _openEditor(initial: service),
                                ),
                              if (isManager)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: _isSaving
                                      ? null
                                      : () => _deleteService(service),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
