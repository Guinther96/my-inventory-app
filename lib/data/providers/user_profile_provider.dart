import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../core/security/route_access_guard.dart';
import '../models/user_profile_model.dart';
import '../../services/user/user_profile_service.dart';

class UserProfileProvider extends ChangeNotifier {
  final UserProfileService _service = UserProfileService();

  UserProfile? _profile;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _errorMessage;
  bool _mustChangePassword = false;

  UserProfile? get profile => _profile;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;
  bool get mustChangePassword => _mustChangePassword;

  AppRole get role => _profile?.role ?? AppRole.seller;
  bool get isManager => role == AppRole.manager;
  bool get isSeller => role == AppRole.seller;
  bool get isProvider => role == AppRole.provider;

  Future<void> initialize({bool forceRefresh = false}) async {
    if (_isInitialized && !forceRefresh) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _profile = await _service.fetchCurrentProfile();
      _mustChangePassword = await _service.fetchMustChangePassword();
      _isInitialized = true;
    } catch (e) {
      _profile = null;
      _mustChangePassword = false;
      _errorMessage = e.toString();
      _isInitialized = true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool canAccessRoute(String route) {
    final decision = RouteAccessGuard.evaluateSync(route: route, role: role);
    return decision.allowed;
  }

  void clear() {
    _profile = null;
    _isLoading = false;
    _isInitialized = false;
    _errorMessage = null;
    _mustChangePassword = false;
    _service.clearRoleCache();
    notifyListeners();
  }
}
