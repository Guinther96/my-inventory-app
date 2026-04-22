import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../services/provider/provider_earning_service.dart';
import '../../../../services/provider/provider_reservation_service.dart';
import '../../../../data/models/provider_reservation_model.dart';

class ProviderDashboardScreen extends StatefulWidget {
  const ProviderDashboardScreen({Key? key}) : super(key: key);

  @override
  State<ProviderDashboardScreen> createState() =>
      _ProviderDashboardScreenState();
}

class _ProviderDashboardScreenState extends State<ProviderDashboardScreen> {
  final _reservationService = ProviderReservationService();
  final _earningService = ProviderEarningService();

  bool _loading = true;
  String? _error;

  int _pendingCount = 0;
  int _completedCount = 0;
  double _totalEarnings = 0;
  List<ProviderReservation> _upcoming = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _showLogoutDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Se deconnecter'),
        content: const Text('Etes-vous sure de vouloir vous deconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await Supabase.instance.client.auth.signOut();
                if (mounted) {
                  context.go('/login');
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
                }
              }
            },
            child: const Text('Deconnecter'),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);

      final reservations = await _reservationService.fetchReservations();
      final earnings = await _earningService.fetchEarnings(from: startOfMonth);

      if (!mounted) return;
      setState(() {
        _pendingCount = reservations.where((r) => r.status == 'pending').length;
        _completedCount = reservations
            .where((r) => r.status == 'completed')
            .length;
        _totalEarnings = earnings.fold(0.0, (sum, e) => sum + e.amount);
        _upcoming = reservations
            .where(
              (r) =>
                  r.status == 'pending' &&
                  !r.date.isBefore(DateTime(now.year, now.month, now.day)),
            )
            .take(5)
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau de bord Prestataire'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                _showLogoutDialog();
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 10),
                    Text('Se deconnecter'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/provider/reservations/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle réservation'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _load,
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _StatsRow(
                    pending: _pendingCount,
                    completed: _completedCount,
                    earnings: _totalEarnings,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Prochaines réservations',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.go('/provider/reservations'),
                        child: const Text('Tout voir'),
                      ),
                    ],
                  ),
                  if (_upcoming.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('Aucune réservation à venir.')),
                    )
                  else
                    ..._upcoming.map((r) => _UpcomingTile(reservation: r)),
                ],
              ),
            ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int pending;
  final int completed;
  final double earnings;

  const _StatsRow({
    required this.pending,
    required this.completed,
    required this.earnings,
  });

  @override
  Widget build(BuildContext context) {
    final earningsStr = NumberFormat.currency(
      symbol: '',
      decimalDigits: 2,
    ).format(earnings);
    return Row(
      children: [
        _StatCard(label: 'En attente', value: '$pending', icon: Icons.schedule),
        const SizedBox(width: 8),
        _StatCard(
          label: 'Terminées',
          value: '$completed',
          icon: Icons.check_circle_outline,
        ),
        const SizedBox(width: 8),
        _StatCard(
          label: 'Gains (mois)',
          value: earningsStr,
          icon: Icons.attach_money,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpcomingTile extends StatelessWidget {
  final ProviderReservation reservation;

  const _UpcomingTile({required this.reservation});

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('dd/MM/yyyy').format(reservation.date);
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person)),
      title: Text(reservation.clientName),
      subtitle: Text(
        '${reservation.serviceName} — $dateStr ${reservation.time}',
      ),
      trailing: Text(
        NumberFormat.currency(
          symbol: 'HTG ',
          decimalDigits: 2,
        ).format(reservation.price),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}
