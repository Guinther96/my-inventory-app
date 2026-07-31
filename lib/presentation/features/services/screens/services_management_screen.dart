import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../core/utils/currency.dart';
import '../../../../../data/models/service_category_model.dart';
import '../../../../../data/models/service_model.dart';
import '../../../../../data/models/service_order_model.dart';
import '../../../../../data/providers/user_profile_provider.dart';
import '../../../../../services/service_orders/service_category_service.dart';
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
  final ServiceCategoryService _categoryService = ServiceCategoryService();
  final ServiceOrderService _orderService = ServiceOrderService();
  RealtimeChannel? _realtimeChannel;
  Timer? _realtimeDebounce;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  List<Service> _services = const <Service>[];
  List<ServiceCategory> _categories = const <ServiceCategory>[];
  List<ServiceOrder> _recentOrders = const <ServiceOrder>[];
  String? _selectedRecentOrderId;

  /// Categorie active pour filtrer le catalogue ci-dessous. Null = "Toutes".
  String? _selectedCategoryId;

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
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'service_categories',
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
        _categoryService.fetchCategories(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _services = results[0] as List<Service>;
        _recentOrders = results[1] as List<ServiceOrder>;
        _categories = (results[2] as List<ServiceCategory>)
          ..sort((a, b) => a.name.compareTo(b.name));
        if (_selectedCategoryId != null &&
            !_categories.any((c) => c.id == _selectedCategoryId)) {
          _selectedCategoryId = null;
        }
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

  List<Service> get _filteredServices {
    final categoryId = _selectedCategoryId;
    if (categoryId == null) {
      return _services;
    }
    return _services.where((s) => s.categoryId == categoryId).toList();
  }

  String _categoryNameFor(String? categoryId) {
    if (categoryId == null) {
      return 'Sans categorie';
    }
    final matches = _categories.where((c) => c.id == categoryId).toList();
    return matches.isEmpty ? 'Sans categorie' : matches.first.name;
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
    var selectedCurrency = normalizeCurrencyCode(initial?.currency);
    var selectedCategoryId = initial?.categoryId;
    // Un service existant deja sans categorie (donnees anterieures a cette
    // fonctionnalite) peut rester tel quel; un nouveau service doit en
    // choisir une.
    final allowUncategorized = initial != null && initial.categoryId == null;

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
                    DropdownButtonFormField<String>(
                      value: selectedCurrency,
                      decoration: const InputDecoration(
                        labelText: 'Type de devise',
                      ),
                      items: kSupportedCurrencies
                          .map(
                            (code) => DropdownMenuItem<String>(
                              value: code,
                              child: Text(AppCurrency.fromCode(code).label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setLocalState(() => selectedCurrency = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      value: selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'Categorie *',
                      ),
                      items: [
                        if (allowUncategorized)
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Sans categorie (existant)'),
                          ),
                        ..._categories.map(
                          (c) => DropdownMenuItem<String?>(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setLocalState(() => selectedCategoryId = value);
                      },
                    ),
                    if (_categories.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Creez d\'abord une categorie de services.',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                          ),
                        ),
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
    if (selectedCategoryId == null && !allowUncategorized) {
      _showMessage('La categorie est obligatoire.');
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
          currency: selectedCurrency,
          durationMinutes: duration,
          createdBy: initial?.createdBy,
          isActive: active,
          categoryId: selectedCategoryId,
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
    final amount = formatMoney(order.totalAmount, order.paymentCurrency);
    final date = DateFormat('dd/MM HH:mm').format(order.createdAt);
    return '${order.clientName} • $amount • $date';
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
                                            formatMoney(
                                              order.totalAmount,
                                              order.paymentCurrency,
                                            ),
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
                                                formatMoney(
                                                  selectedOrder.totalAmount,
                                                  selectedOrder.paymentCurrency,
                                                ),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Categories',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (isManager)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton.icon(
                              onPressed: () =>
                                  context.push('/beauty/service-categories'),
                              icon: const Icon(Icons.settings_outlined),
                              label: const Text('Gerer'),
                            ),
                            const SizedBox(width: 4),
                            FilledButton.tonalIcon(
                              onPressed: () =>
                                  context.push('/beauty/service-categories'),
                              icon: const Icon(Icons.add),
                              label: const Text('Nouvelle categorie'),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _CategoryFilterRow(
                    categories: _categories,
                    services: _services,
                    selectedCategoryId: _selectedCategoryId,
                    onSelected: (categoryId) =>
                        setState(() => _selectedCategoryId = categoryId),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Catalogue des services',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (_filteredServices.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aucun service configure.'),
                      ),
                    )
                  else
                    ..._filteredServices.map(
                      (service) => Card(
                        child: ListTile(
                          title: Text(service.name),
                          subtitle: Text(
                            '${formatMoney(service.price, service.currency)} | '
                            '${service.durationMinutes ?? '-'} min | '
                            '${_categoryNameFor(service.categoryId)}',
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

/// Rangee horizontale de cartes categories (avec compteur) pour filtrer le
/// catalogue de services ci-dessous. Une carte "Toutes" reinitialise le
/// filtre.
class _CategoryFilterRow extends StatelessWidget {
  final List<ServiceCategory> categories;
  final List<Service> services;
  final String? selectedCategoryId;
  final ValueChanged<String?> onSelected;

  const _CategoryFilterRow({
    required this.categories,
    required this.services,
    required this.selectedCategoryId,
    required this.onSelected,
  });

  int _countFor(String? categoryId) => categoryId == null
      ? services.length
      : services.where((s) => s.categoryId == categoryId).length;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const Text(
        'Aucune categorie: creez-en une pour organiser vos services.',
        style: TextStyle(color: Color(0xFF617287)),
      );
    }

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length + 1,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _CategoryFilterCard(
              label: 'Toutes',
              count: _countFor(null),
              selected: selectedCategoryId == null,
              onTap: () => onSelected(null),
            );
          }
          final category = categories[index - 1];
          return _CategoryFilterCard(
            label: category.name,
            count: _countFor(category.id),
            selected: selectedCategoryId == category.id,
            onTap: () => onSelected(category.id),
          );
        },
      ),
    );
  }
}

class _CategoryFilterCard extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryFilterCard({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? colorScheme.primary
                : colorScheme.outlineVariant,
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.spa_outlined,
              color: selected ? Colors.white : colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$count service${count > 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: selected
                    ? Colors.white.withValues(alpha: 0.85)
                    : theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
