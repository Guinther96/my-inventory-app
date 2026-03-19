class Product {
  final String id;
  final String? categoryId;
  final String name;
  final String? description;
  final String? barcode;
  final double price;
  final int quantityInStock;
  final int minStockAlert;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  Product({
    required this.id,
    this.categoryId,
    required this.name,
    this.description,
    this.barcode,
    required this.price,
    required this.quantityInStock,
    this.minStockAlert = 5,
    this.imageUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] ?? json['createdAt'];
    final updatedAtRaw = json['updated_at'] ?? json['updatedAt'];
    final quantityRaw = json['quantity_in_stock'] ?? json['quantity'];
    final minStockRaw = json['min_stock_alert'] ?? json['min_stock'];
    final quantity = int.tryParse(quantityRaw?.toString() ?? '') ?? 0;
    final minStock = int.tryParse(minStockRaw?.toString() ?? '') ?? 5;

    return Product(
      id: json['id']?.toString() ?? '',
      categoryId: json['category_id'],
      name: json['name']?.toString() ?? '',
      description: json['description'],
      barcode: json['barcode'],
      price: json['price'] != null
          ? double.parse(json['price'].toString())
          : 0.0,
      quantityInStock: quantity,
      minStockAlert: minStock,
      imageUrl: json['images_url'] ?? json['image_url'],
      createdAt:
          DateTime.tryParse(createdAtRaw?.toString() ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(updatedAtRaw?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Product copyWith({
    String? id,
    String? categoryId,
    String? name,
    String? description,
    String? barcode,
    double? price,
    int? quantityInStock,
    int? minStockAlert,
    String? imageUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      description: description ?? this.description,
      barcode: barcode ?? this.barcode,
      price: price ?? this.price,
      quantityInStock: quantityInStock ?? this.quantityInStock,
      minStockAlert: minStockAlert ?? this.minStockAlert,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      if (categoryId != null) 'category_id': categoryId,
      'name': name,
      if (description != null) 'description': description,
      if (barcode != null) 'barcode': barcode,
      'price': price,
      'quantity': quantityInStock,
      'min_stock': minStockAlert,
      if (imageUrl != null) 'images_url': imageUrl,
    };
  }
}
