import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/utils/currency.dart';
import '../../../../data/models/product_model.dart';
import '../../../../data/models/product_variant.dart';
import 'quantity_selector.dart';
import 'variant_selector.dart';

/// Fiche produit moderne (image, description, options, quantite) affichee
/// avant l'ajout au panier des qu'un produit a des variantes. Les produits
/// simples (sans variante) continuent d'etre ajoutes directement depuis la
/// grille, sans passer par cette fiche.
class ProductDetailSheet extends StatefulWidget {
  final Product product;
  final String categoryName;
  final List<ProductVariant> variants;
  final void Function(ProductVariant? variant, int quantity) onAddToCart;

  const ProductDetailSheet({
    super.key,
    required this.product,
    required this.categoryName,
    required this.variants,
    required this.onAddToCart,
  });

  static Future<void> show(
    BuildContext context, {
    required Product product,
    required String categoryName,
    required List<ProductVariant> variants,
    required void Function(ProductVariant? variant, int quantity) onAddToCart,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProductDetailSheet(
        product: product,
        categoryName: categoryName,
        variants: variants,
        onAddToCart: onAddToCart,
      ),
    );
  }

  @override
  State<ProductDetailSheet> createState() => _ProductDetailSheetState();
}

class _ProductDetailSheetState extends State<ProductDetailSheet> {
  final Map<String, String> _selectedAttributes = {};
  int _quantity = 1;
  int _galleryIndex = 0;

  bool get _hasVariants => widget.variants.isNotEmpty;

  List<String> get _attributeNames {
    final names = <String>[];
    for (final variant in widget.variants) {
      for (final attribute in variant.attributes) {
        if (!names.contains(attribute.attributeName)) {
          names.add(attribute.attributeName);
        }
      }
    }
    return names;
  }

  /// La variante correspondant exactement a la selection courante, ou null
  /// tant que toutes les options n'ont pas ete choisies (ou si la
  /// combinaison n'existe pas).
  ProductVariant? get _matchingVariant {
    if (!_hasVariants) {
      return null;
    }
    final names = _attributeNames;
    if (names.any((name) => !_selectedAttributes.containsKey(name))) {
      return null;
    }

    for (final variant in widget.variants) {
      final matches = names.every((name) {
        final attribute = variant.attributes
            .where((a) => a.attributeName == name)
            .firstOrNull;
        return attribute?.attributeValue == _selectedAttributes[name];
      });
      if (matches) {
        return variant;
      }
    }
    return null;
  }

  int get _availableStock {
    if (!_hasVariants) {
      return widget.product.quantityInStock;
    }
    return _matchingVariant?.stock ?? 0;
  }

  double get _displayPrice => _matchingVariant?.price ?? widget.product.price;

  List<String> get _galleryImages {
    final images = <String>[];
    final productImage = widget.product.imageUrl?.trim();
    if (productImage != null && productImage.isNotEmpty) {
      images.add(productImage);
    }
    for (final variant in widget.variants) {
      final url = variant.imageUrl?.trim();
      if (url != null && url.isNotEmpty && !images.contains(url)) {
        images.add(url);
      }
    }
    return images;
  }

  void _onAttributeSelected(String attributeName, String value) {
    setState(() {
      _selectedAttributes[attributeName] = value;
      _quantity = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.9;
    final canAdd = _hasVariants
        ? (_matchingVariant != null && _availableStock > 0)
        : widget.product.quantityInStock > 0;
    final images = _galleryImages;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    children: [
                      _ProductGallery(
                        images: images,
                        selectedIndex: _galleryIndex,
                        onSelected: (index) =>
                            setState(() => _galleryIndex = index),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.product.name,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.primaryColor.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    widget.categoryName,
                                    style: TextStyle(
                                      color: theme.primaryColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            formatMoney(_displayPrice, widget.product.currency),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _StockBadge(available: _availableStock),
                      if ((widget.product.description ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          widget.product.description!.trim(),
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color
                                ?.withValues(alpha: 0.75),
                            height: 1.5,
                          ),
                        ),
                      ],
                      if (_hasVariants) ...[
                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 12),
                        VariantSelector(
                          variants: widget.variants,
                          selectedAttributes: _selectedAttributes,
                          onAttributeSelected: _onAttributeSelected,
                        ),
                        if (_attributeNames.every(
                              _selectedAttributes.containsKey,
                            ) &&
                            _matchingVariant == null)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Cette combinaison n est pas disponible.',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
                      ],
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Quantite',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          QuantitySelector(
                            quantity: _quantity,
                            maxQuantity: _availableStock <= 0
                                ? 1
                                : _availableStock,
                            onChanged: (value) =>
                                setState(() => _quantity = value),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: canAdd
                            ? () {
                                Navigator.pop(context);
                                widget.onAddToCart(_matchingVariant, _quantity);
                              }
                            : null,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        icon: const Icon(Icons.add_shopping_cart),
                        label: Text(
                          canAdd
                              ? 'Ajouter au panier'
                              : 'Indisponible',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _StockBadge extends StatelessWidget {
  final int available;

  const _StockBadge({required this.available});

  @override
  Widget build(BuildContext context) {
    final isOut = available <= 0;
    final color = isOut ? Colors.redAccent : Colors.green;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 6),
        Text(
          isOut ? 'Rupture de stock' : '$available en stock',
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _ProductGallery extends StatelessWidget {
  final List<String> images;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _ProductGallery({
    required this.images,
    required this.selectedIndex,
    required this.onSelected,
  });

  Widget _image(String url, {required double size}) {
    if (url.startsWith('data:image/')) {
      final commaIndex = url.indexOf(',');
      if (commaIndex > 0 && commaIndex < url.length - 1) {
        try {
          final bytes = base64Decode(url.substring(commaIndex + 1));
          return Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
          );
        } catch (_) {
          // Retombe sur le placeholder ci-dessous.
        }
      }
    }
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          _placeholder(size: size),
    );
  }

  Widget _placeholder({required double size}) {
    return Container(
      width: size,
      height: size,
      color: const Color(0xFFE8F2FF),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        color: const Color(0xFF0C7EA5),
        size: size * 0.35,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mainUrl = images.isEmpty
        ? null
        : images[selectedIndex.clamp(0, images.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            width: double.infinity,
            height: 220,
            child: mainUrl == null
                ? _placeholder(size: 220)
                : _image(mainUrl, size: 220),
          ),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final selected = index == selectedIndex;
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onSelected(index),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).primaryColor
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _image(images[index], size: 60),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
