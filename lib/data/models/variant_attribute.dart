/// Attribut d'une variante (ex: "Couleur" -> "Noir", "Taille" -> "XL").
/// Le nom de l'attribut est libre: aucun champ metier n'est code en dur,
/// ce qui permet de couvrir vetements, services de barbershop, ongles, etc.
class VariantAttribute {
  final String id;
  final String variantId;
  final String attributeName;
  final String attributeValue;

  VariantAttribute({
    required this.id,
    required this.variantId,
    required this.attributeName,
    required this.attributeValue,
  });

  factory VariantAttribute.fromJson(Map<String, dynamic> json) {
    return VariantAttribute(
      id: json['id']?.toString() ?? '',
      variantId: json['variant_id']?.toString() ?? '',
      attributeName: json['attribute_name']?.toString() ?? '',
      attributeValue: json['attribute_value']?.toString() ?? '',
    );
  }

  VariantAttribute copyWith({
    String? id,
    String? variantId,
    String? attributeName,
    String? attributeValue,
  }) {
    return VariantAttribute(
      id: id ?? this.id,
      variantId: variantId ?? this.variantId,
      attributeName: attributeName ?? this.attributeName,
      attributeValue: attributeValue ?? this.attributeValue,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'variant_id': variantId,
      'attribute_name': attributeName,
      'attribute_value': attributeValue,
    };
  }
}
