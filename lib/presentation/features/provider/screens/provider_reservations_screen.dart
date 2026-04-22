import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../data/models/provider_reservation_model.dart';
import '../../../../services/provider/provider_reservation_service.dart';
import '../widgets/reservation_card.dart';

class ProviderReservationsScreen extends StatefulWidget {
  const ProviderReservationsScreen({Key? key}) : super(key: key);

  @override
  State<ProviderReservationsScreen> createState() =>
      _ProviderReservationsScreenState();
}

class _ProviderReservationsScreenState
    extends State<ProviderReservationsScreen> {
  final _service = ProviderReservationService();

  bool _loading = true;
  String? _error;
  List<ProviderReservation> _reservations = [];

  String? _statusFilter; // null = all

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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur: $e')),
                  );
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
      final list = await _service.fetchReservations(status: _statusFilter);
      if (!mounted) return;
      setState(() {
        _reservations = list;
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

  Future<void> _updateStatus(String id, String status) async {
    try {
      await _service.updateStatus(reservationId: id, status: status);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer'),
        content:
            const Text('Supprimer cette réservation définitivement ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteReservation(id);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes réservations'),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtrer',
            onSelected: (v) {
              setState(() => _statusFilter = v);
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: null, child: Text('Toutes')),
              PopupMenuItem(value: 'pending', child: Text('En attente')),
              PopupMenuItem(value: 'completed', child: Text('Terminées')),
              PopupMenuItem(value: 'cancelled', child: Text('Annulées')),
            ],
          ),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/provider/reservations/new'),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!,
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                          onPressed: _load,
                          child: const Text('Réessayer')),
                    ],
                  ),
                )
              : _reservations.isEmpty
                  ? const Center(child: Text('Aucune réservation.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _reservations.length,
                        itemBuilder: (_, i) {
                          final r = _reservations[i];
                          return ReservationCard(
                            reservation: r,
                            onMarkCompleted: () =>
                                _updateStatus(r.id, 'completed'),
                            onMarkCancelled: () =>
                                _updateStatus(r.id, 'cancelled'),
                            onDelete: () => _delete(r.id),
                          );
                        },
                      ),
                    ),
    );
  }
}
