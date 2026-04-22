import 'package:flutter/foundation.dart';

class AppConstants {
  static const String appName = 'BiznisPlus';

  static const String supabaseUrl = 'https://ylzkzcogrmzcnwviktya.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_FoRe55nJnCDrqJ7A3IBRWw_eN97kzbE';

  static const String _emailConfirmRedirectFromEnv = String.fromEnvironment(
    'EMAIL_CONFIRM_REDIRECT_URL',
    defaultValue: '',
  );

  static const String _passwordResetRedirectFromEnv = String.fromEnvironment(
    'PASSWORD_RESET_REDIRECT_URL',
    defaultValue: '',
  );

  static bool get isSupabaseConfigured {
    final url = supabaseUrl.trim();
    final key = supabaseAnonKey.trim();

    return url.isNotEmpty && key.isNotEmpty;
  }

  static String? get emailConfirmationRedirectUrl {
    final fromEnv = _emailConfirmRedirectFromEnv.trim();
    if (fromEnv.isNotEmpty) {
      return fromEnv;
    }

    return _buildPublicWebRedirect('/confirm-email?confirmed=1');
  }

  static String? get passwordResetRedirectUrl {
    final fromEnv = _passwordResetRedirectFromEnv.trim();
    if (fromEnv.isNotEmpty) {
      return fromEnv;
    }

    return _buildPublicWebRedirect('/change-password?recovery=1');
  }

  static String? _buildPublicWebRedirect(String path) {
    if (!kIsWeb) {
      return null;
    }

    final base = Uri.base;
    final host = base.host.trim().toLowerCase();
    final scheme = base.scheme.trim().toLowerCase();
    final isLocalHost =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';

    if (host.isEmpty ||
        scheme.isEmpty ||
        (scheme != 'http' && scheme != 'https')) {
      return null;
    }

    // Allow localhost redirects during web debug to simplify local auth tests.
    if (isLocalHost && kReleaseMode) {
      return null;
    }

    final origin = Uri(
      scheme: scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
    ).toString();

    final normalizedOrigin = origin.endsWith('/')
        ? origin.substring(0, origin.length - 1)
        : origin;

    return '$normalizedOrigin$path';
  }
}
