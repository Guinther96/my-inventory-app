import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/user/user_profile_service.dart';
import '../../services/features/feature_access_service.dart';
import '../security/route_access_guard.dart';
import '../../data/providers/user_profile_provider.dart';

import '../../presentation/features/auth/screens/change_password_screen.dart';
import '../../presentation/features/auth/screens/confirm_email_screen.dart';
import '../../presentation/features/auth/screens/forgot_password_screen.dart';
import '../../presentation/features/auth/screens/login_screen.dart';
import '../../presentation/features/auth/screens/splash_screen.dart';
import '../../presentation/features/auth/screens/unauthorized_screen.dart';
import '../../presentation/features/dashboard/screens/dashboard_screen.dart';
import '../../presentation/features/inventory/screens/categories_screen.dart';
import '../../presentation/features/inventory/screens/inventory_screen.dart';
import '../../presentation/features/products/screens/products_screen.dart';
import '../../presentation/features/reports/screens/reports_screen.dart';
import '../../presentation/features/reports/screens/settings_screen.dart';
import '../../presentation/features/reports/screens/user_roles_screen.dart';
import '../../presentation/features/sales/screens/sales_screen.dart';
import '../../data/models/reservation_model.dart';
import '../../presentation/features/services/screens/create_service_order_screen.dart';
import '../../presentation/features/services/screens/reservation_screen.dart';
import '../../presentation/features/services/screens/services_management_screen.dart';
import '../../presentation/features/provider/screens/provider_dashboard_screen.dart';
import '../../presentation/features/provider/screens/add_reservation_screen.dart';
import '../../presentation/features/provider/screens/provider_reservations_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/splash',
  refreshListenable: FeatureAccessService.instance.routerRefreshListenable,
  redirect: (context, state) {
    final authCallbackRedirect = _resolveAuthCallbackRedirect(state);
    if (authCallbackRedirect != null) {
      return authCallbackRedirect;
    }

    final isLoggedIn = _isLoggedInSafely();
    final isLoginRoute = state.matchedLocation == '/login';
    final isSplashRoute = state.matchedLocation == '/splash';
    final isChangePasswordRoute = state.matchedLocation == '/change-password';
    final isConfirmEmailRoute = state.matchedLocation == '/confirm-email';
    final isForgotPasswordRoute = state.matchedLocation == '/forgot-password';

    if (isSplashRoute) {
      return null;
    }

    if (isConfirmEmailRoute) {
      return null;
    }

    if (isForgotPasswordRoute) {
      return null;
    }

    if (isChangePasswordRoute) {
      return null;
    }

    if (!isLoggedIn &&
        !isLoginRoute &&
        !isConfirmEmailRoute &&
        !isForgotPasswordRoute) {
      return '/login';
    }

    if (isLoggedIn && isLoginRoute) {
      final userProvider = context.read<UserProfileProvider>();
      if (userProvider.isManager) return '/';
      if (userProvider.isProvider) return '/provider/dashboard';
      return '/sales';
    }

    if (isLoggedIn && !isChangePasswordRoute) {
      final userProvider = context.read<UserProfileProvider>();
      final snapshot = FeatureAccessService.instance.snapshot;

      // Data not yet loaded: allow provisionally.
      // refreshListenable will trigger re-evaluation once data arrives.
      if (!userProvider.isInitialized || !snapshot.hasCompany) {
        return null;
      }

      if (userProvider.mustChangePassword) {
        return '/change-password';
      }

      final decision = RouteAccessGuard.evaluateSync(
        route: state.matchedLocation,
        role: userProvider.role,
      );
      if (!decision.allowed) {
        final encodedMessage = Uri.encodeQueryComponent(
          decision.message ?? 'Acces non autorise.',
        );
        final encodedFrom = Uri.encodeQueryComponent(state.matchedLocation);
        return '/unauthorized?message=$encodedMessage&from=$encodedFrom';
      }
    }

    return null;
  },
  routes: [
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => ForgotPasswordScreen(
        initialEmail: state.uri.queryParameters['email'] ?? '',
      ),
    ),
    GoRoute(
      path: '/confirm-email',
      builder: (context, state) {
        final callbackParams = _mergedAuthCallbackParams(state.uri);
        return ConfirmEmailScreen(
          initialEmail:
              callbackParams['email'] ??
              state.uri.queryParameters['email'] ??
              '',
          isConfirmed: state.uri.queryParameters['confirmed'] == '1',
          waitingForActivation: state.uri.queryParameters['waiting'] == '1',
          callbackType: callbackParams['type'],
          callbackTokenHash: callbackParams['token_hash'],
          callbackCode: callbackParams['code'],
          authErrorCode: callbackParams['error_code'],
          authErrorDescription: callbackParams['error_description'],
        );
      },
    ),
    GoRoute(path: '/', builder: (context, state) => const DashboardScreen()),
    GoRoute(
      path: '/products',
      builder: (context, state) => const ProductsScreen(),
    ),
    GoRoute(
      path: '/categories',
      builder: (context, state) => const CategoriesScreen(),
    ),
    GoRoute(
      path: '/movements',
      builder: (context, state) => const InventoryScreen(),
    ),
    GoRoute(path: '/sales', builder: (context, state) => const SalesScreen()),
    GoRoute(
      path: '/beauty/services',
      builder: (context, state) => const ServicesManagementScreen(),
    ),
    GoRoute(
      path: '/beauty/reservations',
      builder: (context, state) => const ReservationScreen(),
    ),
    GoRoute(
      path: '/beauty/orders/new',
      builder: (context, state) => CreateServiceOrderScreen(
        initialReservation: state.extra is Reservation
            ? state.extra as Reservation
            : null,
      ),
    ),
    GoRoute(
      path: '/reports',
      builder: (context, state) => const ReportsScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/change-password',
      builder: (context, state) => const ChangePasswordScreen(),
    ),
    GoRoute(
      path: '/unauthorized',
      builder: (context, state) {
        return UnauthorizedScreen(
          message:
              state.uri.queryParameters['message'] ?? 'Acces non autorise.',
          redirectPath: state.uri.queryParameters['from'],
        );
      },
    ),
    GoRoute(
      path: '/users',
      builder: (context, state) => const UserRolesScreen(),
    ),
    GoRoute(
      path: '/provider/dashboard',
      builder: (context, state) => const ProviderDashboardScreen(),
    ),
    GoRoute(
      path: '/provider/reservations',
      builder: (context, state) => const ProviderReservationsScreen(),
    ),
    GoRoute(
      path: '/provider/reservations/new',
      builder: (context, state) => const AddReservationScreen(),
    ),
  ],
);

