import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/security/route_access_guard.dart';
import '../models/user_profile_model.dart';
import '../../services/features/feature_access_service.dart';

class FeatureAccessProvider extends ChangeNotifier {
  FeatureAccessProvider({FeatureAccessService? service})
    : _service = service ?? FeatureAccessService.instance;

  final FeatureAccessService _service;

  StreamSubscription<FeatureAccessSnapshot>? _changesSubscription;
  bool _initialized = false;

  FeatureAccessSnapshot _snapshot = FeatureAccessSnapshot.empty;

  FeatureAccessSnapshot get snapshot => _snapshot;
  bool get isSuspended => _snapshot.isSuspended;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _initialized = true;
    await _service.initialize();
    _snapshot = _service.snapshot;

    _changesSubscription = _service.changes.listen((next) {
      _snapshot = next;
      notifyListeners();
    });

    notifyListeners();
  }

  Future<void> forceRefresh() async {
    await _service.forceRefresh();
  }

  bool canAccess(String featureKey) {
    return _snapshot.canAccess(featureKey);
  }

  bool canAccessRoute({required String route, required AppRole role}) {
    return RouteAccessGuard.evaluateSync(route: route, role: role).allowed;
  }

  @visibleForTesting
  void debugSetSnapshot(FeatureAccessSnapshot snapshot) {
    _snapshot = snapshot;
    notifyListeners();
  }

  @override
  void dispose() {
    _changesSubscription?.cancel();
    _changesSubscription = null;
    super.dispose();
  }
}

