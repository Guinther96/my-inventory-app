import '../../core/utils/currency.dart';

class Service {
  final String id;
  final String companyId;
  final String name;
  final String? description;
  final double price;
  final String currency;
  final int? durationMinutes;
  final String? createdBy;
  final bool isActive;
  final String? categoryId;
  final String? imageUrl;

  /// Prestataire suggere par defaut pour ce service. Simple pre-remplissage
  /// pratique: l'assignation qui fait autorite reste celle choisie a la
  /// ligne de commande (service_order_items), pas celle-ci.
  final String? defaultProviderId;

  /// Commission indicative associee au service (non branchee dans le calcul
  /// des gains prestataire, qui reste base sur l'assignation par commande).
  final String? commissionType;
  final double? commissionValue;

  final DateTime createdAt;
  final DateTime updatedAt;

  Service({
    required this.id,
    required this.companyId,
    required this.name,
    this.description,
    required this.price,
    this.currency = 'HTG',
    this.durationMinutes,
    this.createdBy,
    required this.isActive,
    this.categoryId,
    this.imageUrl,
    this.defaultProviderId,
    this.commissionType,
    this.commissionValue,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Service.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] ?? json['createdAt'];
    final updatedAtRaw = json['updated_at'] ?? json['updatedAt'];

    return Service(
      id: json['id']?.toString() ?? '',
      companyId: json['company_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      price:
          double.tryParse(
            (json['price'] ?? json['base_price'])?.toString() ?? '',
          ) ??
          0,
      currency: normalizeCurrencyCode(json['currency']?.toString()),
      durationMinutes: int.tryParse(json['duration_minutes']?.toString() ?? ''),
      createdBy: json['created_by']?.toString(),
      isActive: json['is_active'] == null ? true : json['is_active'] == true,
      categoryId: json['category_id']?.toString(),
      imageUrl: json['image_url']?.toString(),
      defaultProviderId: json['default_provider_id']?.toString(),
      commissionType: json['commission_type']?.toString(),
      commissionValue: double.tryParse(
        json['commission_value']?.toString() ?? '',
      ),
      createdAt:
          DateTime.tryParse(createdAtRaw?.toString() ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(updatedAtRaw?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Service copyWith({
    String? id,
    String? companyId,
    String? name,
    String? description,
    double? price,
    String? currency,
    int? durationMinutes,
    String? createdBy,
    bool? isActive,
    String? categoryId,
    String? imageUrl,
    String? defaultProviderId,
    String? commissionType,
    double? commissionValue,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Service(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      createdBy: createdBy ?? this.createdBy,
      isActive: isActive ?? this.isActive,
      categoryId: categoryId ?? this.categoryId,
      imageUrl: imageUrl ?? this.imageUrl,
      defaultProviderId: defaultProviderId ?? this.defaultProviderId,
      commissionType: commissionType ?? this.commissionType,
      commissionValue: commissionValue ?? this.commissionValue,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'company_id': companyId,
      'name': name,
      'description': description,
      'price': price,
      'currency': currency,
      'duration_minutes': durationMinutes,
      'created_by': createdBy,
      'is_active': isActive,
      'category_id': categoryId,
      'image_url': imageUrl,
      'default_provider_id': defaultProviderId,
      'commission_type': commissionType,
      'commission_value': commissionValue,
    };
  }
}
