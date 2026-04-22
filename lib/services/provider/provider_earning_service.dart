import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/provider_earning_model.dart';

class ProviderEarningService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<String> _currentUserId() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Utilisateur non authentifié.');
    return uid;
  }

  Future<List<ProviderEarning>> fetchEarnings({
    DateTime? from,
    DateTime? to,
  }) async {
    final userId = await _currentUserId();

    var query = _client
        .from('provider_earnings')
        .select()
        .eq('provider_id', userId);

    if (from != null) {
      query = query.gte('created_at', from.toIso8601String());
    }
    if (to != null) {
      query = query.lte('created_at', to.toIso8601String());
    }

    final rows = await query.order('created_at', ascending: false);
    return (rows as List<dynamic>)
        .map((r) => ProviderEarning.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<double> fetchTotalEarnings({DateTime? from, DateTime? to}) async {
    final earnings = await fetchEarnings(from: from, to: to);
    var total = 0.0;
    for (final earning in earnings) {
      total += earning.amount;
    }
    return total;
  }
}
