import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/providers/inventory_provider.dart';
import '../../../../services/service_order_service.dart';
import '../../../common_widgets/app_drawer.dart';
import '../../../common_widgets/app_sidebar.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final ServiceOrderService _serviceOrderService = ServiceOrderService();

  bool _isClientsLoading = false;
  String? _clientsError;
  ClientActivitySummary? _clientSummary;

  @override
  void initState() {
    super.initState();
    _loadClientSummary();
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 950;
    final horizontalPadding = isDesktop ? 24.0 : 14.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F6FC),
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x100D1B2A),
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
                        'Clients actifs / inactifs',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x100D1B2A),
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
                                      style: const TextStyle(
                                        color: Colors.redAccent,
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
