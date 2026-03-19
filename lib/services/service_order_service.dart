import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/client_model.dart';
import '../data/models/reservation_model.dart';
import '../data/models/service_model.dart';
import '../data/models/service_order_item_model.dart';
import '../data/models/service_order_model.dart';
import 'reservation_service.dart';

class ClientActivitySummary {
  final List<Client> activeClients;
  final List<Client> inactiveClients;
  final int activeWindowDays;

  const ClientActivitySummary({
    required this.activeClients,
    required this.inactiveClients,
    required this.activeWindowDays,
  });

  int get totalClients => activeClients.length + inactiveClients.length;
  int get activeCount => activeClients.length;
  int get inactiveCount => inactiveClients.length;
}

class ServiceOrderService {
  SupabaseClient get _client => Supabase.instance.client;
  final ReservationService _reservationService = ReservationService();

  Future<String> _resolveCompanyId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Utilisateur non authentifie.');
    }

    final row = await _client
        .from('users')
        .select('company_id')
        .eq('id', userId)
        .maybeSingle();

    final companyId = row?['company_id']?.toString();
    if (companyId == null || companyId.isEmpty) {
      throw Exception('Company introuvable pour cet utilisateur.');
    }
    return companyId;
  }

  Future<String> _currentCashierDisplayName() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return 'Caissier';
    }

    final row = await _client
        .from('users')
        .select('email')
        .eq('id', userId)
        .maybeSingle();

    final email = row?['email']?.toString();
    if (email != null && email.isNotEmpty) {
      return email;
    }
    return 'Caissier';
  }

  Future<List<Service>> fetchServices({bool activeOnly = true}) async {
    final companyId = await _resolveCompanyId();

    var query = _client.from('services').select().eq('company_id', companyId);

    if (activeOnly) {
      query = query.eq('is_active', true);
    }

    final rows = await query.order('name');
    return (rows as List<dynamic>)
        .map((row) => Service.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<Service> upsertService(Service service) async {
    final companyId = await _resolveCompanyId();
    final isNew = !_isUuid(service.id);

    final payload = <String, dynamic>{
      if (!isNew) 'id': service.id,
      'company_id': companyId,
      'name': service.name,
      'description': service.description,
      'price': service.price,
      'is_active': service.isActive,
    };

    final row = await _client
        .from('services')
        .upsert(payload)
        .select()
        .single();
    return Service.fromJson(Map<String, dynamic>.from(row));
  }

  Future<List<Client>> fetchClients() async {
    final companyId = await _resolveCompanyId();
    final rows = await _client
        .from('clients')
        .select()
        .eq('company_id', companyId)
        .order('full_name');

    return (rows as List<dynamic>)
        .map((row) => Client.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<ClientActivitySummary> fetchClientActivitySummary({
    int activeWindowDays = 30,
  }) async {
    final companyId = await _resolveCompanyId();

    final clientRows = await _client
        .from('clients')
        .select()
        .eq('company_id', companyId)
        .order('full_name');

    final allClients = (clientRows as List<dynamic>)
        .map((row) => Client.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();

    if (allClients.isEmpty) {
      return ClientActivitySummary(
        activeClients: const <Client>[],
        inactiveClients: const <Client>[],
        activeWindowDays: activeWindowDays,
      );
    }

    final cutoff = DateTime.now().subtract(Duration(days: activeWindowDays));
    final orderRows = await _client
        .from('service_orders')
        .select('client_id, created_at')
        .eq('company_id', companyId)
        .gte('created_at', cutoff.toIso8601String())
        .not('client_id', 'is', null);

    final activeClientIds = (orderRows as List<dynamic>)
        .map((row) => (row as Map)['client_id']?.toString())
        .whereType<String>()
        .toSet();

    final active = <Client>[];
    final inactive = <Client>[];

    for (final client in allClients) {
      if (activeClientIds.contains(client.id)) {
        active.add(client);
      } else {
        inactive.add(client);
      }
    }

    return ClientActivitySummary(
      activeClients: active,
      inactiveClients: inactive,
      activeWindowDays: activeWindowDays,
    );
  }

  Future<Client> upsertClient({
    String? id,
    required String fullName,
    String? phone,
    String? notes,
  }) async {
    final companyId = await _resolveCompanyId();
    final isNew = !_isUuid(id ?? '');

    final payload = <String, dynamic>{
      if (!isNew) 'id': id,
      'company_id': companyId,
      'full_name': fullName,
      'phone': phone,
      'notes': notes,
    };

    final row = await _client.from('clients').upsert(payload).select().single();
    return Client.fromJson(Map<String, dynamic>.from(row));
  }

  Future<ServiceOrder> createServiceOrder({
    String? clientId,
    required String clientName,
    required List<ServiceOrderItem> items,
    String? paymentMethod,
    String? notes,
    String? reservationId,
  }) async {
    if (items.isEmpty) {
      throw Exception('Ajoutez au moins un service.');
    }

    final companyId = await _resolveCompanyId();
    final cashierId = _client.auth.currentUser?.id;
    final cashierName = await _currentCashierDisplayName();
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    const discount = 0.0;
    final total = subtotal - discount;

    final now = DateTime.now();
    final ticketNumber = 'SRV-${DateFormat('yyyyMMdd-HHmmss').format(now)}';

    final orderRow = await _client
        .from('service_orders')
        .insert({
          'company_id': companyId,
          'client_id': clientId,
          'client_name': clientName,
          'cashier_id': cashierId,
          'cashier_name': cashierName,
          'reservation_id': reservationId,
          'ticket_number': ticketNumber,
          'payment_method': paymentMethod,
          'payment_status': 'paid',
          'subtotal_amount': subtotal,
          'discount_amount': discount,
          'total_amount': total,
          'paid_amount': total,
          'notes': notes,
        })
        .select()
        .single();

    final createdOrder = ServiceOrder.fromJson(
      Map<String, dynamic>.from(orderRow),
    );

    final itemPayload = items
        .map(
          (item) => {
            'service_order_id': createdOrder.id,
            'service_id': item.serviceId,
            'service_name': item.serviceName,
            'unit_price': item.unitPrice,
            'quantity': item.quantity,
            'line_total': item.lineTotal,
          },
        )
        .toList();

    await _client.from('service_order_items').insert(itemPayload);

    if (reservationId != null && reservationId.isNotEmpty) {
      await _reservationService.updateReservationStatus(
        reservationId: reservationId,
        status: 'completed',
        convertedOrderId: createdOrder.id,
      );
    }

    return fetchOrderById(createdOrder.id);
  }

  Future<ServiceOrder> convertReservationToOrder({
    required Reservation reservation,
    required Service service,
    String? notes,
  }) async {
    final line = ServiceOrderItem(
      id: '',
      serviceOrderId: '',
      serviceId: service.id,
      serviceName: service.name,
      unitPrice: service.price,
      quantity: 1,
      lineTotal: service.price,
      createdAt: DateTime.now(),
    );

    return createServiceOrder(
      clientId: reservation.clientId,
      clientName: reservation.clientName,
      items: <ServiceOrderItem>[line],
      paymentMethod: 'counter',
      notes: notes,
      reservationId: reservation.id,
    );
  }

  Future<ServiceOrder> fetchOrderById(String orderId) async {
    final companyId = await _resolveCompanyId();

    final row = await _client
        .from('service_orders')
        .select('*, service_order_items(*)')
        .eq('id', orderId)
        .eq('company_id', companyId)
        .single();

    return ServiceOrder.fromJson(Map<String, dynamic>.from(row));
  }

  Future<List<ServiceOrder>> fetchRecentOrders({
    int limit = 30,
    bool includeItems = true,
  }) async {
    final companyId = await _resolveCompanyId();

    final selectClause = includeItems
        ? '*, service_order_items(*)'
        : 'id, company_id, client_id, client_name, cashier_id, cashier_name, reservation_id, ticket_number, payment_method, payment_status, subtotal_amount, discount_amount, total_amount, paid_amount, notes, created_at, updated_at';

    final rows = await _client
        .from('service_orders')
        .select(selectClause)
        .eq('company_id', companyId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List<dynamic>)
        .map(
          (row) => ServiceOrder.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  bool _isUuid(String value) {
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    return uuidRegex.hasMatch(value);
  }
}
