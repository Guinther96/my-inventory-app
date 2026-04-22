import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../data/models/service_model.dart';
import '../../../../../data/models/service_order_model.dart';
import '../../../../../data/providers/user_profile_provider.dart';
import '../../../../../services/service_orders/service_service.dart';
import '../../../../../services/service_orders/service_order_service.dart';
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
  RealtimeChannel? _realtimeChannel;
  Timer? _realtimeDebounce;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  List<Service> _services = const <Service>[];
  List<ServiceOrder> _recentOrders = const <ServiceOrder>[];
  String? _selectedRecentOrderId;

  @override
  void initState() {
    super.initState();
    _load();
    unawaited(_initRealtime());
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    final channel = _realtimeChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  Future<void> _initRealtime() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      return;
    }

    try {
      final row = await client
          .from('users')
          .select('company_id')
          .eq('id', userId)
          .maybeSingle();

      final companyId = row?['company_id']?.toString();
      if (!mounted || companyId == null || companyId.isEmpty) {
        return;
      }

      final existing = _realtimeChannel;
      if (existing != null) {
        client.removeChannel(existing);
      }

      _realtimeChannel = client
          .channel('services-management-$companyId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'services',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'company_id',
              value: companyId,
            ),
            callback: (_) => _scheduleRealtimeLoad(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'service_orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'company_id',
              value: companyId,
            ),
            callback: (_) => _scheduleRealtimeLoad(),
          )
          .subscribe();
    } catch (_) {
      // L'ecran reste utilisable en rafraichissement manuel si Realtime echoue.
    }
  }

  void _scheduleRealtimeLoad() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted && !_isLoading && !_isSaving) {
        unawaited(_load());
      }
    });
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
        if (_recentOrders.isEmpty) {
          _selectedRecentOrderId = null;
        } else {
          final hasSelection =
              _selectedRecentOrderId != null &&
              _recentOrders.any((order) => order.id == _selectedRecentOrderId);
          _selectedRecentOrderId = hasSelection
              ? _selectedRecentOrderId
              : _recentOrders.first.id;
        }
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

  ServiceOrder? _selectedRecentOrder() {
    if (_recentOrders.isEmpty) {
      return null;
    }
    final selectedId = _selectedRecentOrderId;
    if (selectedId == null) {
      return _recentOrders.first;
    }
    for (final order in _recentOrders) {
      if (order.id == selectedId) {
        return order;
      }
    }
    return _recentOrders.first;
  }

  String _orderMenuLabel(ServiceOrder order) {
    final amount = order.totalAmount.toStringAsFixed(2);
    final date = DateFormat('dd/MM HH:mm').format(order.createdAt);
    return '${order.clientName} • $amount Gdes • $date';
  }

  Future<void> _openRecentTicketsPicker() async {
    if (_recentOrders.isEmpty) {
      return;
    }

    final selectedOrder = _selectedRecentOrder();
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _recentOrders.where((order) {
              if (query.trim().isEmpty) {
                return true;
              }
              final lower = query.trim().toLowerCase();
              final services = order.items
                  .map((item) => item.serviceName)
                  .join(' ')
                  .toLowerCase();
              final haystack =
                  '${order.clientName} ${order.cashierName ?? ''} ${order.ticketNumber ?? ''} $services'
                      .toLowerCase();
              return haystack.contains(lower);
            }).toList();

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x2A0B1A2A),
                        blurRadius: 28,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 5,
                        margin: const EdgeInsets.only(top: 10),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).textTheme.bodySmall?.color?.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.receipt_long,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Selectionner un ticket',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                        child: TextField(
                          onChanged: (value) {
                            setModalState(() => query = value);
                          },
                          decoration: InputDecoration(
                            hintText: 'Rechercher client, ticket, service...',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor:
                                Theme.of(
                                  context,
                                ).inputDecorationTheme.fillColor ??
                                Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.06),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        child: filtered.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'Aucun ticket correspondant.',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.color
                                        ?.withValues(alpha: 0.7),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final order = filtered[index];
                                  final isSelected =
                                      order.id == selectedOrder?.id;
                                  return ListTile(
                                    onTap: () =>
                                        Navigator.of(context).pop(order.id),
                                    leading: CircleAvatar(
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.14),
                                      child: Icon(
                                        Icons.person,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                    title: Text(
                                      order.clientName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Ticket ${order.ticketNumber ?? '-'} • ${DateFormat('dd/MM/yyyy HH:mm').format(order.createdAt)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: isSelected
                                        ? Icon(
                                            Icons.check_circle,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          )
                                        : Text(
                                            '${order.totalAmount.toStringAsFixed(2)} Gdes',
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.color
                                                  ?.withValues(alpha: 0.7),
                                            ),
                                          ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || selectedId == null) {
      return;
    }

    setState(() => _selectedRecentOrderId = selectedId);
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
                    Text(
                      'Tickets clients effectues (services caissier)',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (_recentOrders.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Aucun ticket service trouve.'),
                        ),
                      )
                    else ...[
                      Builder(
                        builder: (context) {
                          final selectedOrder = _selectedRecentOrder();
                          final servicesLabel =
                              selectedOrder == null ||
                                  selectedOrder.items.isEmpty
                              ? 'Sans details services'
                              : selectedOrder.items
                                    .map((item) => item.serviceName)
                                    .join(', ');

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF102A43),
                                      Color(0xFF1E3A5F),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x1F0B1A2A),
                                      blurRadius: 18,
                                      offset: Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: InkWell(
                                  onTap: _openRecentTicketsPicker,
                                  borderRadius: BorderRadius.circular(14),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.filter_list,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Ticket selectionne',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              selectedOrder == null
                                                  ? 'Choisir un ticket'
                                                  : _orderMenuLabel(
                                                      selectedOrder,
                                                    ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.expand_more,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (selectedOrder != null) ...[
                                const SizedBox(height: 10),
                                Card(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                selectedOrder.clientName,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withValues(alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                '${selectedOrder.totalAmount.toStringAsFixed(2)} Gdes',
                                                style: TextStyle(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Ticket: ${selectedOrder.ticketNumber ?? '-'} • ${DateFormat('dd/MM/yyyy HH:mm').format(selectedOrder.createdAt)}',
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Caissier: ${selectedOrder.cashierName ?? '-'}',
                                        ),
                                        const SizedBox(height: 8),
                                        ...selectedOrder.items.map(
                                          (item) => Padding(
                                            padding: const EdgeInsets.only(bottom: 4),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.spa_outlined, size: 14),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    item.serviceName,
                                                    style: const TextStyle(fontSize: 13),
                                                  ),
                                                ),
                                                if (item.providerName != null &&
                                                    item.providerName!.isNotEmpty)
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.person_outline, size: 13),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        item.providerName!,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Theme.of(context)
                                                              .colorScheme
                                                              .primary,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
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
                            '${service.price.toStringAsFixed(2)} Gdes | ${service.durationMinutes ?? '-'} min | ${service.description ?? 'Sans description'}',
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
