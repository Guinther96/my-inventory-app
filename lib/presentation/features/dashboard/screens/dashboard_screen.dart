import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../data/models/service_order_model.dart';
import '../../../../data/models/stock_movement_model.dart';
import '../../../../data/providers/inventory_provider.dart';
import '../../../../data/providers/user_profile_provider.dart';
import '../../../../services/service_orders/service_order_service.dart';
import '../../../common_widgets/app_drawer.dart';
import '../../../common_widgets/app_sidebar.dart';

/// Ecran dashboard modernise avec:
/// - En-tete hero
/// - Cartes KPI visuelles
/// - Liste d'activites recente amelioree
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedSalesWindowDays = 7;
  int _selectedVisitsWindowDays = 7;
  String? _selectedRecentMovementId;
  final ServiceOrderService _serviceOrderService = ServiceOrderService();
  RealtimeChannel? _serviceOrdersRealtimeChannel;
  Timer? _visitsRealtimeDebounce;

  List<ServiceOrder> _serviceOrders = const <ServiceOrder>[];
  bool _isVisitsLoading = false;
  String? _visitsError;

  @override
  void initState() {
    super.initState();
    _loadServiceVisits();
    _initVisitsRealtime();
  }

  @override
  void dispose() {
    _visitsRealtimeDebounce?.cancel();
    final channel = _serviceOrdersRealtimeChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  Future<void> _initVisitsRealtime() async {
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

      final previousChannel = _serviceOrdersRealtimeChannel;
      if (previousChannel != null) {
        client.removeChannel(previousChannel);
      }

      _serviceOrdersRealtimeChannel = client
          .channel('dashboard-service-orders-$companyId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'service_orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'company_id',
              value: companyId,
            ),
            callback: (_) {
              if (!mounted) {
                return;
              }

              _visitsRealtimeDebounce?.cancel();
              _visitsRealtimeDebounce = Timer(
                const Duration(milliseconds: 250),
                () {
                  if (mounted) {
                    _loadServiceVisits();
                  }
                },
              );
            },
          )
          .subscribe();
    } catch (_) {
      // Le dashboard continue de fonctionner en mode manuel si Realtime echoue.
    }
  }

  Future<void> _loadServiceVisits() async {
    setState(() {
      _isVisitsLoading = true;
      _visitsError = null;
    });

    try {
      final orders = await _serviceOrderService.fetchRecentOrders(
        limit: 600,
        includeItems: false,
      );
      if (!mounted) {
        return;
      }
      setState(() => _serviceOrders = orders);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(
        () => _visitsError = e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _isVisitsLoading = false);
      }
    }
  }

  /// Construit une série de points (un par jour) pour les ventes en Gourdes.
  ///
  /// Le calcul prend uniquement les mouvements de type `exit`.
  /// Montant d'une vente = prix produit courant x quantite sortie.
  List<_SalesPoint> _buildSalesSeries(
    InventoryProvider inventory, {
    required int days,
  }) {
    final now = DateTime.now();
    final firstDay = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));

    // Initialise chaque jour a 0 pour garantir un axe temporel stable.
    final totalsByDay = <DateTime, double>{
      for (int i = 0; i < days; i++) firstDay.add(Duration(days: i)): 0,
    };

    for (final movement in inventory.movements) {
      if (movement.movementType != 'exit') {
        continue;
      }

      final day = DateTime(
        movement.createdAt.year,
        movement.createdAt.month,
        movement.createdAt.day,
      );

      if (!totalsByDay.containsKey(day)) {
        continue;
      }

      final product = inventory.findProductById(movement.productId);
      final unitPrice = product?.price ?? 0;
      totalsByDay[day] =
          (totalsByDay[day] ?? 0) + (unitPrice * movement.quantity);
    }

    return totalsByDay.entries
        .map(
          (entry) => _SalesPoint(
            day: entry.key,
            label: _dayLabel(entry.key, days: days),
            amount: entry.value,
          ),
        )
        .toList();
  }

  /// Retourne un label compact pour l'axe X.
  ///
  /// - 7 jours: nom du jour (Lun, Mar...)
  /// - 30/90 jours: date compacte (jj/mm)
  String _dayLabel(DateTime day, {required int days}) {
    if (days == 7) {
      return switch (day.weekday) {
        DateTime.monday => 'Lun',
        DateTime.tuesday => 'Mar',
        DateTime.wednesday => 'Mer',
        DateTime.thursday => 'Jeu',
        DateTime.friday => 'Ven',
        DateTime.saturday => 'Sam',
        DateTime.sunday => 'Dim',
        _ => '-',
      };
    }

    final d = day.day.toString().padLeft(2, '0');
    final m = day.month.toString().padLeft(2, '0');
    return '$d/$m';
  }

  List<_VisitsPoint> _buildVisitsSeries({required int days}) {
    final now = DateTime.now();
    final firstDay = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));

    final visitsByDay = <DateTime, int>{
      for (int i = 0; i < days; i++) firstDay.add(Duration(days: i)): 0,
    };

    for (final order in _serviceOrders) {
      final day = DateTime(
        order.createdAt.year,
        order.createdAt.month,
        order.createdAt.day,
      );

      if (!visitsByDay.containsKey(day)) {
        continue;
      }

      visitsByDay[day] = (visitsByDay[day] ?? 0) + 1;
    }

    return visitsByDay.entries
        .map(
          (entry) => _VisitsPoint(
            day: entry.key,
            label: _dayLabel(entry.key, days: days),
            visits: entry.value,
          ),
        )
        .toList();
  }

  String _movementDropdownKey(StockMovement movement, int index) {
    final rawId = movement.id.trim();
    final stableId = rawId.isNotEmpty ? rawId : 'missing';

    // Always include index to guarantee unique values, even with duplicate IDs.
    return 'id:$stableId:ts:${movement.createdAt.microsecondsSinceEpoch}:i:$index';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 950;
    final horizontalPadding = isDesktop ? 28.0 : 16.0;
    final isManager = context.watch<UserProfileProvider>().isManager;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: isDesktop ? null : AppBar(title: const Text('Tableau de bord')),
      drawer: isDesktop ? null : const AppDrawer(),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) const AppSidebar(),
          Expanded(
            child: Consumer<InventoryProvider>(
              builder: (context, inventory, _) {
                final recent = inventory.recentMovements.take(10).toList();
                final recentOptions = recent.asMap().entries.map((entry) {
                  return (
                    key: _movementDropdownKey(entry.value, entry.key),
                    movement: entry.value,
                  );
                }).toList();
                final selectedRecentMovement = recent.isEmpty
                    ? null
                    : recentOptions.firstWhere(
                        (option) => option.key == _selectedRecentMovementId,
                        orElse: () => recentOptions.first,
                      );
                final selectedRecentMovementOptionKey =
                    selectedRecentMovement?.key;
                final salesSeries = _buildSalesSeries(
                  inventory,
                  days: _selectedSalesWindowDays,
                );
                final visitsSeries = _buildVisitsSeries(
                  days: _selectedVisitsWindowDays,
                );

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    20,
                    horizontalPadding,
                    24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DashboardHero(
                        companyName: inventory.companyName,
                        totalProducts: inventory.totalProducts,
                        lowStockCount: inventory.lowStockProducts.length,
                        totalStockValue: inventory.totalStockValue,
                        onNewMovement: isManager
                            ? () => context.go('/movements')
                            : null,
                      ),
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final cardWidth = isDesktop
                              ? (constraints.maxWidth - 32) / 3
                              : constraints.maxWidth;

                          return Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              _ModernSummaryCard(
                                width: cardWidth,
                                title: 'Produits au total',
                                value: inventory.totalProducts.toString(),
                                subtitle: 'Articles disponibles en catalogue',
                                icon: Icons.inventory_2_rounded,
                                accent: const Color(0xFF0C7EA5),
                              ),
                              _ModernSummaryCard(
                                width: cardWidth,
                                title: 'Stock faible',
                                value: inventory.lowStockProducts.length
                                    .toString(),
                                subtitle: 'Produits a reapprovisionner',
                                icon: Icons.warning_amber_rounded,
                                accent: const Color(0xFFD97706),
                              ),
                              _ModernSummaryCard(
                                width: cardWidth,
                                title: 'Valeur du stock',
                                value:
                                    '${inventory.totalStockValue.toStringAsFixed(2)} Gdes',
                                subtitle: 'Valeur globale des articles',
                                icon: Icons.account_balance_wallet_rounded,
                                accent: const Color(0xFF15803D),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _SalesChartCard(
                        points: salesSeries,
                        days: _selectedSalesWindowDays,
                        onDaysChanged: (days) {
                          setState(() => _selectedSalesWindowDays = days);
                        },
                      ),
                      const SizedBox(height: 20),
                      _VisitsChartCard(
                        points: visitsSeries,
                        days: _selectedVisitsWindowDays,
                        isLoading: _isVisitsLoading,
                        error: _visitsError,
                        onDaysChanged: (days) {
                          setState(() => _selectedVisitsWindowDays = days);
                        },
                        onRetry: _loadServiceVisits,
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Text(
                            'Activites recentes',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${recent.length}',
                              style: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
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
                        child: recent.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: Text('Aucun mouvement pour le moment.'),
                              )
                            : Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    DropdownButtonFormField<String>(
                                      value: selectedRecentMovementOptionKey,
                                      decoration: const InputDecoration(
                                        labelText: 'Choisir une activite',
                                        prefixIcon: Icon(Icons.history),
                                      ),
                                      items: recentOptions.map((option) {
                                        final movement = option.movement;
                                        final productName = inventory
                                            .productNameFor(movement.productId);
                                        return DropdownMenuItem<String>(
                                          value: option.key,
                                          child: Text(
                                            '$productName • ${movement.quantity}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (value) {
                                        setState(
                                          () =>
                                              _selectedRecentMovementId = value,
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    if (selectedRecentMovement != null)
                                      _ActivityTile(
                                        productName: inventory.productNameFor(
                                          selectedRecentMovement
                                              .movement
                                              .productId,
                                        ),
                                        notes: selectedRecentMovement
                                            .movement
                                            .notes,
                                        movementType: selectedRecentMovement
                                            .movement
                                            .movementType,
                                        quantity: selectedRecentMovement
                                            .movement
                                            .quantity,
                                        createdAt: selectedRecentMovement
                                            .movement
                                            .createdAt,
                                      ),
                                  ],
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
      floatingActionButton: isManager
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/movements'),
              icon: const Icon(Icons.sync_alt),
              label: const Text('Nouveau mouvement'),
            )
          : null,
    );
  }
}

/// Donnee d'un point de vente pour un jour donne.
class _SalesPoint {
  final DateTime day;
  final String label;
  final double amount;

  const _SalesPoint({
    required this.day,
    required this.label,
    required this.amount,
  });
}

class _VisitsPoint {
  final DateTime day;
  final String label;
  final int visits;

  const _VisitsPoint({
    required this.day,
    required this.label,
    required this.visits,
  });
}

class _VisitsChartCard extends StatelessWidget {
  final List<_VisitsPoint> points;
  final int days;
  final bool isLoading;
  final String? error;
  final ValueChanged<int> onDaysChanged;
  final VoidCallback onRetry;

  const _VisitsChartCard({
    required this.points,
    required this.days,
    required this.isLoading,
    required this.error,
    required this.onDaysChanged,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final totalVisits = points.fold<int>(0, (sum, p) => sum + p.visits);
    final maxVisits = points.fold<int>(0, (max, p) {
      return p.visits > max ? p.visits : max;
    });

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
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Visites clients (services)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Evolution des tickets services effectues.',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _PeriodChip(
                label: '7j',
                selected: days == 7,
                onTap: () => onDaysChanged(7),
              ),
              const SizedBox(width: 6),
              _PeriodChip(
                label: '30j',
                selected: days == 30,
                onTap: () => onDaysChanged(30),
              ),
              const SizedBox(width: 6),
              _PeriodChip(
                label: '90j',
                selected: days == 90,
                onTap: () => onDaysChanged(90),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$totalVisits visites',
                  style: TextStyle(
                    color: colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (isLoading)
            const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (error != null)
            SizedBox(
              height: 160,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error!),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: onRetry,
                      child: const Text('Reessayer'),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 196,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const reservedHeight = 56.0;
                  final maxBarHeight = (constraints.maxHeight - reservedHeight)
                      .clamp(10.0, constraints.maxHeight);
                  final safeMax = maxVisits <= 0 ? 1 : maxVisits;

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: points.map((point) {
                      final ratio = (point.visits / safeMax).clamp(0.0, 1.0);
                      final barHeight = ratio == 0
                          ? 4.0
                          : (ratio * maxBarHeight);

                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                point.visits.toString(),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeOutCubic,
                                height: barHeight,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF86EFAC),
                                      Color(0xFF16A34A),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                point.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Carte graphique affichant les ventes des 7 derniers jours.
class _SalesChartCard extends StatelessWidget {
  final List<_SalesPoint> points;
  final int days;
  final ValueChanged<int> onDaysChanged;

  const _SalesChartCard({
    required this.points,
    required this.days,
    required this.onDaysChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final total = points.fold<double>(0, (sum, p) => sum + p.amount);
    final maxAmount = points.fold<double>(0, (max, p) {
      return p.amount > max ? p.amount : max;
    });

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
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ventes',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Evolution quotidienne des sorties en Gourdes.',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _PeriodChip(
                label: '7j',
                selected: days == 7,
                onTap: () => onDaysChanged(7),
              ),
              const SizedBox(width: 6),
              _PeriodChip(
                label: '30j',
                selected: days == 30,
                onTap: () => onDaysChanged(30),
              ),
              const SizedBox(width: 6),
              _PeriodChip(
                label: '90j',
                selected: days == 90,
                onTap: () => onDaysChanged(90),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_compact(total)} Gdes',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 196,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Reserve de la place pour les labels haut/bas afin d'eviter
                // tout overflow vertical quand la barre atteint son maximum.
                const reservedHeight = 56.0;
                final maxBarHeight = (constraints.maxHeight - reservedHeight)
                    .clamp(10.0, constraints.maxHeight);
                final safeMax = maxAmount <= 0 ? 1.0 : maxAmount;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: points.map((point) {
                    final ratio = (point.amount / safeMax).clamp(0.0, 1.0);
                    final barHeight = ratio == 0 ? 4.0 : (ratio * maxBarHeight);

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              point.amount <= 0 ? '0' : _compact(point.amount),
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOutCubic,
                              height: barHeight,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF25B6C6),
                                    Color(0xFF0C7EA5),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              point.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Formate une valeur numerique en style compact (k, M).
  static String _compact(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toStringAsFixed(0);
  }
}

/// Petit bouton de selection de periode pour le graphique.
class _PeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? colorScheme.onPrimary
                : colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// En-tete principal du dashboard avec un look moderne et action rapide.
class _DashboardHero extends StatelessWidget {
  final String companyName;
  final int totalProducts;
  final int lowStockCount;
  final double totalStockValue;
  final VoidCallback? onNewMovement;

  const _DashboardHero({
    required this.companyName,
    required this.totalProducts,
    required this.lowStockCount,
    required this.totalStockValue,
    required this.onNewMovement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFF0C7EA5), Color(0xFF25B6C6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x220C7EA5),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 18,
        runSpacing: 14,
        children: [
          SizedBox(
            width: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dashboard inventaire',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Suivez vos stocks, detectez les alertes et pilotez les mouvements en temps reel.',
                  style: TextStyle(color: Color(0xDDF5FBFF), height: 1.45),
                ),
                const SizedBox(height: 12),
                _AnimatedCompanyName(name: companyName),
              ],
            ),
          ),
          if (onNewMovement != null)
            FilledButton.icon(
              onPressed: onNewMovement,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0C7EA5),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
              ),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Nouveau mouvement'),
            ),
        ],
      ),
    );
  }
}

/// Affiche le nom de la company avec une transition douce a chaque mise a jour.
class _AnimatedCompanyName extends StatelessWidget {
  final String name;

  const _AnimatedCompanyName({required this.name});

  @override
  Widget build(BuildContext context) {
    final safeName = name.trim().isEmpty ? 'Mon entreprise' : name.trim();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 700),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0, 0.22),
          end: Offset.zero,
        ).animate(animation);

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offsetAnimation, child: child),
        );
      },
      child: Container(
        key: ValueKey<String>(safeName),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.apartment_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: _LetterRevealText(
                key: ValueKey<String>('reveal-$safeName'),
                text: safeName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Anime le texte en mode "letter-by-letter" pour un rendu premium.
class _LetterRevealText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _LetterRevealText({super.key, required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>(text),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 980),
      curve: Curves.easeOutQuart,
      builder: (context, value, _) {
        final visibleCount = (text.length * value).ceil().clamp(1, text.length);
        final visibleText = text.substring(0, visibleCount);

        return Text(
          visibleText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}

/// Carte KPI style moderne.
class _ModernSummaryCard extends StatelessWidget {
  final double width;
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accent;

  const _ModernSummaryCard({
    required this.width,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: width,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: accent.withValues(alpha: 0.12),
                    child: Icon(icon, color: accent),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ligne activite stylisee pour les mouvements de stock.
class _ActivityTile extends StatelessWidget {
  final String productName;
  final String? notes;
  final String movementType;
  final int quantity;
  final DateTime createdAt;

  const _ActivityTile({
    required this.productName,
    required this.notes,
    required this.movementType,
    required this.quantity,
    required this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    final isExit = movementType == 'exit';
    final isEntry = movementType == 'entry';
    final label = isEntry
        ? 'Entree'
        : isExit
        ? 'Sortie'
        : 'Ajustement';
    final color = isExit ? const Color(0xFFDC2626) : const Color(0xFF16A34A);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(
          isExit ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          color: color,
        ),
      ),
      title: Text(
        '$label - $productName',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${notes ?? 'Mouvement de stock'} • ${_formatDate(createdAt)}',
      ),
      trailing: Text(
        '${isExit ? '-' : '+'}$quantity',
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    final h = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }
}

