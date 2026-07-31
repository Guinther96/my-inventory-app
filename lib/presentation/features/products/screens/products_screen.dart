import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../core/utils/currency.dart';
import '../../../../data/models/product_model.dart';
import '../../../../data/models/product_variant.dart';
import '../../../../data/models/variant_attribute.dart';
import '../../../../data/providers/inventory_provider.dart';
import '../../../common_widgets/app_drawer.dart';
import '../../../common_widgets/app_sidebar.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  String _search = '';
  final ImagePicker _imagePicker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 950;
    final horizontalPadding = isDesktop ? 24.0 : 14.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: isDesktop ? null : AppBar(title: const Text('Produits')),
      drawer: isDesktop ? null : const AppDrawer(),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) const AppSidebar(),
          Expanded(
            child: Consumer<InventoryProvider>(
              builder: (context, inventory, _) {
                final dedupedProducts = _dedupeVisibleProducts(
                  inventory.products,
                );
                final filtered = dedupedProducts.where((p) {
                  final q = _search.toLowerCase();
                  return p.name.toLowerCase().contains(q) ||
                      (p.barcode?.toLowerCase().contains(q) ?? false);
                }).toList()..sort((a, b) => a.name.compareTo(b.name));

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    20,
                    horizontalPadding,
                    18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          Text(
                            'Catalogue produits',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          FilledButton.icon(
                            onPressed: () => _openProductDialog(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Nouveau'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow.withValues(alpha: 0.08),
                              blurRadius: 16,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(
                                  labelText: 'Rechercher un produit',
                                  prefixIcon: Icon(Icons.search),
                                  filled: true,
                                  fillColor: null,
                                  border: OutlineInputBorder(
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onChanged: (value) {
                                  setState(() => _search = value.trim());
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${filtered.length}',
                                style: TextStyle(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.shadow.withValues(
                                  alpha: 0.08,
                                ),
                                blurRadius: 18,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final product = filtered[index];
                              final categoryName =
                                  inventory
                                      .findCategoryById(
                                        product.categoryId ?? '',
                                      )
                                      ?.name ??
                                  'Sans categorie';

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                leading: _ProductImage(
                                  imageUrl: product.imageUrl,
                                ),
                                title: Text(product.name),
                                subtitle: Text(
                                  '$categoryName • Stock: ${product.quantityInStock} • Prix: ${formatMoney(product.price, product.currency)}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Modifier',
                                      icon: const Icon(Icons.edit),
                                      onPressed: () => _openProductDialog(
                                        context,
                                        product: product,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Supprimer',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        await inventory.deleteProduct(
                                          product.id,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Product> _dedupeVisibleProducts(List<Product> products) {
    final byKey = <String, Product>{};

    for (final product in products) {
      final barcode = (product.barcode ?? '').trim().toLowerCase();
      final category = (product.categoryId ?? '').trim().toLowerCase();
      final name = product.name.trim().toLowerCase();
      final key = barcode.isNotEmpty
          ? 'barcode:$barcode'
          : 'name:$name|category:$category';

      final existing = byKey[key];
      if (existing == null || product.updatedAt.isAfter(existing.updatedAt)) {
        byKey[key] = product;
      }
    }

    return byKey.values.toList();
  }

  Future<void> _openProductDialog(
    BuildContext context, {
    Product? product,
  }) async {
    final inventory = context.read<InventoryProvider>();

    final nameController = TextEditingController(text: product?.name ?? '');
    final barcodeController = TextEditingController(
      text: product?.barcode ?? '',
    );
    final descriptionController = TextEditingController(
      text: product?.description ?? '',
    );
    final imageUrlController = TextEditingController(
      text: product?.imageUrl ?? '',
    );
    final priceController = TextEditingController(
      text: product != null ? product.price.toStringAsFixed(2) : '0',
    );
    final quantityController = TextEditingController(
      text: product?.quantityInStock.toString() ?? '0',
    );
    final minAlertController = TextEditingController(
      text: product?.minStockAlert.toString() ?? '5',
    );

    String? selectedCategoryId = product?.categoryId;
    String selectedCurrency = normalizeCurrencyCode(product?.currency);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final mediaQuery = MediaQuery.of(context);
            final availableHeight =
                mediaQuery.size.height - mediaQuery.viewInsets.vertical - 48;
            final dialogMaxHeight = availableHeight < 320
                ? 320.0
                : availableHeight;

            return AnimatedPadding(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              padding: mediaQuery.viewInsets,
              child: Dialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 560,
                    maxHeight: dialogMaxHeight,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product == null
                              ? 'Nouveau produit'
                              : 'Modifier produit',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(labelText: 'Nom'),
                        ),
                        TextField(
                          controller: barcodeController,
                          decoration: const InputDecoration(
                            labelText: 'Code-barres',
                          ),
                        ),
                        TextField(
                          controller: descriptionController,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                          ),
                        ),
                        Row(
                          children: [
                            _DialogImagePreview(
                              imageUrl: imageUrlController.text,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final picked =
                                          await _pickImageAsDataUrl();
                                      if (!context.mounted || picked == null) {
                                        return;
                                      }
                                      setDialogState(() {
                                        imageUrlController.text = picked;
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.photo_library_outlined,
                                    ),
                                    label: const Text('Galerie'),
                                  ),
                                  if (imageUrlController.text.trim().isNotEmpty)
                                    TextButton.icon(
                                      onPressed: () {
                                        setDialogState(() {
                                          imageUrlController.clear();
                                        });
                                      },
                                      icon: const Icon(Icons.close),
                                      label: const Text('Retirer'),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        TextField(
                          controller: priceController,
                          decoration: const InputDecoration(labelText: 'Prix'),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: selectedCurrency,
                          decoration: const InputDecoration(
                            labelText: 'Type de devise',
                          ),
                          items: kSupportedCurrencies
                              .map(
                                (code) => DropdownMenuItem<String>(
                                  value: code,
                                  child: Text(AppCurrency.fromCode(code).label),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setDialogState(() => selectedCurrency = value);
                          },
                        ),
                        TextField(
                          controller: quantityController,
                          decoration: const InputDecoration(
                            labelText: 'Quantite en stock',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        TextField(
                          controller: minAlertController,
                          decoration: const InputDecoration(
                            labelText: 'Alerte stock minimum',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String?>(
                          value: selectedCategoryId,
                          decoration: const InputDecoration(
                            labelText: 'Categorie',
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Sans categorie'),
                            ),
                            ...inventory.categories.map(
                              (c) => DropdownMenuItem<String?>(
                                value: c.id,
                                child: Text(c.name),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setDialogState(() => selectedCategoryId = value);
                          },
                        ),
                        if (product != null) ...[
                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 8),
                          _VariantsSection(
                            productId: product.id,
                            currency: selectedCurrency,
                          ),
                        ],
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Annuler'),
                              ),
                              FilledButton(
                                onPressed: () async {
                                  final name = nameController.text.trim();
                                  if (name.isEmpty) {
                                    return;
                                  }

                                  final parsedPrice =
                                      double.tryParse(
                                        priceController.text.trim().replaceAll(
                                          ',',
                                          '.',
                                        ),
                                      ) ??
                                      0;
                                  final parsedQty =
                                      int.tryParse(
                                        quantityController.text.trim(),
                                      ) ??
                                      0;
                                  final parsedMin =
                                      int.tryParse(
                                        minAlertController.text.trim(),
                                      ) ??
                                      5;

                                  final now = DateTime.now();
                                  final productToSave = Product(
                                    id: product?.id ?? '',
                                    categoryId: selectedCategoryId,
                                    name: name,
                                    description:
                                        descriptionController.text
                                            .trim()
                                            .isEmpty
                                        ? null
                                        : descriptionController.text.trim(),
                                    barcode:
                                        barcodeController.text.trim().isEmpty
                                        ? null
                                        : barcodeController.text.trim(),
                                    imageUrl:
                                        imageUrlController.text.trim().isEmpty
                                        ? null
                                        : imageUrlController.text.trim(),
                                    price: parsedPrice,
                                    currency: selectedCurrency,
                                    quantityInStock: parsedQty,
                                    minStockAlert: parsedMin,
                                    createdAt: product?.createdAt ?? now,
                                    updatedAt: now,
                                  );

                                  try {
                                    await inventory.addOrUpdateProduct(
                                      productToSave,
                                    );
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      final rawMessage = e.toString();
                                      final message = rawMessage.replaceFirst(
                                        'Exception: ',
                                        '',
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text(message)),
                                      );
                                    }
                                  }
                                },
                                child: const Text('Enregistrer'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _pickImageAsDataUrl() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1280,
      );

      if (image == null) {
        return null;
      }

      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);
      final extension = image.path.split('.').last.toLowerCase();
      final mime = _mimeFromExtension(extension);
      return 'data:$mime;base64,$base64Image';
    } on PlatformException catch (e) {
      if (!mounted) {
        return null;
      }
      final details = (e.message ?? e.code).trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible d\'ouvrir la galerie ($details). Redemarrez completement l\'application et reessayez.',
          ),
        ),
      );
      return null;
    } catch (_) {
      if (!mounted) {
        return null;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la lecture de l\'image.')),
      );
      return null;
    }
  }

  String _mimeFromExtension(String extension) {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'image/png';
    }
  }
}

class _DialogImagePreview extends StatelessWidget {
  final String? imageUrl;

  const _DialogImagePreview({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: const Color(0xFFE8F2FF),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined, color: Color(0xFF0C7EA5)),
      );
    }

    if (url.startsWith('data:image/')) {
      final commaIndex = url.indexOf(',');
      if (commaIndex > 0 && commaIndex < url.length - 1) {
        try {
          final raw = url.substring(commaIndex + 1);
          final bytes = base64Decode(raw);
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              bytes,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
            ),
          );
        } catch (_) {
          // Falls back to placeholder below.
        }
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 72,
            height: 72,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined),
          );
        },
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  final String? imageUrl;

  const _ProductImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    if (url != null && url.startsWith('data:image/')) {
      final commaIndex = url.indexOf(',');
      if (commaIndex > 0 && commaIndex < url.length - 1) {
        try {
          final raw = url.substring(commaIndex + 1);
          final bytes = base64Decode(raw);
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              bytes,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
            ),
          );
        } catch (_) {
          // Falls through to placeholder.
        }
      }
    }

    final lowerUrl = url?.toLowerCase() ?? '';
    final uri = url == null ? null : Uri.tryParse(url);
    final hasSupportedExtension =
        lowerUrl.endsWith('.png') ||
        lowerUrl.endsWith('.jpg') ||
        lowerUrl.endsWith('.jpeg') ||
        lowerUrl.endsWith('.webp') ||
        lowerUrl.endsWith('.gif') ||
        lowerUrl.endsWith('.bmp');
    final isHttpImage =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        !lowerUrl.endsWith('.svg') &&
        hasSupportedExtension;

    if (url == null || url.isEmpty || !isHttpImage) {
      return const CircleAvatar(
        radius: 24,
        backgroundColor: Color(0xFFE8F2FF),
        child: Icon(Icons.image_outlined, color: Color(0xFF0C7EA5)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 52,
            height: 52,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined),
          );
        },
      ),
    );
  }
}

