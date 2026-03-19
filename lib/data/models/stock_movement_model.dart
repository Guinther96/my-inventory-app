class StockMovement {
  final String id;
  final String productId;
  final String? userId; // Optional for when no user context is loaded
  final String? sellerId;
  final String movementType; // 'entry', 'exit', 'adjustment'
  final int quantity;
  final String? notes;
  final DateTime createdAt;

  StockMovement({
    required this.id,
    required this.productId,
    this.userId,
    this.sellerId,
    required this.movementType,
    required this.quantity,
    this.notes,
    required this.createdAt,
  });

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] ?? json['createdAt'];

    return StockMovement(
      id: json['id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      userId: json['user_id'],
      sellerId: json['seller_id']?.toString(),
      movementType:
          (json['movement_type'] ?? json['type'])?.toString() ?? 'entry',
      quantity: (json['quantity'] as num? ?? 0).toInt(),
      notes: json['notes'],
      createdAt:
          DateTime.tryParse(createdAtRaw?.toString() ?? '') ?? DateTime.now(),
    );
  }

  StockMovement copyWith({
    String? id,
    String? productId,
    String? userId,
    String? sellerId,
    String? movementType,
    int? quantity,
    String? notes,
    DateTime? createdAt,
  }) {
    return StockMovement(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      userId: userId ?? this.userId,
      sellerId: sellerId ?? this.sellerId,
      movementType: movementType ?? this.movementType,
      quantity: quantity ?? this.quantity,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      if (userId != null) 'user_id': userId,
      if (sellerId != null) 'seller_id': sellerId,
      'type': movementType,
      'quantity': quantity,
      if (notes != null) 'notes': notes,
    };
  }
}
