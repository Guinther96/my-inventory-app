import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/user_profile_service.dart';

import '../../presentation/features/auth/screens/change_password_screen.dart';
import '../../presentation/features/auth/screens/confirm_email_screen.dart';
import '../../presentation/features/auth/screens/login_screen.dart';
import '../../presentation/features/auth/screens/splash_screen.dart';
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

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/splash',
  redirect: (context, state) async {
    final isLoggedIn = _isLoggedInSafely();
    final isLoginRoute = state.matchedLocation == '/login';
    final isSplashRoute = state.matchedLocation == '/splash';
    final isChangePasswordRoute = state.matchedLocation == '/change-password';
    final isConfirmEmailRoute = state.matchedLocation == '/confirm-email';

    if (isSplashRoute) {
      return null;
    }

    if (isConfirmEmailRoute) {
      return null;
    }

    if (!isLoggedIn && !isLoginRoute && !isConfirmEmailRoute) {
      return '/login';
    }

    if (isLoggedIn && isLoginRoute) {
      return await UserProfileService().defaultHomeRoute();
    }

    if (isLoggedIn && !isChangePasswordRoute) {
      final mustChange = await UserProfileService().fetchMustChangePassword();
      if (mustChange) {
        return '/change-password';
      }

      final canAccess = await UserProfileService().canAccessRoute(
        state.matchedLocation,
      );

      if (!canAccess) {
        return await UserProfileService().defaultHomeRoute();
      }
    }

    return null;
  },
  routes: [
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/confirm-email',
      builder: (context, state) => ConfirmEmailScreen(
        initialEmail: state.uri.queryParameters['email'] ?? '',
        isConfirmed: state.uri.queryParameters['confirmed'] == '1',
        waitingForActivation: state.uri.queryParameters['waiting'] == '1',
      ),
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
      path: '/users',
      builder: (context, state) => const UserRolesScreen(),
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