/// Section "Variantes" du dialogue produit: liste les variantes existantes
/// (options universelles: couleur/taille, barbier/duree, longueur/technique...)
/// et permet d'en ajouter/modifier/supprimer. Chaque variante porte son
/// propre stock et son propre prix, independamment du produit parent.
class _VariantsSection extends StatelessWidget {
  final String productId;
  final String currency;

  const _VariantsSection({required this.productId, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, inventory, _) {
        final variants = inventory.variantsForProduct(productId);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Variantes',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                TextButton.icon(
                  onPressed: () =>
                      _openVariantDialog(context, productId: productId),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ajouter'),
                ),
              ],
            ),
            if (variants.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Aucune variante: le produit se vend tel quel, avec le stock '
                  'ci-dessus. Ajoutez une variante pour des options comme '
                  'couleur/taille, barbier/duree, longueur/technique...',
                  style: TextStyle(color: Color(0xFF617287)),
                ),
              )
            else
              ...variants.map(
                (variant) => _VariantTile(
                  variant: variant,
                  currency: currency,
                  onEdit: () => _openVariantDialog(
                    context,
                    productId: productId,
                    variant: variant,
                  ),
                  onDelete: () =>
                      context.read<InventoryProvider>().deleteVariant(
                        variant.id,
                      ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _VariantTile extends StatelessWidget {
  final ProductVariant variant;
  final String currency;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _VariantTile({
    required this.variant,
    required this.currency,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final label = variant.attributes.isEmpty
        ? (variant.sku ?? 'Variante')
        : variant.attributesLabel;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  '${formatMoney(variant.price, currency)} • Stock: ${variant.stock}'
                  '${(variant.sku ?? '').isNotEmpty ? ' • SKU: ${variant.sku}' : ''}',
                  style: const TextStyle(color: Color(0xFF617287), fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Modifier',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: 'Supprimer',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _AttributeRow {
  final TextEditingController nameController;
  final TextEditingController valueController;

  _AttributeRow({String name = '', String value = ''})
    : nameController = TextEditingController(text: name),
      valueController = TextEditingController(text: value);

  void dispose() {
    nameController.dispose();
    valueController.dispose();
  }
}

Future<void> _openVariantDialog(
  BuildContext context, {
  required String productId,
  ProductVariant? variant,
}) async {
  final inventory = context.read<InventoryProvider>();

  final skuController = TextEditingController(text: variant?.sku ?? '');
  final barcodeController = TextEditingController(text: variant?.barcode ?? '');
  final imageUrlController = TextEditingController(text: variant?.imageUrl ?? '');
  final priceController = TextEditingController(
    text: variant != null ? variant.price.toStringAsFixed(2) : '0',
  );
  final stockController = TextEditingController(
    text: variant?.stock.toString() ?? '0',
  );

  final attributeRows = (variant != null && variant.attributes.isNotEmpty)
      ? variant.attributes
            .map(
              (attribute) => _AttributeRow(
                name: attribute.attributeName,
                value: attribute.attributeValue,
              ),
            )
            .toList()
      : <_AttributeRow>[_AttributeRow()];

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final mediaQuery = MediaQuery.of(dialogContext);
          final availableHeight =
              mediaQuery.size.height - mediaQuery.viewInsets.vertical - 48;
          final dialogMaxHeight = availableHeight < 320 ? 320.0 : availableHeight;

          return AnimatedPadding(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: mediaQuery.viewInsets,
            child: Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 480,
                  maxHeight: dialogMaxHeight,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        variant == null ? 'Nouvelle variante' : 'Modifier variante',
                        style: Theme.of(dialogContext).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Options (ex: Couleur -> Noir, Taille -> XL, Barbier -> '
                        'Jean, Duree -> 45 min...)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF617287),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < attributeRows.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: attributeRows[i].nameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Attribut',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: attributeRows[i].valueController,
                                  decoration: const InputDecoration(
                                    labelText: 'Valeur',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: attributeRows.length <= 1
                                    ? null
                                    : () {
                                        setDialogState(() {
                                          attributeRows[i].dispose();
                                          attributeRows.removeAt(i);
                                        });
                                      },
                              ),
                            ],
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            setDialogState(() => attributeRows.add(_AttributeRow()));
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Ajouter un attribut'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: skuController,
                        decoration: const InputDecoration(labelText: 'SKU'),
                      ),
                      TextField(
                        controller: barcodeController,
                        decoration: const InputDecoration(
                          labelText: 'Code-barres',
                        ),
                      ),
                      TextField(
                        controller: imageUrlController,
                        decoration: const InputDecoration(
                          labelText: 'URL image (optionnel)',
                        ),
                      ),
                      TextField(
                        controller: priceController,
                        decoration: const InputDecoration(labelText: 'Prix'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      TextField(
                        controller: stockController,
                        decoration: const InputDecoration(
                          labelText: 'Stock de cette variante',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('Annuler'),
                            ),
                            FilledButton(
                              onPressed: () async {
                                final parsedPrice =
                                    double.tryParse(
                                      priceController.text.trim().replaceAll(
                                        ',',
                                        '.',
                                      ),
                                    ) ??
                                    0;
                                final parsedStock =
                                    int.tryParse(stockController.text.trim()) ??
                                    0;

                                final attributes = attributeRows
                                    .where(
                                      (row) =>
                                          row.nameController.text
                                              .trim()
                                              .isNotEmpty &&
                                          row.valueController.text
                                              .trim()
                                              .isNotEmpty,
                                    )
                                    .map(
                                      (row) => VariantAttribute(
                                        id: '',
                                        variantId: variant?.id ?? '',
                                        attributeName:
                                            row.nameController.text.trim(),
                                        attributeValue:
                                            row.valueController.text.trim(),
                                      ),
                                    )
                                    .toList();

                                final variantToSave = ProductVariant(
                                  id: variant?.id ?? '',
                                  productId: productId,
                                  sku: skuController.text.trim().isEmpty
                                      ? null
                                      : skuController.text.trim(),
                                  barcode: barcodeController.text.trim().isEmpty
                                      ? null
                                      : barcodeController.text.trim(),
                                  price: parsedPrice,
                                  stock: parsedStock,
                                  imageUrl:
                                      imageUrlController.text.trim().isEmpty
                                      ? null
                                      : imageUrlController.text.trim(),
                                  createdAt: variant?.createdAt ?? DateTime.now(),
                                );

                                try {
                                  await inventory.addOrUpdateVariant(
                                    productId: productId,
                                    variant: variantToSave,
                                    attributes: attributes,
                                  );
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                } catch (e) {
                                  if (dialogContext.mounted) {
                                    final message = e.toString().replaceFirst(
                                      'Exception: ',
                                      '',
                                    );
                                    ScaffoldMessenger.of(
                                      dialogContext,
                                    ).showSnackBar(SnackBar(content: Text(message)));
                                  }
                                }
                              },
                              child: const Text('Enregistrer'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  for (final row in attributeRows) {
    row.dispose();
  }
  skuController.dispose();
  barcodeController.dispose();
  imageUrlController.dispose();
  priceController.dispose();
  stockController.dispose();
}
