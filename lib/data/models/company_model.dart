enum CompanyStatus { active, suspended }

class Company {
  final String id;
  final CompanyStatus status;
  final DateTime? updatedAt;

  const Company({required this.id, required this.status, this.updatedAt});

  bool get isSuspended => status == CompanyStatus.suspended;
  bool get isActive => status == CompanyStatus.active;

  static CompanyStatus normalizeStatus(String? rawStatus) {
    final normalized = (rawStatus ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'actif':
      case 'active':
        return CompanyStatus.active;
      case 'suspendu':
      case 'suspended':
        return CompanyStatus.suspended;
      default:
        return CompanyStatus.suspended;
    }
  }

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['id']?.toString() ?? '',
      status: normalizeStatus(json['status']?.toString()),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }
}
