class Service {
  final String id;
  final String companyId;
  final String name;
  final String? description;
  final double price;
  final int? durationMinutes;
  final String? createdBy;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Service({
    required this.id,
    required this.companyId,
    required this.name,
    this.description,
    required this.price,
    this.durationMinutes,
    this.createdBy,
    required this.isActive,
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
      durationMinutes: int.tryParse(json['duration_minutes']?.toString() ?? ''),
      createdBy: json['created_by']?.toString(),
      isActive: json['is_active'] == null ? true : json['is_active'] == true,
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
    int? durationMinutes,
    String? createdBy,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Service(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      createdBy: createdBy ?? this.createdBy,
      isActive: isActive ?? this.isActive,
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
      'duration_minutes': durationMinutes,
      'created_by': createdBy,
      'is_active': isActive,
    };
  }
}
