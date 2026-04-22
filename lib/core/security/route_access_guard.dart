import '../../data/models/user_profile_model.dart';
import '../../services/features/feature_access_service.dart';
import '../../services/user/user_profile_service.dart';

class AccessDecision {
  final bool allowed;
  final String? message;
  final String? featureKey;

  const AccessDecision._({
    required this.allowed,
    this.message,
    this.featureKey,
  });

  factory AccessDecision.allow() => const AccessDecision._(allowed: true);

  factory AccessDecision.deny({required String message, String? featureKey}) =>
      AccessDecision._(
        allowed: false,
        message: message,
        featureKey: featureKey,
      );
}

class RouteAccessGuard {
  static final List<_RouteRule> _rules = <_RouteRule>[
    _RouteRule(prefix: '/', featureKey: 'dashboard'),
    _RouteRule(prefix: '/products', featureKey: 'inventory', managerOnly: true),
    _RouteRule(
      prefix: '/categories',
      featureKey: 'inventory',
      managerOnly: true,
    ),
    _RouteRule(
      prefix: '/movements',
      featureKey: 'inventory',
      managerOnly: true,
    ),
    _RouteRule(prefix: '/sales', featureKey: 'sales'),
    _RouteRule(prefix: '/beauty/services', featureKey: 'services'),
    _RouteRule(prefix: '/beauty/reservations', featureKey: 'services'),
    _RouteRule(prefix: '/beauty/orders/new', featureKey: 'services'),
    _RouteRule(prefix: '/reports', featureKey: 'reports', managerOnly: true),
    _RouteRule(prefix: '/settings', featureKey: 'settings'),
    _RouteRule(prefix: '/users', featureKey: 'users', managerOnly: true),
    _RouteRule(prefix: '/provider/dashboard', featureKey: 'provider'),
    _RouteRule(prefix: '/provider/reservations', featureKey: 'provider'),
  ];

  static bool isPublicRoute(String route) {
    return route == '/login' ||
        route == '/splash' ||
        route == '/forgot-password' ||
        route == '/confirm-email' ||
        route == '/change-password' ||
        route == '/unauthorized';
  }

  static Future<AccessDecision> evaluate(String route) async {
    await FeatureAccessService.instance.initialize();
    final role = await UserProfileService().fetchCurrentRole();
    return evaluateSync(route: route, role: role);
  }

  static AccessDecision evaluateSync({
    required String route,
    required AppRole role,
  }) {
    if (isPublicRoute(route)) {
      return AccessDecision.allow();
    }

    final snapshot = FeatureAccessService.instance.snapshot;

    if (!snapshot.hasCompany) {
      return AccessDecision.deny(
        message: 'Compte non rattache a une entreprise. Acces non autorise.',
      );
    }

    if (snapshot.isSuspended) {
      return AccessDecision.deny(
        message: 'Entreprise suspendue. Acces non autorise.',
      );
    }

    final rule = _resolveRule(route);
    if (rule == null) {
      return AccessDecision.allow();
    }

    if (rule.managerOnly && role != AppRole.manager) {
      return AccessDecision.deny(
        message: 'Acces reserve au manager.',
        featureKey: rule.featureKey,
      );
    }

    if (!snapshot.canAccess(rule.featureKey)) {
      return AccessDecision.deny(
        message: 'Fonctionnalite desactivee pour votre entreprise.',
        featureKey: rule.featureKey,
      );
    }

    return AccessDecision.allow();
  }

  static _RouteRule? _resolveRule(String route) {
    _RouteRule? match;
    var bestLength = -1;

    for (final rule in _rules) {
      if (!route.startsWith(rule.prefix)) {
        continue;
      }
      final length = rule.prefix.length;
      if (length > bestLength) {
        bestLength = length;
        match = rule;
      }
    }

    return match;
  }
}

class _RouteRule {
  final String prefix;
  final String featureKey;
  final bool managerOnly;

  const _RouteRule({
    required this.prefix,
    required this.featureKey,
    this.managerOnly = false,
  });
}

