import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/company_feature_model.dart';
import '../../data/models/company_model.dart';

class FeatureAccessSnapshot {
  final Company? company;
  final Map<String, bool> features;

  const FeatureAccessSnapshot({required this.company, required this.features});

  static const FeatureAccessSnapshot empty = FeatureAccessSnapshot(
    company: null,
    features: <String, bool>{},
  );

  bool get hasCompany => company != null;
  bool get isSuspended => company?.isSuspended == true;

  bool canAccess(String featureKey) {
    if (isSuspended) {
      return false;
    }

    final normalized = featureKey.trim().toLowerCase();
    if (normalized.isEmpty) {
      return !isSuspended;
    }

    return features[normalized] ?? true;
  }

  FeatureAccessSnapshot copyWith({
    Company? company,
    Map<String, bool>? features,
  }) {
    return FeatureAccessSnapshot(
      company: company ?? this.company,
      features: features ?? this.features,
    );
  }
}

class FeatureAccessService {
  FeatureAccessService._();

  static final FeatureAccessService instance = FeatureAccessService._();

  SupabaseClient get _client => Supabase.instance.client;

  final StreamController<FeatureAccessSnapshot> _changesController =
      StreamController<FeatureAccessSnapshot>.broadcast();
  final ValueNotifier<int> _routerRefresh = ValueNotifier<int>(0);

  StreamSubscription<AuthState>? _authSubscription;
  RealtimeChannel? _companiesChannel;
  RealtimeChannel? _companyFeaturesChannel;
  Timer? _reconnectTimer;

  FeatureAccessSnapshot _snapshot = FeatureAccessSnapshot.empty;
  bool _isInitialized = false;
  int _reconnectAttempt = 0;

  FeatureAccessSnapshot get snapshot => _snapshot;
  Stream<FeatureAccessSnapshot> get changes => _changesController.stream;
  Listenable get routerRefreshListenable => _routerRefresh;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    _isInitialized = true;
    _authSubscription = _client.auth.onAuthStateChange.listen((authState) {
      unawaited(_handleAuthStateChange(authState));
    });

