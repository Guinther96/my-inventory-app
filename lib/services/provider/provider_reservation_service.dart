import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/provider_reservation_model.dart';

class ProviderReservationService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<String> _currentUserId() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Utilisateur non authentifié.');
    return uid;
  }

  Future<String> _resolveCompanyId() async {
    final userId = await _currentUserId();
    final row = await _client
        .from('users')
        .select('company_id')
        .eq('id', userId)
        .maybeSingle();
    final companyId = row?['company_id']?.toString();
    if (companyId == null || companyId.isEmpty) {
      throw Exception('Entreprise introuvable pour cet utilisateur.');
    }
    return companyId;
  }

  Future<List<ProviderReservation>> fetchReservations({
    String? status,
    DateTime? from,
    DateTime? to,
  }) async {
    final userId = await _currentUserId();

    var query = _client
        .from('provider_reservations')
        .select()
        .eq('provider_id', userId);

    if (status != null) {
      query = query.eq('status', status);
    }
    if (from != null) {
      query = query.gte('date', from.toIso8601String().substring(0, 10));
    }
    if (to != null) {
      query = query.lte('date', to.toIso8601String().substring(0, 10));
    }

    final rows = await query.order('date', ascending: false).order('time');
    return (rows as List<dynamic>)
        .map((r) => ProviderReservation.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<ProviderReservation> createReservation({
    required String clientName,
    required String serviceName,
    required double price,
    required DateTime date,
    required String time,
    String createdBy = 'provider',
  }) async {
    final userId = await _currentUserId();
    final businessId = await _resolveCompanyId();

    final payload = {
      'business_id': businessId,
      'provider_id': userId,
      'client_name': clientName,
      'service_name': serviceName,
      'price': price,
      'date': date.toIso8601String().substring(0, 10),
      'time': time,
      'created_by': createdBy,
    };

    final row = await _client
        .from('provider_reservations')
        .insert(payload)
        .select()
        .single();
    return ProviderReservation.fromJson(Map<String, dynamic>.from(row));
  }

  Future<ProviderReservation> updateStatus({
    required String reservationId,
    required String status,
  }) async {
    final row = await _client
        .from('provider_reservations')
        .update({'status': status})
        .eq('id', reservationId)
        .select()
        .single();
    return ProviderReservation.fromJson(Map<String, dynamic>.from(row));
  }

  Future<List<ProviderReservation>> fetchCompanyReservations({
    String? status,
    DateTime? from,
    DateTime? to,
  }) async {
    final companyId = await _resolveCompanyId();

    var query = _client
        .from('provider_reservations')
        .select()
        .eq('business_id', companyId);

    if (status != null) {
      query = query.eq('status', status);
    }
    if (from != null) {
      query = query.gte('date', from.toIso8601String().substring(0, 10));
    }
    if (to != null) {
      query = query.lte('date', to.toIso8601String().substring(0, 10));
    }

    final rows = await query.order('date', ascending: false).order('time');
    return (rows as List<dynamic>)
        .map((r) => ProviderReservation.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> deleteReservation(String reservationId) async {
    await _client
        .from('provider_reservations')
        .delete()
        .eq('id', reservationId);
  }
}
