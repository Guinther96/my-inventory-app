import 'package:flutter/material.dart';

import '../../../../data/models/product_variant.dart';

/// Selecteur d'options universel: n'importe quel ensemble d'attributs
/// dynamiques (Couleur/Taille pour une boutique, Barbier/Duree pour un
/// barbershop, Longueur/Technique pour un studio de beaute...). Une section
/// est generee par nom d'attribut distinct trouve parmi les variantes du
/// produit, aucun champ n'est code en dur.
class VariantSelector extends StatelessWidget {
  final List<ProductVariant> variants;
  final Map<String, String> selectedAttributes;
  final void Function(String attributeName, String value) onAttributeSelected;

  const VariantSelector({
    super.key,
    required this.variants,
    required this.selectedAttributes,
    required this.onAttributeSelected,
  });

  /// Noms d'attributs distincts, dans l'ordre de premiere apparition.
  List<String> get _attributeNames {
    final names = <String>[];
    for (final variant in variants) {
      for (final attribute in variant.attributes) {
        if (!names.contains(attribute.attributeName)) {
          names.add(attribute.attributeName);
        }
      }
    }
    return names;
  }

  /// Valeurs distinctes disponibles pour un nom d'attribut donne, dans
  /// l'ordre de premiere apparition.
  List<String> _valuesFor(String attributeName) {
    final values = <String>[];
    for (final variant in variants) {
      for (final attribute in variant.attributes) {
        if (attribute.attributeName == attributeName &&
            !values.contains(attribute.attributeValue)) {
          values.add(attribute.attributeValue);
        }
      }
    }
    return values;
  }

  @override
  Widget build(BuildContext context) {
    final attributeNames = _attributeNames;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final attributeName in attributeNames) ...[
          Text(
            attributeName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in _valuesFor(attributeName))
                ChoiceChip(
                  label: Text(value),
                  selected: selectedAttributes[attributeName] == value,
                  onSelected: (_) => onAttributeSelected(attributeName, value),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}