    await refresh(forceResubscribe: true);
  }

  Future<void> _handleAuthStateChange(AuthState authState) async {
    if (authState.session == null) {
      await clear();
      return;
    }
    await refresh(forceResubscribe: true);
  }

  Future<void> refresh({bool forceResubscribe = false}) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        await clear();
        return;
      }

      final companyId = await _fetchCurrentCompanyId(userId);
      if (companyId == null || companyId.isEmpty) {
        _updateSnapshot(
          FeatureAccessSnapshot(
            company: null,
            features: const <String, bool>{},
          ),
        );
        await _unsubscribeRealtime();
        return;
      }

      final company = await _fetchCompany(companyId);
      final features = await _fetchFeatures(companyId);

      _updateSnapshot(
        FeatureAccessSnapshot(company: company, features: features),
      );

      if (forceResubscribe || !_isSubscribedToCompany(companyId)) {
        await _subscribeRealtime(companyId);
      }
    } catch (error, stackTrace) {
      debugPrint('FeatureAccessService.refresh failed: $error');
      debugPrintStack(
        stackTrace: stackTrace,
        label: 'FeatureAccessService.refresh stack',
      );
      _scheduleReconnect();
    }
  }

  Future<bool> canAccess(String featureKey) async {
    await initialize();
    return _snapshot.canAccess(featureKey);
  }

  bool canAccessSync(String featureKey) {
    return _snapshot.canAccess(featureKey);
  }

  Future<void> forceRefresh() async {
    await refresh(forceResubscribe: false);
  }

  Future<void> clear() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;

    await _unsubscribeRealtime();
    _updateSnapshot(FeatureAccessSnapshot.empty);
  }

  Future<void> dispose() async {
    await clear();
    await _authSubscription?.cancel();
    _authSubscription = null;
    _isInitialized = false;
    await _changesController.close();
    _routerRefresh.dispose();
  }

  Future<String?> _fetchCurrentCompanyId(String userId) async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final userRow = await _client
            .from('users')
            .select('company_id')
            .eq('id', userId)
            .maybeSingle();

        return userRow?['company_id']?.toString();
      } catch (error) {
        final shouldRetry =
            _isTransientNetworkError(error) && attempt < maxAttempts;
        if (!shouldRetry) {
          rethrow;
        }

        // Petit backoff pour lisser les coupures réseau temporaires.
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
      }
    }

    return null;
  }

  bool _isTransientNetworkError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('socketexception') ||
        message.contains('clientexception') ||
        message.contains('connection reset by peer') ||
        message.contains('connection closed') ||
        message.contains('timed out');
  }

  Future<Company?> _fetchCompany(String companyId) async {
    final companyRow = await _client
        .from('companies')
        .select('id, status, updated_at')
        .eq('id', companyId)
        .maybeSingle();

    if (companyRow == null) {
      return null;
    }

    return Company.fromJson(Map<String, dynamic>.from(companyRow));
  }

  Future<Map<String, bool>> _fetchFeatures(String companyId) async {
    final rows = await _client
        .from('company_features')
        .select('id, company_id, feature_key, enabled, updated_at')
        .eq('company_id', companyId);

    final mapped = <String, bool>{};
    for (final row in rows as List<dynamic>) {
      final feature = CompanyFeature.fromJson(Map<String, dynamic>.from(row));
      mapped[feature.normalizedFeatureKey] = feature.enabled;
    }
    return mapped;
  }

  Future<void> _subscribeRealtime(String companyId) async {
    await _unsubscribeRealtime();

    _companiesChannel = _client
        .channel('companies-access-$companyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'companies',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: companyId,
          ),
          callback: (_) {
            unawaited(_refreshCompanyOnly());
          },
        )
        .subscribe((status, [error]) {
          _handleRealtimeStatus(status, error);
        });

    _companyFeaturesChannel = _client
        .channel('company-features-access-$companyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'company_features',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'company_id',
            value: companyId,
          ),
          callback: (payload) {
            _applyCompanyFeaturePayload(payload);
          },
        )
        .subscribe((status, [error]) {
          _handleRealtimeStatus(status, error);
        });
  }

  Future<void> _refreshCompanyOnly() async {
    final companyId = _snapshot.company?.id;
    if (companyId == null || companyId.isEmpty) {
      return;
    }

    final company = await _fetchCompany(companyId);
    _updateSnapshot(_snapshot.copyWith(company: company));
  }

  void _applyCompanyFeaturePayload(PostgresChangePayload payload) {
    final features = Map<String, bool>.from(_snapshot.features);

    final newRecord = payload.newRecord;
    final oldRecord = payload.oldRecord;

    final newKey = newRecord['feature_key']?.toString().trim().toLowerCase();
    final oldKey = oldRecord['feature_key']?.toString().trim().toLowerCase();

    if (payload.eventType == PostgresChangeEvent.delete) {
      if (oldKey != null && oldKey.isNotEmpty) {
        features.remove(oldKey);
      }
      _updateSnapshot(_snapshot.copyWith(features: features));
      return;
    }

    if (newKey != null && newKey.isNotEmpty) {
      features[newKey] = newRecord['enabled'] == true;
      if (oldKey != null && oldKey.isNotEmpty && oldKey != newKey) {
        features.remove(oldKey);
      }
      _updateSnapshot(_snapshot.copyWith(features: features));
      return;
    }

    unawaited(forceRefresh());
  }

  void _handleRealtimeStatus(RealtimeSubscribeStatus status, Object? error) {
    if (status == RealtimeSubscribeStatus.subscribed) {
      _reconnectAttempt = 0;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      unawaited(forceRefresh());
      return;
    }

    if (status == RealtimeSubscribeStatus.closed ||
        status == RealtimeSubscribeStatus.channelError ||
        status == RealtimeSubscribeStatus.timedOut) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) {
      return;
    }

    _reconnectAttempt += 1;
    final backoffSeconds = (_reconnectAttempt * 2).clamp(2, 30);

    _reconnectTimer = Timer(Duration(seconds: backoffSeconds), () async {
      _reconnectTimer = null;
      final companyId = _snapshot.company?.id;
      if (companyId == null || companyId.isEmpty) {
        await refresh(forceResubscribe: true);
        return;
      }
      await refresh(forceResubscribe: true);
    });
  }

  bool _isSubscribedToCompany(String companyId) {
    return _companiesChannel != null && _companyFeaturesChannel != null;
  }

  Future<void> _unsubscribeRealtime() async {
    final companiesChannel = _companiesChannel;
    final companyFeaturesChannel = _companyFeaturesChannel;

    _companiesChannel = null;
    _companyFeaturesChannel = null;

    if (companiesChannel != null) {
      await _client.removeChannel(companiesChannel);
    }

    if (companyFeaturesChannel != null) {
      await _client.removeChannel(companyFeaturesChannel);
    }
  }

  void _updateSnapshot(FeatureAccessSnapshot next) {
    _snapshot = next;
    if (!_changesController.isClosed) {
      _changesController.add(next);
    }
    _routerRefresh.value = _routerRefresh.value + 1;
  }

  @visibleForTesting
  void debugSetSnapshot(FeatureAccessSnapshot snapshot) {
    _updateSnapshot(snapshot);
  }
}
