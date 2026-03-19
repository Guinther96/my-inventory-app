enum AppRole { manager, seller }

class UserProfile {
  final String id;
  final String email;
  final String companyId;
  final AppRole role;

  const UserProfile({
    required this.id,
    required this.email,
    required this.companyId,
    required this.role,
  });

  bool get isManager => role == AppRole.manager;
  bool get isSeller => role == AppRole.seller;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final rawRole = (json['role'] ?? '').toString().toLowerCase();

    return UserProfile(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      companyId: json['company_id']?.toString() ?? '',
      role: rawRole == 'manager' ? AppRole.manager : AppRole.seller,
    );
  }
}
