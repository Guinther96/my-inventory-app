import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../data/models/service_order_model.dart';
import '../../../../data/models/stock_movement_model.dart';
import '../../../../data/models/user_profile_model.dart';
import '../../../../data/providers/inventory_provider.dart';
import '../../../../services/service_order_service.dart';
import '../../../../services/user_profile_service.dart';
import '../../../common_widgets/app_drawer.dart';
import '../../../common_widgets/app_sidebar.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final ServiceOrderService _serviceOrderService = ServiceOrderService();
  final UserProfileService _userProfileService = UserProfileService();

  bool _isClientsLoading = false;
  String? _clientsError;
  ClientActivitySummary? _clientSummary;

  bool _isSellersLoading = false;
  String? _sellersError;
  List<UserProfile> _companyUsers = const <UserProfile>[];
  String? _selectedSellerForDetails;

  @override
  void initState() {
    super.initState();
    _loadClientSummary();
    _loadCompanyUsers();
  }

  Future<void> _loadClientSummary() async {
    setState(() {
      _isClientsLoading = true;
      _clientsError = null;
    });

    try {
      final summary = await _serviceOrderService.fetchClientActivitySummary(
        activeWindowDays: 30,
      );

      if (!mounted) {
        return;
      }

      setState(() => _clientSummary = summary);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(
        () => _clientsError = e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _isClientsLoading = false);
      }
    }
  }

  Future<void> _loadCompanyUsers() async {
    setState(() {
      _isSellersLoading = true;
      _sellersError = null;
    });

    try {
      final users = await _userProfileService.fetchCompanyUsers();
      if (!mounted) {
        return;
      }

      setState(() => _companyUsers = users);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(
        () => _sellersError = e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _isSellersLoading = false);
      }
    }
  }

  List<_SellerSalesResult> _buildSellerSalesResults(
    InventoryProvider inventory,
  ) {
    final usersById = <String, UserProfile>{
      for (final user in _companyUsers) user.id: user,
    };

    final bySeller = <String, _SellerSalesAccumulator>{};

    for (final movement in inventory.movements) {
      if (movement.movementType != 'exit') {
        continue;
      }

      final sellerKey = _sellerKeyFor(movement);
      final product = inventory.findProductById(movement.productId);
      final lineRevenue = (product?.price ?? 0) * movement.quantity;

      final current = bySeller[sellerKey];
      if (current == null) {
        bySeller[sellerKey] = _SellerSalesAccumulator(
          salesCount: 1,
          totalQuantity: movement.quantity,
          totalRevenue: lineRevenue,
        );
      } else {
        bySeller[sellerKey] = _SellerSalesAccumulator(
          salesCount: current.salesCount + 1,
          totalQuantity: current.totalQuantity + movement.quantity,
          totalRevenue: current.totalRevenue + lineRevenue,
        );
      }
    }

    final results = bySeller.entries.map((entry) {
      final sellerId = entry.key;
      final acc = entry.value;
      final user = usersById[sellerId];
      final label = _sellerLabel(user, sellerId);

      return _SellerSalesResult(
        sellerId: sellerId,
        sellerLabel: label,
        salesCount: acc.salesCount,
        totalQuantity: acc.totalQuantity,
        totalRevenue: acc.totalRevenue,
      );
    }).toList()..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

    return results;
  }

  String _sellerKeyFor(StockMovement movement) {
    final sellerId = movement.sellerId?.trim();
    if (sellerId != null && sellerId.isNotEmpty) {
      return sellerId;
    }

    final userId = movement.userId?.trim();
    if (userId != null && userId.isNotEmpty) {
      return userId;
    }

    return 'unknown';
  }

  String _sellerLabel(UserProfile? user, String sellerId) {
    if (user != null) {
      if (user.email.trim().isNotEmpty) {
        return user.email;
      }
      return user.id;
    }

    if (sellerId == 'unknown') {
      return 'Seller inconnu';
    }

    final shortId = sellerId.length > 8 ? sellerId.substring(0, 8) : sellerId;
    return 'Seller $shortId';
  }

  Future<List<ServiceOrder>> _loadSellerServiceOrders(String sellerId) async {
    try {
      if (sellerId.trim().isEmpty || sellerId == 'unknown') {
        return const <ServiceOrder>[];
      }

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        return const <ServiceOrder>[];
      }

      final row = await Supabase.instance.client
          .from('users')
          .select('company_id')
          .eq('id', userId)
          .maybeSingle();
      final companyId = row?['company_id']?.toString();

      if (companyId == null) {
        return const <ServiceOrder>[];
      }

      final rows = await Supabase.instance.client
          .from('service_orders')
          .select()
          .eq('company_id', companyId)
          .eq('cashier_id', sellerId)
          .order('created_at', ascending: false);

      return (rows as List<dynamic>)
          .map(
            (row) =>
                ServiceOrder.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
    } catch (_) {
      return const <ServiceOrder>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 950;
    final horizontalPadding = isDesktop ? 24.0 : 14.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: isDesktop ? null : AppBar(title: const Text('Rapports')),
      drawer: isDesktop ? null : const AppDrawer(),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) const AppSidebar(),
          Expanded(
            child: Consumer<InventoryProvider>(
              builder: (context, inventory, _) {
                final lowStock = inventory.lowStockProducts;
                final totalMovements = inventory.movements.length;
                final sellerResults = _buildSellerSalesResults(inventory);

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    20,
                    horizontalPadding,
                    18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rapports de stock',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _ReportCard(
                            title: 'Produits references',
                            value: inventory.totalProducts.toString(),
                            icon: Icons.inventory,
                            color: const Color(0xFF0C7EA5),
                          ),
                          _ReportCard(
                            title: 'Articles en stock',
                            value: inventory.totalItemsInStock.toString(),
                            icon: Icons.warehouse,
                            color: const Color(0xFF2563EB),
                          ),
                          _ReportCard(
                            title: 'Valeur totale stock',
                            value:
                                '${inventory.totalStockValue.toStringAsFixed(2)} Gdes',
                            icon: Icons.payments,
                            color: const Color(0xFF15803D),
                          ),
                          _ReportCard(
                            title: 'Mouvements enregistres',
                            value: totalMovements.toString(),
                            icon: Icons.sync_alt,
                            color: const Color(0xFFD97706),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Produits en alerte de stock (${lowStock.length})',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
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
                        child: lowStock.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('Aucune alerte de stock.'),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: lowStock.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final p = lowStock[index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    leading: const Icon(
                                      Icons.warning_amber_rounded,
                                      color: Colors.orange,
                                    ),
                                    title: Text(p.name),
                                    subtitle: Text(
                                      'Stock actuel: ${p.quantityInStock} | Seuil: ${p.minStockAlert}',
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Resultats des sellers',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
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
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _isSellersLoading
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(10),
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : _sellersError != null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _sellersError!,
                                      style: TextStyle(
                                        color: colorScheme.error,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      onPressed: _loadCompanyUsers,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Reessayer'),
                                    ),
                                  ],
                                )
                              : _SellerResultsSection(
                                  results: sellerResults,
                                  onLoadSellerServices:
                                      _loadSellerServiceOrders,
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Clients actifs / inactifs',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
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
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _isClientsLoading
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(10),
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : _clientsError != null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _clientsError!,
                                      style: TextStyle(
                                        color: colorScheme.error,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      onPressed: _loadClientSummary,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Reessayer'),
                                    ),
                                  ],
                                )
                              : _ClientActivitySection(
                                  summary: _clientSummary,
                                  onRefresh: _loadClientSummary,
                                ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerSalesAccumulator {
  final int salesCount;
  final int totalQuantity;
  final double totalRevenue;

  const _SellerSalesAccumulator({
    required this.salesCount,
    required this.totalQuantity,
    required this.totalRevenue,
  });
}

class _SellerSalesResult {
  final String sellerId;
  final String sellerLabel;
  final int salesCount;
  final int totalQuantity;
  final double totalRevenue;

  const _SellerSalesResult({
    required this.sellerId,
    required this.sellerLabel,
    required this.salesCount,
    required this.totalQuantity,
    required this.totalRevenue,
  });
}

class _SellerResultsSection extends StatefulWidget {
  final List<_SellerSalesResult> results;
  final Future<List<ServiceOrder>> Function(String) onLoadSellerServices;

  const _SellerResultsSection({
    required this.results,
    required this.onLoadSellerServices,
  });

  @override
  State<_SellerResultsSection> createState() => _SellerResultsSectionState();
}

enum _SellerSortKey { revenue, salesCount, quantity }

class _SellerResultsSectionState extends State<_SellerResultsSection> {
  _SellerSortKey _sortKey = _SellerSortKey.revenue;

  @override
  Widget build(BuildContext context) {
    if (widget.results.isEmpty) {
      return const Text('Aucune vente seller disponible pour le moment.');
    }

    final sortedResults = [...widget.results]
      ..sort((a, b) {
        switch (_sortKey) {
          case _SellerSortKey.salesCount:
            return b.salesCount.compareTo(a.salesCount);
          case _SellerSortKey.quantity:
            return b.totalQuantity.compareTo(a.totalQuantity);
          case _SellerSortKey.revenue:
            return b.totalRevenue.compareTo(a.totalRevenue);
        }
      });

    final totalSalesCount = sortedResults.fold<int>(
      0,
      (sum, item) => sum + item.salesCount,
    );
    final totalQuantity = sortedResults.fold<int>(
      0,
      (sum, item) => sum + item.totalQuantity,
    );
    final totalRevenue = sortedResults.fold<double>(
      0,
      (sum, item) => sum + item.totalRevenue,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              Text(
                'Sellers: ${sortedResults.length}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Ventes: $totalSalesCount',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Quantité: $totalQuantity',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'CA: ${totalRevenue.toStringAsFixed(2)} Gdes',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Trier: CA'),
              selected: _sortKey == _SellerSortKey.revenue,
              onSelected: (_) {
                setState(() => _sortKey = _SellerSortKey.revenue);
              },
            ),
            ChoiceChip(
              label: const Text('Trier: Ventes'),
              selected: _sortKey == _SellerSortKey.salesCount,
              onSelected: (_) {
                setState(() => _sortKey = _SellerSortKey.salesCount);
              },
            ),
            ChoiceChip(
              label: const Text('Trier: Quantité'),
              selected: _sortKey == _SellerSortKey.quantity,
              onSelected: (_) {
                setState(() => _sortKey = _SellerSortKey.quantity);
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sortedResults.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final row = sortedResults[index];
            return _SellerResultCard(
              rank: index + 1,
              result: row,
              onViewDetails: () => _showSellerDetailsModal(context, row),
            );
          },
        ),
      ],
    );
  }

  Future<void> _showSellerDetailsModal(
    BuildContext context,
    _SellerSalesResult seller,
  ) async {
    final ordersFuture = widget.onLoadSellerServices(seller.sellerId);

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Détails - ${seller.sellerLabel}'),
          content: SizedBox(
            width: 520,
            child: FutureBuilder<List<ServiceOrder>>(
              future: ordersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 140,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return const SizedBox(
                    height: 140,
                    child: Center(
                      child: Text('Impossible de charger les détails seller.'),
                    ),
                  );
                }

                final serviceOrders = snapshot.data ?? const <ServiceOrder>[];
                final firstOrderTime = serviceOrders.isNotEmpty
                    ? serviceOrders.last.createdAt
                    : null;
                final lastOrderTime = serviceOrders.isNotEmpty
                    ? serviceOrders.first.createdAt
                    : null;

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Résumé ventes',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('Nombre de ventes: ${seller.salesCount}'),
                      Text('Quantité totale: ${seller.totalQuantity}'),
                      Text(
                        'CA total: ${seller.totalRevenue.toStringAsFixed(2)} Gdes',
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Horaires d\'activités',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (firstOrderTime != null)
                        Text(
                          'Première connexion: ${_formatDateTime(firstOrderTime)}',
                        )
                      else
                        const Text('Pas de première connexion'),
                      if (lastOrderTime != null)
                        Text(
                          'Dernière activité: ${_formatDateTime(lastOrderTime)}',
                        )
                      else
                        const Text('Pas de dernière activité'),
                      const SizedBox(height: 16),
                      Text(
                        'Services effectués (${serviceOrders.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (serviceOrders.isEmpty)
                        const Text('Aucun service enregistré.')
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 300),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: serviceOrders.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final order = serviceOrders[index];
                              final servicesLabel = order.items.isEmpty
                                  ? 'Sans details services'
                                  : order.items
                                        .map((item) => item.serviceName)
                                        .join(', ');

                              return ListTile(
                                dense: true,
                                title: Text(
                                  '${order.clientName} - ${order.totalAmount.toStringAsFixed(2)} Gdes',
                                ),
                                subtitle: Text(
                                  '${_formatDateTime(order.createdAt)}\n$servicesLabel',
                                ),
                                isThreeLine: true,
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _SellerResultCard extends StatelessWidget {
  final int rank;
  final _SellerSalesResult result;
  final VoidCallback onViewDetails;

  const _SellerResultCard({
    required this.rank,
    required this.result,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.secondaryContainer,
              foregroundColor: colorScheme.onSecondaryContainer,
              child: Text('$rank'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.sellerLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ventes: ${result.salesCount}  •  Quantité: ${result.totalQuantity}',
                    style: const TextStyle(color: Color(0xFF617287)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${result.totalRevenue.toStringAsFixed(2)} Gdes',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: onViewDetails,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Voir détails'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientActivitySection extends StatelessWidget {
  final ClientActivitySummary? summary;
  final VoidCallback onRefresh;

  const _ClientActivitySection({
    required this.summary,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final data = summary;
    if (data == null) {
      return const Text('Donnees clients indisponibles.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _ReportCard(
                title: 'Clients actifs (${data.activeWindowDays}j)',
                value: data.activeCount.toString(),
                icon: Icons.check_circle,
                color: const Color(0xFF15803D),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ReportCard(
                title: 'Clients inactifs',
                value: data.inactiveCount.toString(),
                icon: Icons.remove_circle_outline,
                color: const Color(0xFFDC2626),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Total clients: ${data.totalClients}',
          style: const TextStyle(color: Color(0xFF617287)),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          title: Text('Clients actifs (${data.activeCount})'),
          initiallyExpanded: data.activeClients.isNotEmpty,
          children: data.activeClients.isEmpty
              ? const [
                  ListTile(
                    dense: true,
                    title: Text('Aucun client actif sur la periode.'),
                  ),
                ]
              : data.activeClients
                    .map(
                      (client) => ListTile(
                        dense: true,
                        title: Text(client.fullName),
                        subtitle: Text(client.phone ?? 'Sans telephone'),
                        leading: const Icon(
                          Icons.circle,
                          size: 10,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    )
                    .toList(),
        ),
        ExpansionTile(
          title: Text('Clients inactifs (${data.inactiveCount})'),
          children: data.inactiveClients.isEmpty
              ? const [
                  ListTile(dense: true, title: Text('Aucun client inactif.')),
                ]
              : data.inactiveClients
                    .map(
                      (client) => ListTile(
                        dense: true,
                        title: Text(client.fullName),
                        subtitle: Text(client.phone ?? 'Sans telephone'),
                        leading: const Icon(
                          Icons.circle,
                          size: 10,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    )
                    .toList(),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualiser'),
          ),
        ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _ReportCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color.withValues(alpha: 0.16)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x100D1B2A),
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.14),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(color: Color(0xFF617287))),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
