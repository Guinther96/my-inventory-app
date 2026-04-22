import 'package:supabase_flutter/supabase_flutter.dart';

import 'feature_access_service.dart';

class FeatureService {
  static SupabaseClient get _client => Supabase.instance.client;

  static void setFeatures(Map<String, dynamic> features) {
    // Kept for compatibility with old call sites. Source of truth is company_features.
  }

  static Map<String, dynamic> get features {
    final snapshot = FeatureAccessService.instance.snapshot;
    return Map<String, dynamic>.from(snapshot.features);
  }

  static bool isEnabled(String key) {
    return FeatureAccessService.instance.canAccessSync(key);
  }

  static Future<void> loadForCurrentUser() async {
    await FeatureAccessService.instance.initialize();
    await FeatureAccessService.instance.forceRefresh();
  }

  static Future<void> updateCompanyFeatures({
    required String companyId,
    required Map<String, dynamic> features,
  }) async {
    for (final entry in features.entries) {
      await _client.from('company_features').upsert(<String, dynamic>{
        'company_id': companyId,
        'feature_key': entry.key.trim().toLowerCase(),
        'enabled': entry.value == true,
      });
    }

    await FeatureAccessService.instance.forceRefresh();
  }

  static Future<void> updateFeatureFlag({
    required String companyId,
    required String key,
    required bool enabled,
  }) async {
    final merged = <String, dynamic>{...features, key: enabled};
    await updateCompanyFeatures(companyId: companyId, features: merged);
  }

  static Future<void> startRealtimeSync() async {
    await FeatureAccessService.instance.initialize();
    await FeatureAccessService.instance.forceRefresh();
  }

  static Future<void> stopRealtimeSync() async {
    // Centralized by FeatureAccessService auth/realtime lifecycle.
  }

  static void clear() {
    FeatureAccessService.instance.clear();
  }
}
