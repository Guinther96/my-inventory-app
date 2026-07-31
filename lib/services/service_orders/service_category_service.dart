import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/service_category_model.dart';

class ServiceCategoryService {
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

  Future<List<ServiceCategory>> fetchCategories({
    bool activeOnly = false,
  }) async {
    final companyId = await _resolveCompanyId();

    var query = _client
        .from('service_categories')
        .select()
        .eq('company_id', companyId);

    if (activeOnly) {
      query = query.eq('is_active', true);
    }

    final rows = await query.order('name');
    return (rows as List<dynamic>)
        .map(
          (row) =>
              ServiceCategory.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<ServiceCategory> upsertCategory(ServiceCategory category) async {
    final companyId = await _resolveCompanyId();
    final isNew = category.id.trim().isEmpty;

    final payload = <String, dynamic>{
      if (!isNew) 'id': category.id,
      'company_id': companyId,
      'name': category.name,
      'description': category.description,
      'image_url': category.imageUrl,
      'is_active': category.isActive,
    };

    final row = await _client
        .from('service_categories')
        .upsert(payload)
        .select()
        .single();
    return ServiceCategory.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> deleteCategory(String categoryId) async {
    final companyId = await _resolveCompanyId();

    await _client
        .from('service_categories')
        .delete()
        .eq('id', categoryId)
        .eq('company_id', companyId);
  }
}
