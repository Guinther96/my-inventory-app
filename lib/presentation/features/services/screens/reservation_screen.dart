import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../common_widgets/app_drawer.dart';
import '../../../common_widgets/app_sidebar.dart';
import '../../../../../data/models/client_model.dart';
import '../../../../../data/models/reservation_model.dart';
import '../../../../../data/models/service_model.dart';
import '../../../../../services/reservation_service.dart';
import '../../../../../services/service_service.dart';
import '../../../../../services/service_order_service.dart';

class ReservationScreen extends StatefulWidget {
  const ReservationScreen({super.key});

  @override
  State<ReservationScreen> createState() => _ReservationScreenState();
}

class _ReservationScreenState extends State<ReservationScreen> {
  final ReservationService _reservationService = ReservationService();
  final ServiceService _serviceService = ServiceService();
  final ServiceOrderService _serviceOrderService = ServiceOrderService();

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  List<Service> _services = const <Service>[];
  List<Client> _clients = const <Client>[];
  List<Reservation> _reservations = const <Reservation>[];

  Client? _selectedClient;
  String? _selectedServiceId;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

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
        _serviceService.fetchServices(),
        _serviceOrderService.fetchClients(),
        _reservationService.fetchReservations(),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _services = results[0] as List<Service>;
        _clients = results[1] as List<Client>;
        _reservations = results[2] as List<Reservation>;
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

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      initialDate: _selectedDate ?? now,
    );

    if (date == null || !mounted) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );

    if (time == null) {
      return;
    }

    setState(() {
      _selectedDate = date;
      _selectedTime = time;
    });
  }

  DateTime? get _combinedDateTime {
    final date = _selectedDate;
    final time = _selectedTime;
    if (date == null || time == null) {
      return null;
    }
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _createReservation() async {
    final serviceId = _selectedServiceId;
    final reservedAt = _combinedDateTime;
    if (serviceId == null || reservedAt == null) {
      _show('Choisissez un service et une date/heure.');
      return;
    }

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _show('Le nom client est obligatoire.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      String? clientId = _selectedClient?.id;
      if (clientId == null) {
        final client = await _serviceOrderService.upsertClient(
          fullName: name,
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        );
        clientId = client.id;
      }

      await _reservationService.createReservation(
        clientId: clientId,
        clientName: name,
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        serviceId: serviceId,
        reservedAt: reservedAt,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      _nameCtrl.clear();
      _phoneCtrl.clear();
      _notesCtrl.clear();
      setState(() {
        _selectedClient = null;
        _selectedServiceId = null;
        _selectedDate = null;
        _selectedTime = null;
      });

      await _load();
      _show('Reservation enregistree.');
    } catch (e) {
      _show('Erreur reservation: $e');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _convertToOrder(Reservation reservation) async {
    context.go('/beauty/orders/new', extra: reservation);
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
              title: const Text('Reservations'),
            ),
      drawer: isDesktop ? null : const AppDrawer(),
      body: Row(
        children: [
          if (isDesktop) const AppSidebar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Nouvelle reservation',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<Client>(
                                  initialValue: _selectedClient,
                                  decoration: const InputDecoration(
                                    labelText: 'Client existant (optionnel)',
                                  ),
                                  items: _clients
                                      .map(
                                        (client) => DropdownMenuItem<Client>(
                                          value: client,
                                          child: Text(
                                            '${client.fullName} ${client.phone ?? ''}',
                                          ),
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
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _nameCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Nom client',
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _phoneCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Telephone',
                                  ),
                                ),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String>(
                                  decoration: const InputDecoration(
                                    labelText: 'Service demande',
                                  ),
                                  items: _services
                                      .map(
                                        (service) => DropdownMenuItem<String>(
                                          value: service.id,
                                          child: Text(
                                            '${service.name} (${service.price.toStringAsFixed(2)})',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setState(() => _selectedServiceId = value);
                                  },
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: _pickDateTime,
                                  icon: const Icon(Icons.schedule),
                                  label: Text(
                                    _combinedDateTime == null
                                        ? 'Choisir date et heure'
                                        : DateFormat(
                                            'dd/MM/yyyy HH:mm',
                                          ).format(_combinedDateTime!),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _notesCtrl,
                                  minLines: 1,
                                  maxLines: 3,
                                  decoration: const InputDecoration(
                                    labelText: 'Notes',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _isSubmitting
                                      ? null
                                      : _createReservation,
                                  icon: const Icon(Icons.save),
                                  label: const Text('Enregistrer'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Liste des reservations',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        if (_reservations.isEmpty)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: Text('Aucune reservation.'),
                            ),
                          )
                        else
                          ..._reservations.map((reservation) {
                            final service = _findServiceById(
                              reservation.serviceId,
                            );
                            final canConvert =
                                reservation.status != 'completed' &&
                                reservation.status != 'cancelled';

                            return Card(
                              child: ListTile(
                                title: Text(
                                  '${reservation.clientName} - ${service?.name ?? 'Service inconnu'}',
                                ),
                                subtitle: Text(
                                  '${DateFormat('dd/MM/yyyy HH:mm').format(reservation.reservedAt)} | ${reservation.phone ?? '-'} | ${reservation.status}',
                                ),
                                trailing: canConvert
                                    ? FilledButton(
                                        onPressed: () =>
                                            _convertToOrder(reservation),
                                        child: const Text('Paiement + ticket'),
                                      )
                                    : null,
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
