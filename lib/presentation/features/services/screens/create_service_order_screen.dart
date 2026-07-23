import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../common_widgets/app_drawer.dart';
import '../../../common_widgets/app_sidebar.dart';
import '../../../../../core/utils/currency.dart';
import '../../../../../data/models/client_model.dart';
import '../../../../../data/models/reservation_model.dart';
import '../../../../../data/models/service_model.dart';
import '../../../../../data/models/service_order_item_model.dart';
import '../../../../../data/models/service_order_model.dart';
import '../../../../../data/models/tax_config_model.dart';
import '../../../../../data/models/user_profile_model.dart';
import '../../../../../data/providers/inventory_provider.dart';
import '../../../../../services/company/company_service.dart';
import '../../../../../services/service_orders/service_service.dart';
import '../../../../../services/service_orders/service_order_service.dart';
import '../../../../../services/user/user_profile_service.dart';

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
  final UserProfileService _userProfileService = UserProfileService();

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  List<Service> _services = const <Service>[];
  List<Client> _clients = const <Client>[];
  List<UserProfile> _providers = const <UserProfile>[];
  List<_OrderLine> _lines = <_OrderLine>[];

  /// Devise de paiement choisie par le client pour le ticket courant.
  String? _selectedPaymentCurrency;
  double? _exchangeRate;
  TaxConfig _taxConfig = TaxConfig.disabled;

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
      final companyId = context.read<InventoryProvider>().companyId;
      final results = await Future.wait<dynamic>([
        _serviceCatalogService.fetchServices(),
        _service.fetchClients(),
        _userProfileService.fetchCompanyUsers(),
        if (companyId != null && companyId.isNotEmpty)
          CompanyService().fetchExchangeRate(companyId),
        if (companyId != null && companyId.isNotEmpty)
          CompanyService().fetchTaxConfig(companyId),
      ]);

      if (!mounted) {
        return;
      }

      _services = results[0] as List<Service>;
      _clients = results[1] as List<Client>;
      if (results.length > 3) {
        _exchangeRate = results[3] as double?;
      }
      if (results.length > 4) {
        _taxConfig = results[4] as TaxConfig;
      }

      // Filtrer seulement les prestataires
      final allUsers = results[2] as List<UserProfile>;
      _providers = allUsers.where((u) => u.role == AppRole.provider).toList();

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

  /// Regroupe le montant du ticket par devise (les services ajoutes peuvent
  /// etre en HTG et en USD dans le meme ticket).
  Map<String, double> get _totalsByCurrency {
    final totals = <String, double>{};
    for (final line in _lines) {
      final lineTotal = line.quantity * line.service.price;
      totals.update(
        line.service.currency,
        (value) => value + lineTotal,
        ifAbsent: () => lineTotal,
      );
    }
    return totals;
  }

  /// Devise de paiement effective: choix explicite, sinon devise unique du
  /// ticket, sinon HTG si le ticket est mixte/vide.
  String get _paymentCurrency {
    if (_selectedPaymentCurrency != null) {
      return _selectedPaymentCurrency!;
    }
    final totals = _totalsByCurrency;
    if (totals.length == 1) {
      return totals.keys.first;
    }
    return 'HTG';
  }

  /// Total converti dans la devise de paiement choisie, ou null si une
  /// conversion est necessaire mais qu'aucun taux n'est configure.
  double? get _convertedTotal {
    final paymentCurrency = _paymentCurrency;
    var total = 0.0;
    for (final entry in _totalsByCurrency.entries) {
      final converted = convertAmount(
        amount: entry.value,
        fromCurrency: entry.key,
        toCurrency: paymentCurrency,
        usdToHtgRate: _exchangeRate,
      );
      if (converted == null) {
        return null;
      }
      total += converted;
    }
    return total;
  }

  /// Apercu Sous-total/Taxe/Total sur le sous-total converti. Null si la
  /// taxe necessite une conversion de devise mais qu'aucun taux n'est
  /// configure — dans ce cas la validation est bloquee, comme pour une
  /// conversion de service manquante.
  TaxCalculationResult? get _taxPreview {
    final subtotal = _convertedTotal;
    if (subtotal == null) {
      return null;
    }
    return calculateTax(
      subtotal: subtotal,
      taxEnabled: _taxConfig.enabled,
      taxType: _taxConfig.type,
      taxValue: _taxConfig.value,
      taxCurrency: _taxConfig.currency,
      paymentCurrency: _paymentCurrency,
      usdToHtgRate: _exchangeRate,
    );
  }

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

    if (_convertedTotal == null) {
      _show('Taux de change non configure. Configurez-le dans Parametres.');
      return;
    }

    if (_taxConfig.enabled && _taxPreview == null) {
      _show(
        'Taux de change requis pour appliquer la taxe. Configurez-le dans Parametres.',
      );
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
              currency: line.service.currency,
              quantity: line.quantity,
              lineTotal: line.quantity * line.service.price,
              providerId: line.providerId,
              providerName: line.providerName,
              createdAt: DateTime.now(),
            ),
          )
          .toList();

      // Use integrated printer service within the service layer
      final companyName = context.read<InventoryProvider>().companyName;
      final companyEmail = context.read<InventoryProvider>().companyEmail;
      final (order, printResult) = await _service.createServiceOrderWithPrinter(
        clientId: clientId,
        clientName: clientName,
        items: items,
        paymentMethod: 'counter',
        paymentCurrency: _paymentCurrency,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        reservationId: widget.initialReservation?.id,
        companyName: companyName,
        companyEmail: companyEmail,
      );

      if (!mounted) {
        return;
      }

      await _showTicketDialog(order);

      setState(() {
        _lines = <_OrderLine>[];
        _selectedClient = null;
        _selectedPaymentCurrency = null;
      });
      _nameCtrl.clear();
      _phoneCtrl.clear();
      _notesCtrl.clear();

      // Show appropriate message based on print status
      _show(
        printResult.success
            ? 'Paiement enregistre. Ticket genere.'
            : 'Paiement enregistre. ${printResult.message}',
      );
    } catch (e) {
      _show('Erreur paiement: $e');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _showTicketDialog(ServiceOrder order) async {
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
                    '- ${item.serviceName}: ${formatMoney(item.unitPrice, item.currency)} x ${item.quantity} = ${formatMoney(item.lineTotal, item.currency)}',
                  ),
                ),
                const SizedBox(height: 8),
                if (order.taxAmount > 0) ...[
                  Text(
                    'Sous-total: ${formatMoney(order.subtotalAmount, order.paymentCurrency)}',
                  ),
                  Text(
                    '${order.isTaxPercentage ? '${order.taxName} (${order.taxValue?.toStringAsFixed(0)}%)' : order.taxName}: ${formatMoney(order.taxAmount, order.paymentCurrency)}',
                  ),
                ],
                Text(
                  'Total: ${formatMoney(order.totalAmount, order.paymentCurrency)}',
                ),
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
                                  '${service.name} (${formatMoney(service.price, service.currency)})',
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
                                ..._lines.asMap().entries.map(
                                  (entry) {
                                    final idx = entry.key;
                                    final line = entry.value;
                                    return Card(
                                      color: Colors.grey.shade100,
                                      margin: const EdgeInsets.only(bottom: 12),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              line.service.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              '${line.quantity} x ${formatMoney(line.service.price, line.service.currency)} = ${formatMoney(line.quantity * line.service.price, line.service.currency)}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                            const SizedBox(height: 12),
                                            DropdownButtonFormField<String?>(
                                              value: line.providerId,
                                              hint: const Text('Selectioner le prestataire'),
                                              decoration: const InputDecoration(
                                                labelText: 'Prestataire',
                                                border: OutlineInputBorder(),
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8,
                                                    ),
                                              ),
                                              items: _providers
                                                  .map(
                                                    (provider) =>
                                                        DropdownMenuItem<String?>(
                                                      value: provider.id,
                                                      child: Text(
                                                        provider.email,
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (String? newProviderId) {
                                                setState(() {
                                                  if (idx >= 0 && idx < _lines.length) {
                                                    final provider =
                                                        _providers.firstWhere(
                                                      (p) => p.id == newProviderId,
                                                      orElse: UserProfile.empty,
                                                    );
                                                    _lines[idx] = _lines[idx]
                                                        .copyWith(
                                                          providerId:
                                                              newProviderId,
                                                          providerName:
                                                              provider.email,
                                                        );
                                                  }
                                                });
                                              },
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                IconButton(
                                                  onPressed: () =>
                                                      _changeQty(line.service, -1),
                                                  icon: const Icon(
                                                    Icons.remove_circle_outline,
                                                  ),
                                                ),
                                                Text(
                                                  '${line.quantity}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                IconButton(
                                                  onPressed: () =>
                                                      _changeQty(line.service, 1),
                                                  icon: const Icon(
                                                    Icons.add_circle_outline,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              const Divider(),
                              if (_totalsByCurrency.length > 1) ...[
                                const Text('Mode de paiement'),
                                Row(
                                  children: kSupportedCurrencies.map((code) {
                                    return Expanded(
                                      child: RadioListTile<String>(
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                        value: code,
                                        groupValue: _paymentCurrency,
                                        title: Text(
                                          AppCurrency.fromCode(code).label,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                        onChanged: (value) {
                                          if (value != null) {
                                            setState(
                                              () => _selectedPaymentCurrency =
                                                  value,
                                            );
                                          }
                                        },
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                              Builder(
                                builder: (context) {
                                  final preview = _taxPreview;
                                  if (_convertedTotal != null &&
                                      _taxConfig.enabled &&
                                      preview != null &&
                                      preview.taxAmount > 0) {
                                    final taxLabel = _taxConfig.isPercentage
                                        ? '${_taxConfig.name} (${_taxConfig.value.toStringAsFixed(0)}%)'
                                        : _taxConfig.name;
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Sous-total: ${formatMoney(preview.subtotal, _paymentCurrency)}',
                                        ),
                                        Text(
                                          '$taxLabel: ${formatMoney(preview.taxAmount, _paymentCurrency)}',
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Total: ${formatMoney(preview.total, _paymentCurrency)}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                      ],
                                    );
                                  }
                                  return Text(
                                    _convertedTotal == null
                                        ? 'Total: taux de change requis (configurez-le dans Parametres)'
                                        : 'Total: ${formatMoney(_convertedTotal!, _paymentCurrency)}',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed:
                                    _isSubmitting ||
                                        _convertedTotal == null ||
                                        (_taxConfig.enabled &&
                                            _taxPreview == null)
                                    ? null
                                    : _submit,
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
  final String? providerId;
  final String? providerName;

  const _OrderLine({
    required this.service,
    required this.quantity,
    this.providerId,
    this.providerName,
  });

  _OrderLine copyWith({
    Service? service,
    int? quantity,
    String? providerId,
    String? providerName,
  }) {
    return _OrderLine(
      service: service ?? this.service,
      quantity: quantity ?? this.quantity,
      providerId: providerId ?? this.providerId,
      providerName: providerName ?? this.providerName,
    );
  }
}
