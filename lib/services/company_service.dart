import 'package:supabase_flutter/supabase_flutter.dart';

class CompanyService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<String?> ensureCurrentCompanyId() async {
    final existing = await fetchCurrentCompanyId();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final user = _client.auth.currentUser;
    if (user == null) {
      return null;
    }

    final accountType = user.userMetadata?['account_type']
        ?.toString()
        .toLowerCase();
    if (accountType == 'staff') {
      return null;
    }

    final metadataName = user.userMetadata?['name']?.toString().trim();
    final companyName = (metadataName != null && metadataName.isNotEmpty)
        ? metadataName
        : _companyNameFromEmail(user.email);

    await _client.rpc(
      'create_company_for_current_user',
      params: {
        'company_name': companyName,
        'company_email': user.email ?? 'unknown@example.com',
      },
    );

    return fetchCurrentCompanyId();
  }

  Future<String?> fetchCurrentCompanyId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return null;
    }

    final row = await _client
        .from('users')
        .select('company_id')
        .eq('id', userId)
        .maybeSingle();

    return row?['company_id']?.toString();
  }

  String _companyNameFromEmail(String? email) {
    final value = (email ?? '').trim();
    if (!value.contains('@')) {
      return 'Mon entreprise';
    }
    return value.split('@').first;
  }

  Future<String?> fetchSubscriptionStatus(String companyId) async {
    final row = await _client
        .from('companies')
        .select('subscription_status')
        .eq('id', companyId)
        .maybeSingle();

    return row?['subscription_status']?.toString();
  }

  Future<String?> fetchCompanyName(String companyId) async {
    final row = await _client
        .from('companies')
        .select('name')
        .eq('id', companyId)
        .maybeSingle();

    return row?['name']?.toString();
  }
}
