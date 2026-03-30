import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../common_widgets/app_drawer.dart';
import '../../../common_widgets/app_sidebar.dart';
import '../../../../../data/models/client_model.dart';
import '../../../../../data/models/reservation_model.dart';
import '../../../../../data/models/service_model.dart';
import '../../../../../data/models/service_order_item_model.dart';
import '../../../../../data/models/service_order_model.dart';
import '../../../../../services/service_service.dart';
import '../../../../../services/service_order_service.dart';
import '../../../../../services/thermal_ticket_service.dart';

class CreateServiceOrderScreen extends StatefulWidget {
  final Reservation? initialReservation;

  const CreateServiceOrderScreen({super.key, this.initialReservation});

  @override
  State<CreateServiceOrderScreen> createState() =>
      _CreateServiceOrderScreenState();
}

class _CreateServiceOrderScreenState extends State<CreateServiceOrderScreen> {
  final ServiceService _serviceCatalogService = ServiceService();
  final ServiceOrderService _service = ServiceOrderService();
  final ThermalTicketService _ticketService = ThermalTicketService();

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  List<Service> _services = const <Service>[];
  List<Client> _clients = const <Client>[];
  List<_OrderLine> _lines = <_OrderLine>[];

  Client? _selectedClient;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait<dynamic>([
        _serviceCatalogService.fetchServices(),
        _service.fetchClients(),
      ]);

      if (!mounted) {
        return;
      }

      _services = results[0] as List<Service>;
      _clients = results[1] as List<Client>;

      final reservation = widget.initialReservation;
      if (reservation != null) {
        _nameCtrl.text = reservation.clientName;
        _phoneCtrl.text = reservation.phone ?? '';

        final service = _findServiceById(reservation.serviceId);
        if (service != null) {
          _lines = <_OrderLine>[_OrderLine(service: service, quantity: 1)];
        }
      }

      setState(() {});
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

  void _addService(Service service) {
    setState(() {
      final idx = _lines.indexWhere((line) => line.service.id == service.id);
      if (idx >= 0) {
        _lines[idx] = _lines[idx].copyWith(quantity: _lines[idx].quantity + 1);
      } else {
        _lines.add(_OrderLine(service: service, quantity: 1));
      }
    });
  }

  void _changeQty(Service service, int delta) {
    setState(() {
      final idx = _lines.indexWhere((line) => line.service.id == service.id);
      if (idx < 0) {
        return;
      }
      final nextQty = _lines[idx].quantity + delta;
      if (nextQty <= 0) {
        _lines.removeAt(idx);
      } else {
        _lines[idx] = _lines[idx].copyWith(quantity: nextQty);
      }
    });
  }

  double get _total => _lines.fold<double>(
    0,
    (sum, line) => sum + (line.quantity * line.service.price),
  );

