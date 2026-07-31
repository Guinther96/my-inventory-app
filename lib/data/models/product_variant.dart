import 'variant_attribute.dart';

/// Une combinaison vendable d'un produit (ex: Pantalon Cargo / Noir / XL).
/// Porte son propre stock et son propre prix, independamment du produit
/// parent, pour permettre un suivi precis quel que soit le type de commerce
/// (boutique, barbershop, studio de beaute...).
class ProductVariant {
  final String id;
  final String productId;
  final String? sku;
  final String? barcode;
  final double price;
  final int stock;
  final String? imageUrl;
  final DateTime createdAt;
  final List<VariantAttribute> attributes;

  ProductVariant({
    required this.id,
    required this.productId,
    this.sku,
    this.barcode,
    required this.price,
    required this.stock,
    this.imageUrl,
    required this.createdAt,
    this.attributes = const <VariantAttribute>[],
  });

  /// Libelle lisible des attributs, ex: "Couleur: Noir, Taille: XL".
  String get attributesLabel =>
      attributes.map((a) => '${a.attributeName}: ${a.attributeValue}').join(', ');

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] ?? json['createdAt'];
    final rawAttributes = json['attributes'] ?? json['variant_attributes'];

    return ProductVariant(
      id: json['id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      sku: json['sku']?.toString(),
      barcode: json['barcode']?.toString(),
      price: json['price'] != null
          ? double.tryParse(json['price'].toString()) ?? 0
          : 0,
      stock: int.tryParse(json['stock']?.toString() ?? '') ?? 0,
      imageUrl: json['image_url']?.toString(),
      createdAt:
          DateTime.tryParse(createdAtRaw?.toString() ?? '') ?? DateTime.now(),
      attributes: rawAttributes is List
          ? rawAttributes
              .map(
                (a) => VariantAttribute.fromJson(
                  Map<String, dynamic>.from(a as Map),
                ),
              )
              .toList()
          : const <VariantAttribute>[],
    );
  }

  ProductVariant copyWith({
    String? id,
    String? productId,
    String? sku,
    String? barcode,
    double? price,
    int? stock,
    String? imageUrl,
    DateTime? createdAt,
    List<VariantAttribute>? attributes,
  }) {
    return ProductVariant(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      attributes: attributes ?? this.attributes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'product_id': productId,
      if (sku != null) 'sku': sku,
      if (barcode != null) 'barcode': barcode,
      'price': price,
      'stock': stock,
      if (imageUrl != null) 'image_url': imageUrl,
    };
  }
}
