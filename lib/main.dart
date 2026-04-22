import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:my_inventory_app/core/constants/app_constants.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/providers/feature_access_provider.dart';
import 'data/providers/inventory_provider.dart';
import 'data/providers/user_profile_provider.dart';
import 'services/auth/auth_service.dart';
import 'services/user/user_profile_service.dart';

int _mainInvocationCount = 0;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    usePathUrlStrategy();
  }

  final invocation = ++_mainInvocationCount;
  final bootTimestamp = DateTime.now().toIso8601String();
  final runtime = kIsWeb ? 'web' : 'native';

  if (!kReleaseMode) {
    debugPrint('DEBUG: Boot #$invocation started at $bootTimestamp ($runtime)');
    if (invocation > 1) {
      debugPrint(
        'INFO: main() invoked again. This is expected after hot restart, '
        'browser reload, or debugger reconnect.',
      );
    }
  }

  runApp(const InventoryApp());
}

Future<bool> _initializeSupabase() async {
  if (!AppConstants.isSupabaseConfigured) {
    debugPrint('WARNING: Supabase not configured - skipping initialization');
    return false;
  }

  try {
    debugPrint(
      'DEBUG: Initializing Supabase with URL: ${AppConstants.supabaseUrl}',
    );
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    ).timeout(const Duration(seconds: 12));
    debugPrint('DEBUG: Supabase initialized successfully');
    return true;
  } on TimeoutException catch (e) {
    debugPrint('ERROR: Supabase initialization timed out: $e');
    return false;
  } catch (e, stackTrace) {
    debugPrint('ERROR: Supabase initialization failed: $e');
    debugPrint('STACKTRACE: $stackTrace');
    return false;
  }
}

class InventoryApp extends StatefulWidget {
  const InventoryApp({super.key});

  @override
  State<InventoryApp> createState() => _InventoryAppState();
}

class _InventoryAppState extends State<InventoryApp> {
  final UserProfileProvider _userProfileProvider = UserProfileProvider();
  final InventoryProvider _inventoryProvider = InventoryProvider();
  final FeatureAccessProvider _featureAccessProvider = FeatureAccessProvider();
  StreamSubscription<AuthState>? _authSubscription;
  String? _lastHandledAccessToken;
  bool _supabaseInitialized = false;

  Future<void> _yieldToUi() async {
    // Give the UI thread a chance to paint before continuing boot work.
    await Future<void>.delayed(Duration.zero);
    await SchedulerBinding.instance.endOfFrame;
  }

  Future<void> _initializeRuntime() async {
    debugPrint('DEBUG: Starting application initialization...');

    final initialized = await _initializeSupabase();
    if (initialized) {
      debugPrint('DEBUG: Supabase initialization completed successfully');
    } else {
      debugPrint(
        'WARNING: Supabase initialization unavailable, starting app anyway',
      );
    }

    if (!mounted) {
      return;
    }

    _supabaseInitialized = initialized;

    if (AppConstants.isSupabaseConfigured && _supabaseInitialized) {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen(_handleAuthStateChange);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_bootstrapProvidersAfterFirstFrame());
    });
  }

  Future<void> _bootstrapProvidersAfterFirstFrame() async {
    if (!AppConstants.isSupabaseConfigured || !_supabaseInitialized) {
      _userProfileProvider.clear();
      return;
    }

    try {
      await _yieldToUi();
      await _featureAccessProvider.initialize();

      final hasSession =
          Supabase.instance.client.auth.currentSession?.accessToken != null;
      if (!hasSession) {
        _userProfileProvider.clear();
        return;
      }

      await _yieldToUi();
      await _userProfileProvider.initialize();

      // Inventory refresh can be expensive with large payloads, so defer it.
      unawaited(
        _inventoryProvider.initialize().catchError((
          Object error,
          StackTrace s,
        ) {
          debugPrint('ERROR: Deferred inventory bootstrap failed: $error');
          debugPrint('STACKTRACE: $s');
        }),
      );
    } catch (e, stackTrace) {
      debugPrint('ERROR: Deferred provider bootstrap failed: $e');
      debugPrint('STACKTRACE: $stackTrace');
    }
  }

  void _scheduleRouterGo(String location) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      appRouter.go(location);
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_initializeRuntime());
  }

  Future<void> _handleAuthStateChange(AuthState authState) async {
    final event = authState.event;
    final session = authState.session;
    final currentLocation = appRouter.routeInformationProvider.value.uri
        .toString();
    final isConfirmEmailFlow = currentLocation.startsWith('/confirm-email');

    if (event == AuthChangeEvent.passwordRecovery) {
      if (session != null) {
        _lastHandledAccessToken = session.accessToken;
      }
      if (mounted) {
        _scheduleRouterGo('/change-password');
      }
      return;
    }

    if (session == null) {
      _lastHandledAccessToken = null;
      _userProfileProvider.clear();
      await _featureAccessProvider.forceRefresh();
      return;
    }

    if (event != AuthChangeEvent.signedIn &&
        event != AuthChangeEvent.initialSession) {
      return;
    }

    // Do not auto-redirect while the user is on email confirmation flow.
    // This prevents jumping into an existing account immediately after
    // opening a confirmation link.
    if (isConfirmEmailFlow) {
      return;
    }

    if (_lastHandledAccessToken == session.accessToken) {
      return;
    }
    _lastHandledAccessToken = session.accessToken;

    try {
      final authService = AuthService();
      final linkedToCompany = await authService.prepareAuthenticatedSession();
      await _yieldToUi();
      await _featureAccessProvider.forceRefresh();
      await _yieldToUi();
      await _userProfileProvider.initialize(forceRefresh: true);

      if (!mounted) {
        return;
      }

      if (!linkedToCompany) {
        final email = session.user.email ?? '';
        final encodedEmail = Uri.encodeQueryComponent(email);
        _scheduleRouterGo(
          '/confirm-email?email=$encodedEmail&confirmed=1&waiting=1',
        );
        return;
      }

      final mustChange = await UserProfileService().fetchMustChangePassword();
      if (mustChange) {
        _scheduleRouterGo('/change-password');
        return;
      }

      final target = await UserProfileService().defaultHomeRoute();
      _scheduleRouterGo(target);

      unawaited(
        _inventoryProvider.initialize(forceRefresh: true).catchError((
          Object error,
          StackTrace s,
        ) {
          debugPrint('ERROR: Background inventory refresh failed: $error');
          debugPrint('STACKTRACE: $s');
        }),
      );
    } catch (e, stackTrace) {
      // Log errors instead of silently suppressing them during startup
      debugPrint('ERROR: Post-auth setup failed: $e');
      debugPrint('STACKTRACE: $stackTrace');
      // Keep the default router behavior if post-confirmation setup fails.
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _userProfileProvider.dispose();
    _inventoryProvider.dispose();
    _featureAccessProvider.dispose();
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
        ChangeNotifierProvider<FeatureAccessProvider>.value(
          value: _featureAccessProvider,
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
