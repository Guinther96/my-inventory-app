import 'dart:io';
import 'dart:math';

import 'package:my_inventory_app/core/constants/app_constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  SupabaseClient get _client => Supabase.instance.client;

  void _ensureSupabaseConfigured() {
    if (!AppConstants.isSupabaseConfigured) {
      throw Exception(
        'Configuration Supabase manquante: renseignez supabaseUrl et supabaseAnonKey dans lib/core/constants/app_constants.dart',
      );
    }
  }

  User? get currentUser => _client.auth.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    _ensureSupabaseConfigured();
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
      await _ensureCompanyForCurrentUser();

      final linkedToCompany = await _isCurrentUserLinkedToCompany();
      if (!linkedToCompany) {
        throw Exception(
          'Compte en attente d\'activation. Demandez a votre manager de vous ajouter dans Utilisateurs.',
        );
      }
    } on SocketException {
      throw Exception(_networkErrorMessage());
    } on AuthException catch (e) {
      throw Exception(_readableAuthError(e));
    } on PostgrestException catch (e) {
      throw Exception(_readablePostgrestError(e));
    } catch (e) {
      if (e.toString().toLowerCase().contains('failed host lookup')) {
        throw Exception(_networkErrorMessage());
      }
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    _ensureSupabaseConfigured();

    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      throw Exception('Email requis.');
    }

    try {
      await _client.auth.resetPasswordForEmail(
        normalizedEmail,
        redirectTo: AppConstants.passwordResetRedirectUrl,
      );
    } on SocketException {
      throw Exception(_networkErrorMessage());
    } on AuthException catch (e) {
      throw Exception(_readableAuthError(e));
    } catch (e) {
      if (e.toString().toLowerCase().contains('failed host lookup')) {
        throw Exception(_networkErrorMessage());
      }
      rethrow;
    }
  }

  Future<void> signUpWithCompany({
    required String email,
    required String password,
    required String companyName,
  }) async {
    _ensureSupabaseConfigured();
    final AuthResponse authResponse;

    try {
      authResponse = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'name': companyName, 'account_type': 'company_owner'},
        emailRedirectTo: AppConstants.emailConfirmationRedirectUrl,
      );
    } on SocketException {
      throw Exception(_networkErrorMessage());
    } on AuthException catch (e) {
      final recovered = await _recoverFromSignUpAuthError(
        error: e,
        email: email,
        password: password,
      );
      if (recovered) {
        await _ensureCompanyForCurrentUser();
        return;
      }
      throw Exception(_readableAuthError(e));
    } catch (e) {
      if (e.toString().toLowerCase().contains('failed host lookup')) {
        throw Exception(_networkErrorMessage());
      }
      rethrow;
    }

    if (authResponse.user == null) {
      throw Exception('Inscription impossible.');
    }

    if (authResponse.session == null) {
      // Email confirmation is enabled: company row will be created on first login.
      throw Exception(
        'Compte cree. Un email de confirmation vous a ete envoye. Confirmez votre email puis connectez-vous pour finaliser la creation de votre entreprise.',
      );
    }

    try {
      await _createCompanyForCurrentUser(
        companyName: companyName,
        email: email,
      );
    } on PostgrestException catch (e) {
      throw Exception(_readablePostgrestError(e));
    }
  }

  Future<void> signUpStaffAccount({
    required String email,
    required String password,
  }) async {
    _ensureSupabaseConfigured();

    try {
      final authResponse = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'account_type': 'staff'},
        emailRedirectTo: AppConstants.emailConfirmationRedirectUrl,
      );

      if (authResponse.user == null) {
        throw Exception('Inscription impossible.');
      }

      if (authResponse.session == null) {
        throw Exception(
          'Compte cree. Un email de confirmation vous a ete envoye. Confirmez votre email, puis demandez a votre manager de vous activer dans Utilisateurs.',
        );
      }

      // If email confirmation is disabled, Supabase may open a session.
      // Keep the app on the login flow after staff registration.
      if (authResponse.session != null) {
        await _client.auth.signOut();
      }
    } on SocketException {
      throw Exception(_networkErrorMessage());
    } on AuthException catch (e) {
      throw Exception(_readableAuthError(e));
    } catch (e) {
      if (e.toString().toLowerCase().contains('failed host lookup')) {
        throw Exception(_networkErrorMessage());
      }
      rethrow;
    }
  }

  Future<void> _ensureCompanyForCurrentUser() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return;
    }

    final profile = await _client
        .from('users')
        .select('company_id')
        .eq('id', user.id)
        .maybeSingle();

    if (profile?['company_id'] != null) {
      return;
    }

    if (!_canAutoCreateCompany(user)) {
      return;
    }

    final metadataCompanyName = user.userMetadata?['name']?.toString();
    final fallbackName = _companyNameFromEmail(user.email);

    await _createCompanyForCurrentUser(
      companyName: metadataCompanyName?.trim().isNotEmpty == true
          ? metadataCompanyName!.trim()
          : fallbackName,
      email: user.email ?? 'unknown@example.com',
    );
  }

  bool _canAutoCreateCompany(User user) {
    final accountType = user.userMetadata?['account_type']
        ?.toString()
        .toLowerCase();
    if (accountType == 'staff') {
      return false;
    }
    if (accountType == 'company_owner') {
      return true;
    }

    // Legacy fallback: old company signups stored only "name" in metadata.
    final name = user.userMetadata?['name']?.toString().trim() ?? '';
    return name.isNotEmpty;
  }

  Future<bool> _isCurrentUserLinkedToCompany() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return false;
    }

    final row = await _client
        .from('users')
        .select('company_id')
        .eq('id', userId)
        .maybeSingle();

    final companyId = row?['company_id']?.toString();
    return companyId != null && companyId.isNotEmpty;
  }

  Future<void> _createCompanyForCurrentUser({
    required String companyName,
    required String email,
  }) async {
    await _client.rpc(
      'create_company_for_current_user',
      params: {'company_name': companyName, 'company_email': email},
    );
  }

  String _companyNameFromEmail(String? email) {
    final value = (email ?? '').trim();
    if (!value.contains('@')) {
      return 'Mon entreprise';
    }
    return value.split('@').first;
  }

  String _readableAuthError(AuthException error) {
    final message = error.message.trim();
    final lower = message.toLowerCase();

    if (lower.contains('unexpected_failure') &&
        lower.contains('error sending confirmation email')) {
      return 'Supabase n\'arrive pas a envoyer l\'email de confirmation. Verifiez dans Supabase: Auth > Email (provider actif), SMTP configure, et URL de redirection autorisee.';
    }

    if (_isEmailRateLimited(message)) {
      return 'Envoi d email temporairement limite par le service. Cela peut concerner tout le projet (pas seulement votre compte). Attendez quelques minutes puis reessayez.';
    }

    if (lower.contains('user already registered')) {
      return 'Cet email est deja inscrit. Essayez de vous connecter.';
    }

    if (lower.contains('invalid login credentials')) {
      return 'Identifiants invalides. Verifiez votre email et mot de passe, ou reinitialisez le mot de passe.';
    }

    if (lower.contains('error sending recovery email')) {
      return 'Supabase n\'arrive pas a envoyer l\'email de reinitialisation. Verifiez dans Supabase: Auth > Email (provider actif), SMTP configure, et URL de redirection autorisee.';
    }

    if (lower.contains('email not confirmed')) {
      return 'Email non confirme. Ouvrez votre boite mail et confirmez votre compte avant de vous connecter.';
    }

    if (message.isNotEmpty) {
      return message;
    }
    return 'Authentification impossible. Verifiez la configuration Supabase et vos identifiants.';
  }

  bool _isEmailRateLimited(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('email rate limit exceeded') ||
        normalized.contains('rate limit exceeded');
  }

  Future<bool> _recoverFromSignUpAuthError({
    required AuthException error,
    required String email,
    required String password,
  }) async {
    final message = error.message.toLowerCase();
    final canRecover = message.contains('user already registered');

    if (!canRecover) {
      return false;
    }

    try {
      await _client.auth.signInWithPassword(email: email, password: password);
      return _client.auth.currentUser != null;
    } on AuthException {
      return false;
    }
  }

  String _readablePostgrestError(PostgrestException error) {
    final message = (error.message).trim();
    final lower = message.toLowerCase();

    if (lower.contains('create_company_for_current_user') &&
        (lower.contains('does not exist') || lower.contains('not found'))) {
      return 'La fonction SQL create_company_for_current_user est absente. Executez le script supabase/sql/2026-03-09_inventory_hardening.sql dans Supabase SQL Editor.';
    }

    if (message.isNotEmpty) {
      return message;
    }
    return 'Erreur base de donnees pendant la creation du profil entreprise.';
  }

  String _networkErrorMessage() {
    return 'Connexion reseau impossible vers Supabase. Verifiez Internet sur l\'emulateur/appareil et confirmez que supabaseUrl est correct dans lib/core/constants/app_constants.dart.';
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<bool> prepareAuthenticatedSession() async {
    _ensureSupabaseConfigured();

    await _ensureCompanyForCurrentUser();
    return _isCurrentUserLinkedToCompany();
  }

  Future<void> resendSignupConfirmationEmail({required String email}) async {
    _ensureSupabaseConfigured();

    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      throw Exception('Email requis.');
    }

    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: normalizedEmail,
        emailRedirectTo: AppConstants.emailConfirmationRedirectUrl,
      );
    } on SocketException {
      throw Exception(_networkErrorMessage());
    } on AuthException catch (e) {
      throw Exception(_readableAuthError(e));
    } catch (e) {
      if (e.toString().toLowerCase().contains('failed host lookup')) {
        throw Exception(_networkErrorMessage());
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Invite code helpers
  // ---------------------------------------------------------------------------

  /// Generates a readable 8-character invite code for staff accounts.
  /// Format: XXXX-XXXX (uppercase letters + digits, no ambiguous chars).
  String generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    final part1 = List.generate(
      4,
      (_) => chars[rng.nextInt(chars.length)],
    ).join();
    final part2 = List.generate(
      4,
      (_) => chars[rng.nextInt(chars.length)],
    ).join();
    return '$part1-$part2';
  }

  /// Creates a staff auth account using [email] and [tempPassword] as the
  /// initial password, then signs out so the manager stays logged in.
  Future<void> signUpStaffAccountWithCode({
    required String email,
    required String tempPassword,
  }) async {
    _ensureSupabaseConfigured();

    try {
      final authResponse = await _client.auth.signUp(
        email: email,
        password: tempPassword,
        data: {'account_type': 'staff'},
        emailRedirectTo: AppConstants.emailConfirmationRedirectUrl,
      );

      if (authResponse.user == null) {
        throw Exception('Inscription impossible.');
      }

      // If email confirmation is disabled Supabase opens a session immediately.
      // Immediately sign out so the manager's session is restored on next call.
      if (authResponse.session != null) {
        await _client.auth.signOut();
      }
    } on SocketException {
      throw Exception(_networkErrorMessage());
    } on AuthException catch (e) {
      throw Exception(_readableAuthError(e));
    } catch (e) {
      if (e.toString().toLowerCase().contains('failed host lookup')) {
        throw Exception(_networkErrorMessage());
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Password change
  // ---------------------------------------------------------------------------

  /// Changes the current user's password to [newPassword].
  /// Requires the user to be signed in.
  Future<void> changePassword(String newPassword) async {
    _ensureSupabaseConfigured();

    if (newPassword.length < 8) {
      throw Exception('Le mot de passe doit contenir au moins 8 caracteres.');
    }

    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
      // Clear the must_change_password flag in the profile table.
      await _client.rpc('clear_must_change_password');
    } on AuthException catch (e) {
      throw Exception(_readableAuthError(e));
    } on PostgrestException catch (e) {
      // RPC errors are non-fatal for the password change itself.
      throw Exception(e.message);
    }
  }

  // ---------------------------------------------------------------------------
  // must_change_password check
  // ---------------------------------------------------------------------------

  /// Returns true when the signed-in user must change their password before
  /// accessing the app normally.
  Future<bool> mustChangePassword() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return false;
    }

    try {
      final row = await _client
          .from('users')
          .select('must_change_password')
          .eq('id', userId)
          .maybeSingle();

      return row?['must_change_password'] == true;
    } catch (_) {
      return false;
    }
  }
}
