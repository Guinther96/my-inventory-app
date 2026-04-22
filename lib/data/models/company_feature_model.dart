class CompanyFeature {
  final String id;
  final String companyId;
  final String featureKey;
  final bool enabled;
  final DateTime? updatedAt;

  const CompanyFeature({
    required this.id,
    required this.companyId,
    required this.featureKey,
    required this.enabled,
    this.updatedAt,
  });

  String get normalizedFeatureKey => featureKey.trim().toLowerCase();

  factory CompanyFeature.fromJson(Map<String, dynamic> json) {
    return CompanyFeature(
      id: json['id']?.toString() ?? '',
      companyId: json['company_id']?.toString() ?? '',
      featureKey: json['feature_key']?.toString() ?? '',
      enabled: json['enabled'] == true,
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }
}