  Future<void> _submit() async {
    if (_lines.isEmpty) {
      _show('Ajoutez au moins un service.');
      return;
    }

    final clientName = _nameCtrl.text.trim();
    if (clientName.isEmpty) {
      _show('Nom client obligatoire.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      String? clientId = _selectedClient?.id;
      if (clientId == null) {
        final client = await _service.upsertClient(
          fullName: clientName,
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        );
        clientId = client.id;
      }

      final items = _lines
          .map(
            (line) => ServiceOrderItem(
              id: '',
              serviceOrderId: '',
              serviceId: line.service.id,
              serviceName: line.service.name,
              unitPrice: line.service.price,
              quantity: line.quantity,
              lineTotal: line.quantity * line.service.price,
              createdAt: DateTime.now(),
            ),
          )
          .toList();

      final order = await _service.createServiceOrder(
        clientId: clientId,
        clientName: clientName,
        items: items,
        paymentMethod: 'counter',
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        reservationId: widget.initialReservation?.id,
      );

      if (!mounted) {
        return;
      }

      await _showTicketDialog(order);

      setState(() {
        _lines = <_OrderLine>[];
        _selectedClient = null;
      });
      _nameCtrl.clear();
      _phoneCtrl.clear();
      _notesCtrl.clear();

      _show('Paiement enregistre. Ticket genere.');
    } catch (e) {
      _show('Erreur paiement: $e');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _showTicketDialog(ServiceOrder order) async {
    final bytes = _ticketService.buildEscPosTicket(
      salonName: 'BiznisPlus Beauty',
      date: order.createdAt,
      clientName: order.clientName,
      items: order.items,
      total: order.totalAmount,
      cashierName: order.cashierName ?? 'Caissier',
      ticketNumber: order.ticketNumber,
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Ticket genere'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Salon: BiznisPlus Beauty'),
                Text(
                  'Date: ${DateFormat('dd/MM/yyyy HH:mm').format(order.createdAt)}',
                ),
                Text('Client: ${order.clientName}'),
                Text('Caissier: ${order.cashierName ?? 'Caissier'}'),
                if (order.ticketNumber != null)
                  Text('Ticket: ${order.ticketNumber}'),
                const SizedBox(height: 8),
                const Text('Services:'),
                ...order.items.map(
                  (item) => Text(
                    '- ${item.serviceName}: ${item.unitPrice.toStringAsFixed(2)} x ${item.quantity} = ${item.lineTotal.toStringAsFixed(2)}',
                  ),
                ),
                const SizedBox(height: 8),
                Text('Total: ${order.totalAmount.toStringAsFixed(2)}'),
                const SizedBox(height: 8),
                Text('ESC/POS bytes: ${bytes.length}'),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  void _show(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Service? _findServiceById(String id) {
    for (final service in _services) {
      if (service.id == id) {
        return service;
      }
    }
    return null;
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.go('/beauty/services');
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1120;
    final selectedClientValue = _selectedClient == null
        ? null
        : _clients
              .where((c) => c.id == _selectedClient!.id)
              .cast<Client?>()
              .firstWhere((_) => true, orElse: () => null);

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _goBack,
              ),
              title: const Text('Commande service'),
            ),
      drawer: isDesktop ? null : const AppDrawer(),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) const AppSidebar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
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
                      if (_error != null)
                        Card(
                          color: const Color(0xFFFFF3E0),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(_error!),
                          ),
                        ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              DropdownButtonFormField<Client>(
                                initialValue: selectedClientValue,
                                decoration: const InputDecoration(
                                  labelText: 'Client existant (optionnel)',
                                ),
                                items: _clients
                                    .map(
                                      (client) => DropdownMenuItem<Client>(
                                        value: client,
                                        child: Text(client.fullName),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedClient = value;
                                    if (value != null) {
                                      _nameCtrl.text = value.fullName;
                                      _phoneCtrl.text = value.phone ?? '';
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _nameCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Nom client',
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _phoneCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Telephone',
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _notesCtrl,
                                minLines: 1,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                  labelText: 'Notes',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Services disponibles',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _services
                            .map(
                              (service) => ActionChip(
                                label: Text(
                                  '${service.name} (${service.price.toStringAsFixed(2)})',
                                ),
                                onPressed: () => _addService(service),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ticket en cours',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              if (_lines.isEmpty)
                                const Text('Aucun service ajoute.')
                              else
                                ..._lines.map(
                                  (line) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(line.service.name),
                                    subtitle: Text(
                                      '${line.quantity} x ${line.service.price.toStringAsFixed(2)} = ${(line.quantity * line.service.price).toStringAsFixed(2)}',
                                    ),
                                    trailing: Wrap(
                                      spacing: 4,
                                      children: [
                                        IconButton(
                                          onPressed: () =>
                                              _changeQty(line.service, -1),
                                          icon: const Icon(Icons.remove),
                                        ),
                                        IconButton(
                                          onPressed: () =>
                                              _changeQty(line.service, 1),
                                          icon: const Icon(Icons.add),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              const Divider(),
                              Text(
                                'Total: ${_total.toStringAsFixed(2)}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: _isSubmitting ? null : _submit,
                                icon: const Icon(Icons.receipt_long),
                                label: const Text(
                                  'Valider paiement + generer ticket',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _OrderLine {
  final Service service;
  final int quantity;

  const _OrderLine({required this.service, required this.quantity});

  _OrderLine copyWith({Service? service, int? quantity}) {
    return _OrderLine(
      service: service ?? this.service,
      quantity: quantity ?? this.quantity,
    );
  }
}