bool _isLoggedInSafely() {
  try {
    return Supabase.instance.client.auth.currentUser != null;
  } catch (_) {
    return false;
  }
}

String? _resolveAuthCallbackRedirect(GoRouterState state) {
  final params = _mergedAuthCallbackParams(state.uri);
  if (params.isEmpty) {
    return null;
  }

  final hasAuthOutcome =
      params.containsKey('error') ||
      params.containsKey('error_code') ||
      params.containsKey('access_token') ||
      params.containsKey('refresh_token') ||
      params.containsKey('token_hash') ||
      params.containsKey('type');
  if (!hasAuthOutcome) {
    return null;
  }

  final currentPath = state.matchedLocation;
  final targetPath = _resolveAuthCallbackTarget(params);
  if (currentPath == targetPath) {
    return null;
  }

  final targetQuery = <String, String>{...state.uri.queryParameters, ...params};
  targetQuery.removeWhere((key, value) => value.trim().isEmpty);

  return Uri(path: targetPath, queryParameters: targetQuery).toString();
}

String _resolveAuthCallbackTarget(Map<String, String> params) {
  final callbackType = params['type']?.trim().toLowerCase() ?? '';
  final isRecovery =
      callbackType == 'recovery' ||
      params['recovery'] == '1' ||
      params.containsKey('new_password');

  return isRecovery ? '/change-password' : '/confirm-email';
}

Map<String, String> _mergedAuthCallbackParams(Uri uri) {
  final params = <String, String>{...uri.queryParameters};
  final fragment = uri.fragment.trim();

  if (fragment.isEmpty || fragment.startsWith('/')) {
    return params;
  }

  try {
    final fragmentParams = Uri.splitQueryString(fragment);
    for (final entry in fragmentParams.entries) {
      if (entry.value.trim().isNotEmpty) {
        params[entry.key] = entry.value;
      }
    }
  } catch (_) {
    // Ignore malformed fragments and keep normal routing behavior.
  }

  return params;
}
