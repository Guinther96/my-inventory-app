import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:my_inventory_app/core/constants/app_constants.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/providers/inventory_provider.dart';
import 'data/providers/user_profile_provider.dart';
import 'services/auth_service.dart';
import 'services/user_profile_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _initializeSupabase();

  runApp(const InventoryApp());
}

Future<void> _initializeSupabase() async {
  if (!AppConstants.isSupabaseConfigured) {
    return;
  }

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );
}

class InventoryApp extends StatefulWidget {
  const InventoryApp({Key? key}) : super(key: key);

  @override
  State<InventoryApp> createState() => _InventoryAppState();
}

class _InventoryAppState extends State<InventoryApp> {
  final UserProfileProvider _userProfileProvider = UserProfileProvider();
  final InventoryProvider _inventoryProvider = InventoryProvider();
  StreamSubscription<AuthState>? _authSubscription;
  String? _lastHandledAccessToken;

  @override
  void initState() {
    super.initState();
    _userProfileProvider.initialize();
    _inventoryProvider.initialize();

    if (!AppConstants.isSupabaseConfigured) {
      return;
    }

    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      _handleAuthStateChange,
    );
  }

  Future<void> _handleAuthStateChange(AuthState authState) async {
    final event = authState.event;
    final session = authState.session;

    if (event == AuthChangeEvent.passwordRecovery) {
      if (session != null) {
        _lastHandledAccessToken = session.accessToken;
      }
      if (mounted) {
        appRouter.go('/change-password');
      }
      return;
    }

    if (session == null) {
      _lastHandledAccessToken = null;
      _userProfileProvider.clear();
      return;
    }

    if (event != AuthChangeEvent.signedIn &&
        event != AuthChangeEvent.initialSession) {
      return;
    }

    if (_lastHandledAccessToken == session.accessToken) {
      return;
    }
    _lastHandledAccessToken = session.accessToken;

    try {
      final authService = AuthService();
      final linkedToCompany = await authService.prepareAuthenticatedSession();
      await _userProfileProvider.initialize(forceRefresh: true);
      await _inventoryProvider.initialize(forceRefresh: true);

      if (!mounted) {
        return;
      }

      if (!linkedToCompany) {
        final email = session.user.email ?? '';
        final encodedEmail = Uri.encodeQueryComponent(email);
        appRouter.go(
          '/confirm-email?email=$encodedEmail&confirmed=1&waiting=1',
        );
        return;
      }

      final mustChange = await UserProfileService().fetchMustChangePassword();
      if (mustChange) {
        appRouter.go('/change-password');
        return;
      }

      final target = await UserProfileService().defaultHomeRoute();
      appRouter.go(target);
    } catch (_) {
      // Keep the default router behavior if post-confirmation setup fails.
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _userProfileProvider.dispose();
    _inventoryProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProfileProvider>.value(
          value: _userProfileProvider,
        ),
        ChangeNotifierProvider<InventoryProvider>.value(
          value: _inventoryProvider,
        ),
      ],
      child: MaterialApp.router(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: appRouter,
      ),
    );
  }
}
