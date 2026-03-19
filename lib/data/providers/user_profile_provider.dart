import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../models/user_profile_model.dart';
import '../../services/user_profile_service.dart';

class UserProfileProvider extends ChangeNotifier {
  final UserProfileService _service = UserProfileService();

  UserProfile? _profile;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _errorMessage;

  UserProfile? get profile => _profile;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;

  AppRole get role => _profile?.role ?? AppRole.seller;
  bool get isManager => role == AppRole.manager;
  bool get isSeller => role == AppRole.seller;

  Future<void> initialize({bool forceRefresh = false}) async {
    if (_isInitialized && !forceRefresh) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _profile = await _service.fetchCurrentProfile();
      _isInitialized = true;
    } catch (e) {
      _profile = null;
      _errorMessage = e.toString();
      _isInitialized = true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool canAccessRoute(String route) {
    if (isManager) {
      return true;
    }

    return route == '/' ||
        route.startsWith('/sales') ||
        route.startsWith('/beauty/services') ||
        route.startsWith('/beauty/reservations') ||
        route.startsWith('/beauty/orders/new') ||
        route.startsWith('/reports') ||
        route.startsWith('/settings') ||
        route == '/login';
  }

  void clear() {
    _profile = null;
    _isLoading = false;
    _isInitialized = false;
    _errorMessage = null;
    _service.clearRoleCache();
    notifyListeners();
  }
}
