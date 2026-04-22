import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/service_model.dart';

class ServiceService {
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
    final currentUserId = _client.auth.currentUser?.id;
    final isNew = !_isUuid(service.id);

    final payload = <String, dynamic>{
      if (!isNew) 'id': service.id,
      'company_id': companyId,
      'name': service.name,
      'description': service.description,
      'price': service.price,
      'duration_minutes': service.durationMinutes,
      if (isNew) 'created_by': currentUserId,
      'is_active': service.isActive,
    };

    final row = await _client
        .from('services')
        .upsert(payload)
        .select()
        .single();
    return Service.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> deleteService(String serviceId) async {
    final companyId = await _resolveCompanyId();

    await _client
        .from('services')
        .delete()
        .eq('id', serviceId)
        .eq('company_id', companyId);
  }

  bool _isUuid(String value) {
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    return uuidRegex.hasMatch(value);
  }
}
