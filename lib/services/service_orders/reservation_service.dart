import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/reservation_model.dart';

class ReservationService {
  SupabaseClient get _client => Supabase.instance.client;

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

  Future<List<Reservation>> fetchReservations({
    DateTime? from,
    DateTime? to,
    String? status,
  }) async {
    final companyId = await _resolveCompanyId();

    var query = _client
        .from('reservations')
        .select()
        .eq('company_id', companyId);

    if (status != null && status.isNotEmpty) {
      query = query.eq('status', status);
    }
    if (from != null) {
      query = query.gte('reserved_at', from.toIso8601String());
    }
    if (to != null) {
      query = query.lte('reserved_at', to.toIso8601String());
    }

    final rows = await query.order('reserved_at', ascending: true);
    return (rows as List<dynamic>)
        .map(
          (row) => Reservation.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<Reservation> createReservation({
    String? clientId,
    required String clientName,
    String? phone,
    required String serviceId,
    required DateTime reservedAt,
    String? notes,
  }) async {
    final companyId = await _resolveCompanyId();
    final currentUserId = _client.auth.currentUser?.id;

    final row = await _client
        .from('reservations')
        .insert({
          'company_id': companyId,
          'client_id': clientId,
          'client_name': clientName,
          'phone': phone,
          'service_id': serviceId,
          'reserved_at': reservedAt.toIso8601String(),
          'status': 'pending',
          'notes': notes,
          'created_by': currentUserId,
        })
        .select()
        .single();

    return Reservation.fromJson(Map<String, dynamic>.from(row));
  }

  Future<Reservation> updateReservationStatus({
    required String reservationId,
    required String status,
    String? convertedOrderId,
  }) async {
    final companyId = await _resolveCompanyId();
    final payload = <String, dynamic>{'status': status};
    if (convertedOrderId != null) {
      payload['converted_order_id'] = convertedOrderId;
    }

    final row = await _client
        .from('reservations')
        .update(payload)
        .eq('id', reservationId)
        .eq('company_id', companyId)
        .select()
        .single();

    return Reservation.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> deleteReservation({required String reservationId}) async {
    final companyId = await _resolveCompanyId();

    await _client
        .from('reservations')
        .delete()
        .eq('id', reservationId)
        .eq('company_id', companyId);
  }
}
