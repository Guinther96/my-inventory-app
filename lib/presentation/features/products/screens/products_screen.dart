import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../data/models/product_model.dart';
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
                final filtered = inventory.products.where((p) {
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
                                  '$categoryName • Stock: ${product.quantityInStock} • Prix: ${product.price.toStringAsFixed(2)} Gdes',
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
                          decoration: const InputDecoration(
                            labelText: 'Prix (Gdes)',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
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
