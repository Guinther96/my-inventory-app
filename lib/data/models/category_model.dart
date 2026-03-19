class Category {
  final String id;
  final String name;
  final String? description;
  final String? parentId;
  final DateTime createdAt;

  Category({
    required this.id,
    required this.name,
    this.description,
    this.parentId,
    required this.createdAt,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] ?? json['createdAt'];

    return Category(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description'],
      parentId: json['parent_id']?.toString(),
      createdAt:
          DateTime.tryParse(createdAtRaw?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Category copyWith({
    String? id,
    String? name,
    String? description,
    String? parentId,
    DateTime? createdAt,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      parentId: parentId ?? this.parentId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'parent_id': parentId,
      // Suppress created_at for insert/update typically
    };
  }
}
