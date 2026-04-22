import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/security/route_access_guard.dart';
import '../../data/models/user_profile_model.dart';

class UserProfileService {
  SupabaseClient get _client => Supabase.instance.client;

  static final Map<String, _RoleCache> _roleCache = <String, _RoleCache>{};
  static const Duration _cacheTtl = Duration(seconds: 20);

  Future<UserProfile?> fetchCurrentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return null;
    }

    final row = await _client
        .from('users')
        .select('id, email, company_id, role')
        .eq('id', user.id)
        .maybeSingle();

    if (row == null) {
      return null;
    }

    final profile = UserProfile.fromJson(Map<String, dynamic>.from(row));
    _roleCache[user.id] = _RoleCache(
      role: profile.role,
      expiresAt: DateTime.now().add(_cacheTtl),
    );
    return profile;
  }

  Future<AppRole> fetchCurrentRole({bool forceRefresh = false}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return AppRole.seller;
    }

    final cached = _roleCache[userId];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().isBefore(cached.expiresAt)) {
      return cached.role;
    }

    try {
      final row = await _client
          .from('users')
          .select('role')
          .eq('id', userId)
          .maybeSingle();

      final rawRole = row?['role']?.toString().toLowerCase() ?? 'seller';
      final role = rawRole == 'manager'
        ? AppRole.manager
        : rawRole == 'provider'
        ? AppRole.provider
        : AppRole.seller;

      _roleCache[userId] = _RoleCache(
        role: role,
        expiresAt: DateTime.now().add(_cacheTtl),
      );

      return role;
    } catch (_) {
      return AppRole.seller;
    }
  }

  Future<bool> canAccessRoute(String route) async {
    final decision = await RouteAccessGuard.evaluate(route);
    return decision.allowed;
  }

  Future<String> defaultHomeRoute() async {
    final role = await fetchCurrentRole();
    if (role == AppRole.manager) {
      return '/';
    }
    if (role == AppRole.provider) {
      return '/provider/dashboard';
    }
    return '/sales';
  }

  Future<bool> fetchMustChangePassword() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
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

  Future<List<UserProfile>> fetchCompanyUsers() async {
    final companyId = await _fetchCurrentCompanyId();
    if (companyId == null || companyId.isEmpty) {
      return const <UserProfile>[];
    }

    final rows = await _client
        .from('users')
        .select('id, email, company_id, role')
        .eq('company_id', companyId)
        .order('created_at', ascending: true);

    return (rows as List<dynamic>)
        .map(
          (row) => UserProfile.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> updateUserRole({
    required String userId,
    required AppRole role,
  }) async {
    final companyId = await _fetchCurrentCompanyId();
    if (companyId == null || companyId.isEmpty) {
      throw Exception('Company introuvable pour la mise a jour du role.');
    }

    await _client
        .from('users')
        .update({'role': role.name})
        .eq('id', userId)
        .eq('company_id', companyId);

    if (_client.auth.currentUser?.id == userId) {
      clearRoleCache();
    }
  }

  Future<void> addUserToCompanyByEmail({
    required String email,
    required AppRole role,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      throw Exception('Email requis.');
    }

    try {
      await _client.rpc(
        'assign_user_to_company_by_email',
        params: {'p_email': normalizedEmail, 'p_role': role.name},
      );
    } on PostgrestException catch (e) {
      throw Exception(_readableAssignmentError(e));
    }
  }

  Future<void> removeUserFromCompany({required String userId}) async {
    await _client.rpc(
      'remove_user_from_company',
      params: {'p_user_id': userId},
    );

    if (_client.auth.currentUser?.id == userId) {
      clearRoleCache();
    }
  }

  Future<String?> _fetchCurrentCompanyId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return null;
    }

    final row = await _client
        .from('users')
        .select('company_id')
        .eq('id', userId)
        .maybeSingle();

    return row?['company_id']?.toString();
  }

  String _readableAssignmentError(PostgrestException error) {
    final message = error.message.trim();
    final lower = message.toLowerCase();

    if (lower.contains('aucun compte trouve pour cet email')) {
      return 'Aucun compte employe/prestataire n\'existe pour cet email. Creez d\'abord ce compte depuis Connexion > Creer un nouveau compte, puis revenez ici pour l\'ajouter.';
    }

    if (lower.contains('manager role required')) {
      return 'Seul un manager peut ajouter un utilisateur.';
    }

    if (lower.contains('company not found for current user')) {
      return 'Votre compte manager n\'est lie a aucune compagnie.';
    }

    return message.isNotEmpty
        ? message
        : 'Impossible d\'ajouter cet utilisateur.';
  }

  void clearRoleCache() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      _roleCache.clear();
      return;
    }
    _roleCache.remove(userId);
  }
}

class _RoleCache {
  final AppRole role;
  final DateTime expiresAt;

  const _RoleCache({required this.role, required this.expiresAt});
}
