import 'dart:convert';

// Imports des packages Flutter et providers
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Imports des modèles de données
import '../../../../data/models/category_model.dart';
import '../../../../data/models/product_model.dart';
import '../../../../data/models/stock_movement_model.dart';

// Imports du provider de gestion d'inventaire
import '../../../../data/providers/inventory_provider.dart';

// Imports des widgets communs (barre latérale, drawer)
import '../../../common_widgets/app_drawer.dart';
import '../../../common_widgets/app_sidebar.dart';

/// Écran principal de vente - Mode Caisse
///
/// Cet écran affiche une interface de point de vente (POS) complète avec:
/// - Un panier d'achat (ticket) à gauche
/// - Un catalogue de produits à droite
/// - Filtrage par catégorie et recherche
/// - Management des quantités en temps réel
/// - Encaissement final au moment de la validation
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

/// État du widget SalesScreen - Gère toute la logique de la vente
class _SalesScreenState extends State<SalesScreen> {
  /// Contrôleur pour la note/commentaire du ticket
  final TextEditingController _notesController = TextEditingController();

  /// Dictionnaire stockant les lignes du panier (productId -> CartLine)
  /// Permet une gestion rapide des articles du panier
  final Map<String, _CartLine> _cartLines = <String, _CartLine>{};

  /// Requête de recherche pour filtrer les produits
  String _searchQuery = '';

  /// ID de la catégorie sélectionnée pour le filtrage
  String? _selectedCategoryId;

  /// ID de la catégorie parent sélectionnée pour afficher ses sous-catégories
  String? _selectedParentCategoryId;

  /// ID du produit actuellement sélectionné dans le panier
  String? _selectedCartProductId;

  /// Flag pour savoir si l'opération d'encaissement est en cours
  bool _isSubmitting = false;

  /// Nettoie les ressources quand le widget est détruit
  /// Dispose le contrôleur de texte pour éviter les fuites mémoire
  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  /// Construit l'interface utilisateur principale du mode caisse
  /// Adapte l'affichage selon la taille de l'écran (desktop/tablette/mobile)
  @override
  Widget build(BuildContext context) {
    // Récupère la largeur de l'écran pour l'adaptativité
    final screenWidth = MediaQuery.of(context).size.width;
    // Détermine si c'est un écran desktop (>= 1120px)
    final isDesktop = screenWidth >= 1120;
    // Détermine si c'est une tablette (>= 760px)
    final isTablet = screenWidth >= 760;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      // Affiche la barre d'app uniquement sur mobile
      appBar: isDesktop ? null : AppBar(title: const Text('Caisse')),
      // Affiche le drawer (menu latéral) uniquement sur mobile
      drawer: isDesktop ? null : const AppDrawer(),
      // Couleur de fond légère pour l'interface POS
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Affiche la barre latérale seulement sur desktop
          if (isDesktop) const AppSidebar(),
          // Contenu principal qui s'adapte à l'espace disponible
          Expanded(
            child: Consumer<InventoryProvider>(
              // Écoute les changements du provider d'inventaire
              builder: (context, inventory, _) {
                // Déduplique les produits pour éviter les doublons visuels en caisse
                // si des lignes identiques existent temporairement en base.
                final allProducts = _dedupeCatalogProducts(inventory.products)
                  ..sort((a, b) => a.name.compareTo(b.name));
                // Récupère et trie toutes les catégories par nom
                final categories = [...inventory.categories]
                  ..sort((a, b) => a.name.compareTo(b.name));
                // Filtre les produits selon la recherche et la catégorie sélectionnée
                final filteredProducts = _filterProducts(
                  allProducts,
                  categories,
                );
                // Récupère les ventes d'aujourd'hui
                final todaySales = _todaySales(inventory.movements);
                // Récupère les 8 dernières ventes
                final recentSales = _recentSales(inventory.movements);
                // Convertit les lignes du panier en objets CartEntryData avec produits
                final cartEntries = _resolveCartEntries(inventory);
                // Récupère l'entrée panier actuellement sélectionnée
                final selectedCartEntry = _selectedCartEntry(cartEntries);
                // Calcule le nombre total d'articles dans le panier
                final totalItems = cartEntries.fold<int>(
                  0,
                  (sum, entry) => sum + entry.quantity,
                );
                // Calcule le montant total du panier
                final cartTotal = cartEntries.fold<double>(
                  0,
                  (sum, entry) => sum + entry.lineTotal,
                );
                // Calcule le chiffre d'affaires du jour
                final todayRevenue = todaySales.fold<double>(0, (sum, sale) {
                  final product = inventory.findProductById(sale.productId);
                  return sum + ((product?.price ?? 0) * sale.quantity);
                });

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    isDesktop ? 20 : 12,
                    16,
                    isDesktop ? 20 : 12,
                    16,
                  ),
                  child: isDesktop
                      ? Column(
                          children: [
                            _PosHeader(
                              todaySalesCount: todaySales.length,
                              totalItems: totalItems,
                              todayRevenue: todayRevenue,
                              cartTotal: cartTotal,
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 360,
                                    child: _TicketPanel(
                                      entries: cartEntries,
                                      selectedProductId: _selectedCartProductId,
                                      selectedEntry: selectedCartEntry,
                                      notesController: _notesController,
                                      totalItems: totalItems,
                                      cartTotal: cartTotal,
                                      isSubmitting: _isSubmitting,
                                      onSelectEntry: _selectCartProduct,
                                      onIncrement: (product) =>
                                          _changeQuantity(product, 1),
                                      onDecrement: (product) =>
                                          _changeQuantity(product, -1),
                                      onRemove: _removeFromCart,
                                      onQuickAdd: (value) =>
                                          _applyQuickQuantity(value, inventory),
                                      onClear:
                                          _cartLines.isEmpty || _isSubmitting
                                          ? null
                                          : _clearCart,
                                      onCheckout:
                                          _cartLines.isEmpty || _isSubmitting
                                          ? null
                                          : () => _checkoutCart(
                                              context,
                                              inventory,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _CatalogPanel(
                                      isTablet: isTablet,
                                      products: filteredProducts,
                                      categories: categories,
                                      selectedCategoryId: _selectedCategoryId,
                                      selectedParentCategoryId:
                                          _selectedParentCategoryId,
                                      searchQuery: _searchQuery,
                                      recentSales: recentSales,
                                      inventory: inventory,
                                      onSearchChanged: (value) {
                                        setState(
                                          () => _searchQuery = value.trim(),
                                        );
                                      },
                                      onParentCategorySelected:
                                          (parentCategoryId) {
                                            setState(() {
                                              _selectedParentCategoryId =
                                                  parentCategoryId;
                                              _selectedCategoryId = null;
                                            });
                                          },
                                      onCategorySelected: (categoryId) {
                                        setState(
                                          () =>
                                              _selectedCategoryId = categoryId,
                                        );
                                      },
                                      onAddToCart: _addProductToCart,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : SingleChildScrollView(
                          child: Column(
                            children: [
                              _PosHeader(
                                todaySalesCount: todaySales.length,
                                totalItems: totalItems,
                                todayRevenue: todayRevenue,
                                cartTotal: cartTotal,
                              ),
                              const SizedBox(height: 12),
                              _TicketPanel(
                                entries: cartEntries,
                                selectedProductId: _selectedCartProductId,
                                selectedEntry: selectedCartEntry,
                                notesController: _notesController,
                                totalItems: totalItems,
                                cartTotal: cartTotal,
                                isSubmitting: _isSubmitting,
                                compact: true,
                                onSelectEntry: _selectCartProduct,
                                onIncrement: (product) =>
                                    _changeQuantity(product, 1),
                                onDecrement: (product) =>
                                    _changeQuantity(product, -1),
                                onRemove: _removeFromCart,
                                onQuickAdd: (value) =>
                                    _applyQuickQuantity(value, inventory),
                                onClear: _cartLines.isEmpty || _isSubmitting
                                    ? null
                                    : _clearCart,
                                onCheckout: _cartLines.isEmpty || _isSubmitting
                                    ? null
                                    : () => _checkoutCart(context, inventory),
                              ),
                              const SizedBox(height: 12),
                              _CatalogPanel(
                                isTablet: isTablet,
                                products: filteredProducts,
                                categories: categories,
                                selectedCategoryId: _selectedCategoryId,
                                selectedParentCategoryId:
                                    _selectedParentCategoryId,
                                searchQuery: _searchQuery,
                                recentSales: recentSales,
                                inventory: inventory,
                                compact: true,
                                onSearchChanged: (value) {
                                  setState(() => _searchQuery = value.trim());
                                },
                                onParentCategorySelected: (parentCategoryId) {
                                  setState(() {
                                    _selectedParentCategoryId =
                                        parentCategoryId;
                                    _selectedCategoryId = null;
                                  });
                                },
                                onCategorySelected: (categoryId) {
                                  setState(
                                    () => _selectedCategoryId = categoryId,
                                  );
                                },
                                onAddToCart: _addProductToCart,
                              ),
                            ],
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Filtre la liste des produits selon la requête de recherche et la catégorie sélectionnée
  /// Retourne une liste des produits qui correspondent aux critères de recherche
  List<Product> _filterProducts(
    List<Product> products,
    List<Category> categories,
  ) {
    final descendantsByParent = <String, List<String>>{};
    for (final category in categories) {
      final parentId = category.parentId;
      if (parentId == null || parentId.isEmpty) {
        continue;
      }
      descendantsByParent
          .putIfAbsent(parentId, () => <String>[])
          .add(category.id);
    }

    Set<String> collectScope(String parentId) {
      final collected = <String>{parentId};
      final queue = <String>[parentId];

      while (queue.isNotEmpty) {
        final current = queue.removeLast();
        final children = descendantsByParent[current] ?? const <String>[];
        for (final child in children) {
          if (collected.add(child)) {
            queue.add(child);
          }
        }
      }

      return collected;
    }

    final activeParentScope = _selectedParentCategoryId == null
        ? const <String>{}
        : collectScope(_selectedParentCategoryId!);

    return products.where((product) {
      // Convertit la requête en minuscules pour comparaison insensible à la casse
      final query = _searchQuery.toLowerCase();
      // Vérifie si la catégorie du produit correspond à la catégorie sélectionnée
      // (ou si aucune catégorie n'est sélectionnée, tous les produits passent ce filtre)
      final categoryMatches = _selectedCategoryId != null
          ? product.categoryId == _selectedCategoryId
          : _selectedParentCategoryId != null
          ? activeParentScope.contains(product.categoryId)
          : true;
      // Vérifie si le produit correspond à la requête de recherche
      // Recherche dans le nom, le code-barres et la description
      final queryMatches =
          query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          (product.barcode?.toLowerCase().contains(query) ?? false) ||
          (product.description?.toLowerCase().contains(query) ?? false);

      // Le produit passe le filtre s'il satisfait les deux conditions
      return categoryMatches && queryMatches;
    }).toList();
  }

  List<Product> _dedupeCatalogProducts(List<Product> products) {
    final byKey = <String, Product>{};

    for (final product in products) {
      final barcode = (product.barcode ?? '').trim().toLowerCase();
      final categoryKey = (product.categoryId ?? '').trim().toLowerCase();
      final name = product.name.trim().toLowerCase();
      final key = barcode.isNotEmpty
          ? 'barcode:$barcode'
          : 'name:$name|category:$categoryKey';

      final existing = byKey[key];
      if (existing == null || product.updatedAt.isAfter(existing.updatedAt)) {
        byKey[key] = product;
      }
    }

    return byKey.values.toList();
  }

  /// Convertit les lignes du panier en objets CartEntryData avec les données de produit
  /// Cela facilite l'affichage et la manipulation des articles du panier
  List<_CartEntryData> _resolveCartEntries(InventoryProvider inventory) {
    final entries = <_CartEntryData>[];

    // Boucle sur chaque ligne du panier stockée en mémoire
    for (final line in _cartLines.values) {
      // Récupère le produit correspondant à partir du provider
      final product = inventory.findProductById(line.productId);
      // Ignore les produits qui n'existent plus (supprimés entre-temps)
      if (product == null) {
        continue;
      }

      // Crée un objet CartEntryData contenant le produit et sa quantité
      entries.add(_CartEntryData(product: product, quantity: line.quantity));
    }

    // Trie les entrées par nom de produit pour un affichage cohérent
    entries.sort((a, b) => a.product.name.compareTo(b.product.name));
    return entries;
  }

  /// Récupère l'entrée du panier actuellement sélectionnée
  /// Si aucune n'est sélectionnée, sélectionne la première ou retourne null
  _CartEntryData? _selectedCartEntry(List<_CartEntryData> entries) {
    // Si le panier est vide, réinitialise la sélection
    if (entries.isEmpty) {
      _selectedCartProductId = null;
      return null;
    }

    // Cherche l'entrée correspondant au produit sélectionné
    for (final entry in entries) {
      if (entry.product.id == _selectedCartProductId) {
        return entry;
      }
    }

    // Si la sélection n'est pas trouvée, sélectionne la première entrée
    _selectedCartProductId = entries.first.product.id;
    return entries.first;
  }

  /// Récupère les ventes d'aujourd'hui en filtrant les mouvements de stock
  /// Retourne uniquement les sorties (exit) de la journée du jour
  List<StockMovement> _todaySales(List<StockMovement> movements) {
    // Récupère la date actuelle
    final now = DateTime.now();

    // Filtre les mouvements pour garder uniquement ceux qui sont:
    // 1. Des sorties (type 'exit')
    // 2. De la même date que aujourd'hui
    return movements.where((movement) {
      return movement.movementType == 'exit' &&
          movement.createdAt.year == now.year &&
          movement.createdAt.month == now.month &&
          movement.createdAt.day == now.day;
    }).toList();
  }

  /// Récupère les 8 dernières ventes pour l'affichage historique
  List<StockMovement> _recentSales(List<StockMovement> movements) {
    // Filtre les sorties (ventes) et les trie par date décroissante
    final sales =
        movements.where((movement) => movement.movementType == 'exit').toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    // Retourne seulement les 8 dernières
    return sales.take(8).toList();
  }

  /// Ajoute un produit au panier ou incrémente sa quantité s'il y existe déjà
  /// Valide que le produit a du stock disponible avant d'ajouter
  /// Sélectionne automatiquement le produit après ajout
  void _addProductToCart(Product product) {
    // Refuse l'ajout si le produit n'a pas de stock disponible
    if (product.quantityInStock <= 0) {
      return;
    }

    setState(() {
      // Récupère la ligne existante ou initialise à 0
      final current = _cartLines[product.id];
      // Calcule la nouvelle quantité: +1 de l'existante, normalisée par le stock
      final nextQuantity = _normalizeQuantity(
        (current?.quantity ?? 0) + 1,
        product.quantityInStock,
      );

      // Crée ou met à jour la ligne du panier
      _cartLines[product.id] = _CartLine(
        productId: product.id,
        quantity: nextQuantity,
      );
      // Sélectionne automatiquement le produit nouvellement ajouté
      _selectedCartProductId = product.id;
    });
  }

  /// Modifie la quantité d'un produit dans le panier par un delta (positif ou négatif)
  /// Si la quantité devient <= 0, le produit est supprimé du panier
  void _changeQuantity(Product product, int delta) {
    // Récupère la ligne existante du panier
    final current = _cartLines[product.id];
    // Sort si le produit n'existe pas dans le panier
    if (current == null) {
      return;
    }

    // Calcule la nouvelle quantité avec le delta
    final nextQuantity = current.quantity + delta;
    // Si la quantité devient zéro ou moins, supprime complètement le produit
    if (nextQuantity <= 0) {
      _removeFromCart(product.id);
      return;
    }

    setState(() {
      // Met à jour la quantité normalisée par le stock disponible
      _cartLines[product.id] = current.copyWith(
        quantity: _normalizeQuantity(nextQuantity, product.quantityInStock),
      );
    });
  }

  /// Définit la quantité d'un produit sélectionné à une valeur exacte
  /// Utilisé par les boutons de quantité rapide (1, 2, 5, 10, etc.)
  void _applyQuickQuantity(int quantity, InventoryProvider inventory) {
    // Récupère l'ID du produit actuellement sélectionné
    final productId = _selectedCartProductId;
    // Sort si aucun produit n'est sélectionné
    if (productId == null) {
      return;
    }

    // Récupère les données du produit et sa ligne de panier
    final product = inventory.findProductById(productId);
    final current = _cartLines[productId];
    // Sort si le produit ou sa ligne n'existe pas
    if (product == null || current == null) {
      return;
    }

    setState(() {
      // Met à jour avec la quantité exacte, normalisée par le stock
      _cartLines[productId] = current.copyWith(
        quantity: _normalizeQuantity(quantity, product.quantityInStock),
      );
    });
  }

  /// Supprime un produit du panier
  /// Ajuste aussi la sélection si le produit supprimé était sélectionné
  void _removeFromCart(String productId) {
    setState(() {
      // Supprime la ligne du panier pour ce produit
      _cartLines.remove(productId);

      // Si le produit supprimé était sélectionné, passe à un autre ou à null
      if (_selectedCartProductId == productId) {
        _selectedCartProductId = _cartLines.keys.isEmpty
            ? null
            : _cartLines.keys.first;
      }
    });
  }

  /// Sélectionne un produit du panier pour l'interface (highlight visuel)
  void _selectCartProduct(String productId) {
    setState(() => _selectedCartProductId = productId);
  }

  /// Vide complètement le panier, réinitialise la sélection et les notes
  void _clearCart() {
    setState(() {
      // Supprime tous les articles du panier
      _cartLines.clear();
      // Réinitialise la sélection
      _selectedCartProductId = null;
      // Efface les notes de vente
      _notesController.clear();
    });
  }

  /// Valide et traite la vente: enregistre chaque article comme mouvement de stock 'exit'
  /// Affiche des messages de succès/erreur et vide le panier après succès
  /// Gère les cas: panier vide, validation échouée, contexte non monté, erreurs réseau
  Future<void> _checkoutCart(
    BuildContext context,
    InventoryProvider inventory,
  ) async {
    // Sort si le panier est vide ou si une autre soumission est en cours
    if (_cartLines.isEmpty || _isSubmitting) {
      return;
    }

    // Valide que chaque produit a suffisamment de stock
    final validationError = _validateCart(inventory);
    if (validationError != null) {
      // Affiche le message d'erreur si la validation échoue
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationError)));
      return;
    }

    // Récupère et normalise les notes optionnelles de vente
    final note = _notesController.text.trim();

    // Active le flag de soumission pour éviter les clics doubles
    setState(() => _isSubmitting = true);

    try {
      // Crée une copie des lignes de panier pour itération
      final checkoutLines = _cartLines.values.toList();

      // Enregistre chaque article comme mouvement de stock 'exit'
      for (final line in checkoutLines) {
        await inventory.addStockMovement(
          productId: line.productId,
          movementType: 'exit',
          quantity: line.quantity,
          notes: note.isEmpty ? 'Vente caisse' : note,
        );
      }

      // Vérifie que le contexte est toujours valide après les appels async
      if (!context.mounted) {
        return;
      }

      // Vide le panier après succès
      setState(() {
        _cartLines.clear();
        _selectedCartProductId = null;
        _notesController.clear();
      });

      // Affiche le message de succès
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vente enregistree avec succes.')),
      );
    } catch (e) {
      // Gère les erreurs (validation, réseau, etc.)
      if (!context.mounted) {
        return;
      }

      // Extrait le message d'erreur
      final message = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      // Désactive le flag de soumission si le widget est toujours monté
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Valide que le panier entier peut être vendu
  /// Retourne un message d'erreur si un problème est détecté, null si valide
  /// Vérifie:
  /// - Que chaque produit existe toujours dans le catalogue
  /// - Que les quantités sont positives et valides
  /// - Qu'il y a assez de stock pour chaque article
  String? _validateCart(InventoryProvider inventory) {
    // Itère tous les articles du panier
    for (final line in _cartLines.values) {
      // Vérifie que le produit existe toujours
      final product = inventory.findProductById(line.productId);
      if (product == null) {
        return 'Un produit du panier n existe plus.';
      }

      // Vérifie que la quantité est positive
      if (line.quantity <= 0) {
        return 'Le panier contient une quantite invalide.';
      }

      // Vérifie qu'il y a assez de stock disponible
      if (line.quantity > product.quantityInStock) {
        return 'Stock insuffisant pour ${product.name}. Disponible: ${product.quantityInStock}.';
      }
    }

    // Retourne null si tout est valide
    return null;
  }

  /// Normalise une quantité pour respecter les contraintes du stock
  /// Assure que la quantité est dans l'intervalle [1, maxStock]
  int _normalizeQuantity(int value, int maxStock) {
    // Si le stock max est 0 ou 1, on force à 1 (minimum vendable)
    if (maxStock <= 1) {
      return 1;
    }
    // Si la valeur est < 1, retourne 1 (minimum)
    if (value < 1) {
      return 1;
    }
    // Si la valeur dépasse le stock, retourne le maximum disponible
    if (value > maxStock) {
      return maxStock;
    }
    // Sinon, la valeur est valide
    return value;
  }
}

/// En-tête principal du POS affichant les statistiques du jour et du ticket courant
/// Affiche 4 indicateurs clés: ventes du jour, articles en panier, CA du jour, total du ticket
/// Utilise un gradient bleu avec layout flexible (Wrap) pour s'adapter aux différentes tailles d'écran
class _PosHeader extends StatelessWidget {
  final int todaySalesCount;
  final int totalItems;
  final double todayRevenue;
  final double cartTotal;

  const _PosHeader({
    required this.todaySalesCount,
    required this.totalItems,
    required this.todayRevenue,
    required this.cartTotal,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: isDarkMode
              ? [
                  Color.lerp(primaryColor, Color(0xFF000000), 0.3)!,
                  Color.lerp(primaryColor, Color(0xFF000000), 0.1)!,
                ]
              : const [Color(0xFF0C7EA5), Color(0xFF25B6C6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: isDarkMode
                ? primaryColor.withValues(alpha: 0.15)
                : const Color(0x220C7EA5),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      // Layout flexible: titre + métriques côte à côte avec wrapping automatique
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const SizedBox(width: 250, child: _HeaderIntro()),
          // Métrique 1: Ventes du jour (nombre de tickets)
          _HeaderMetric(
            title: 'Ventes du jour',
            value: todaySalesCount.toString(),
            icon: Icons.receipt_long,
          ),
          // Métrique 2: Articles actuellement dans le panier
          _HeaderMetric(
            title: 'Articles panier',
            value: totalItems.toString(),
            icon: Icons.shopping_cart,
          ),
          // Métrique 3: Chiffre d'affaires généré aujourd'hui
          _HeaderMetric(
            title: 'CA du jour',
            value: '${todayRevenue.toStringAsFixed(2)} Gdes',
            icon: Icons.trending_up,
          ),
          // Métrique 4: Total du ticket courant (montant à payer)
          _HeaderMetric(
            title: 'Total ticket',
            value: '${cartTotal.toStringAsFixed(2)} Gdes',
            icon: Icons.payments,
            accent: Theme.of(context).colorScheme.secondary,
          ),
        ],
      ),
    );
  }
}

/// Affiche le titre introductif et la description de la section POS
/// Partie textuelle gauche de l'en-tête (titre blanc grand + description grise)
class _HeaderIntro extends StatelessWidget {
  const _HeaderIntro();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Titre principal
        const Text(
          'Mode caisse',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        // Description secondaire
        Text(
          'Un ecran de vente rapide, visuel et adapte a votre gestion de stock.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

/// Affiche une métrique individuelle dans l'en-tête (chiffre + icône + libellé)
/// Chaque métrique a un arrière-plan semi-transparent avec bordure légère
/// Support de couleur d'accent customizable pour l'icône (blanc par défaut)
class _HeaderMetric extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color accent;

  const _HeaderMetric({
    required this.title,
    required this.value,
    required this.icon,
    this.accent = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      // Fond semi-transparent avec bordure légère
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar circulaire avec icône colorée
          CircleAvatar(
            radius: 18,
            backgroundColor: accent.withValues(alpha: 0.16),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          // Colonne avec valeur (grande) et libellé (petit)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Valeur grande et en gras (chiffre ou montant)
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              // Libellé petit et grisé
              Text(
                title,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Panneau gauche du POS: panier d'achat (ticket) avec articles, contrôles quantité et encaissement
/// Affiche les articles en panier, permet de les sélectionner et modifier les quantités
/// Inclut contrôles rapides de quantité, notes de vente, et boutons Encaisser/Annuler
/// Responsive: plein écran en desktop, compact en mobile
class _TicketPanel extends StatelessWidget {
  final List<_CartEntryData> entries;
  final String? selectedProductId;
  final _CartEntryData? selectedEntry;
  final TextEditingController notesController;
  final int totalItems;
  final double cartTotal;
  final bool isSubmitting;
  final bool compact;
  final ValueChanged<String> onSelectEntry;
  final ValueChanged<Product> onIncrement;
  final ValueChanged<Product> onDecrement;
  final ValueChanged<String> onRemove;
  final ValueChanged<int> onQuickAdd;
  final VoidCallback? onClear;
  final VoidCallback? onCheckout;

  const _TicketPanel({
    required this.entries,
    required this.selectedProductId,
    required this.selectedEntry,
    required this.notesController,
    required this.totalItems,
    required this.cartTotal,
    required this.isSubmitting,
    required this.onSelectEntry,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onQuickAdd,
    required this.onClear,
    required this.onCheckout,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final card = Container(
      decoration: BoxDecoration(
        color: isDarkMode
            ? Theme.of(context).scaffoldBackgroundColor
            : Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: isDarkMode
                ? const Color(0x080D1B2A)
                : const Color(0x140D1B2A),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        // Mode compact (mobile): pas de scrollable, juste une colonne
        // Mode bureau: scrollable pour accommoder une longue liste d'articles
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildSections(context, scrollable: false),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildSections(context, scrollable: true),
              ),
      ),
    );

    // En mode compact, retourne la carte; en desktop, expand pourt remplir l'espace
    if (compact) {
      return card;
    }

    return SizedBox.expand(child: card);
  }

  /// Construit les sections internes du panier (titre, liste, notes, boutons)
  /// Peut être disposées de manière scrollable ou non selon le contexte
  List<Widget> _buildSections(
    BuildContext context, {
    required bool scrollable,
  }) {
    final widgets = <Widget>[
      // En-tête avec icône et titre
      Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.point_of_sale,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ticket en cours',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 2),
                Text(
                  'Ajoutez des produits puis validez la vente.',
                  style: TextStyle(color: Color(0xFF617287)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '${cartTotal.toStringAsFixed(2)} Gdes',
              style: TextStyle(
                color: Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: _TicketMiniStat(
              label: 'Lignes',
              value: entries.length.toString(),
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _TicketMiniStat(
              label: 'Articles',
              value: totalItems.toString(),
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        'Panier',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
    ];

    if (scrollable) {
      widgets.add(
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                entries.isEmpty
                    ? const _EmptyCartState()
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: entries.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return _CartEntryTile(
                            entry: entry,
                            selected: entry.product.id == selectedProductId,
                            onTap: () => onSelectEntry(entry.product.id),
                            onIncrement: () => onIncrement(entry.product),
                            onDecrement: () => onDecrement(entry.product),
                            onRemove: () => onRemove(entry.product.id),
                          );
                        },
                      ),
                const SizedBox(height: 12),
                _QuickQuantityPanel(
                  selectedEntry: selectedEntry,
                  onQuickAdd: onQuickAdd,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Note ticket',
                    hintText: 'Ex: vente comptoir, livraison, remise locale',
                    filled: true,
                    fillColor:
                        Theme.of(context).inputDecorationTheme.fillColor ??
                        (Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey.withValues(alpha: 0.1)
                            : const Color(0xFFF6F8FB)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).cardColor
                        : const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total a encaisser',
                            style: TextStyle(color: Colors.white70),
                          ),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                '${cartTotal.toStringAsFixed(2)} Gdes',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: onClear,
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white24
                                      : const Color(0x335D6B82),
                                ),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              child: const Text('Vider'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: onCheckout,
                              style: FilledButton.styleFrom(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              icon: isSubmitting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.check_circle_outline),
                              label: Text(
                                isSubmitting ? 'Validation...' : 'Encaisser',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      return widgets;
    } else {
      widgets.add(
        entries.isEmpty
            ? const _EmptyCartState(compact: true)
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: entries.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return _CartEntryTile(
                    entry: entry,
                    selected: entry.product.id == selectedProductId,
                    onTap: () => onSelectEntry(entry.product.id),
                    onIncrement: () => onIncrement(entry.product),
                    onDecrement: () => onDecrement(entry.product),
                    onRemove: () => onRemove(entry.product.id),
                  );
                },
              ),
      );
    }

    widgets.addAll([
      const SizedBox(height: 16),
      _QuickQuantityPanel(selectedEntry: selectedEntry, onQuickAdd: onQuickAdd),
      const SizedBox(height: 16),
      TextField(
        controller: notesController,
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: 'Note ticket',
          hintText: 'Ex: vente comptoir, livraison, remise locale',
          filled: true,
          fillColor:
              Theme.of(context).inputDecorationTheme.fillColor ??
              (Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey.withValues(alpha: 0.1)
                  : const Color(0xFFF6F8FB)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).cardColor
              : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total a encaisser',
                  style: TextStyle(color: Colors.white70),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${cartTotal.toStringAsFixed(2)} Gdes',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onClear,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white24
                            : const Color(0x335D6B82),
                      ),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Vider'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: onCheckout,
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(isSubmitting ? 'Validation...' : 'Encaisser'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ]);

    return widgets;
  }
}

/// Mini-statistique affichée dans le panier
/// Petite carte avec label + valeur numérique, colorée selon le type
class _TicketMiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _TicketMiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(
                context,
              ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// État d'affichage quand le panier est vide
/// Invite l'utilisateur à sélectionner des produits depuis le catalogue
class _EmptyCartState extends StatelessWidget {
  final bool compact;

  const _EmptyCartState({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 18 : 24),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).cardColor
            : const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey.withValues(alpha: 0.2)
              : const Color(0xFFDCE6F2),
        ),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 38,
            color: Color(0xFF94A3B8),
          ),
          SizedBox(height: 10),
          Text(
            'Le panier est vide',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 4),
          Text(
            'Selectionnez des produits a droite pour demarrer une vente.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF617287)),
          ),
        ],
      ),
    );
  }
}

/// Tuile représentant un article dans le panier
/// Affiche image, nom, prix unitaire, quantité, total de ligne et bouton retrait
/// Surlignage visuel quand sélectionné, contrôles +/- quantité
class _CartEntryTile extends StatelessWidget {
  final _CartEntryData entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  const _CartEntryTile({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final borderColor = selected
        ? Theme.of(context).primaryColor
        : (isDarkMode
              ? Colors.grey.withValues(alpha: 0.2)
              : const Color(0xFFDCE6F2));
    final bgColor = selected
        ? Theme.of(context).primaryColor.withValues(alpha: 0.08)
        : (isDarkMode
              ? Colors.grey.withValues(alpha: 0.05)
              : const Color(0xFFF9FBFD));

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor, width: selected ? 1.6 : 1),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProductThumb(product: entry.product, size: 54),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${entry.product.price.toStringAsFixed(2)} Gdes x ${entry.quantity}',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  tooltip: 'Retirer',
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _SquareIconButton(icon: Icons.remove, onPressed: onDecrement),
                Container(
                  width: 56,
                  alignment: Alignment.center,
                  child: Text(
                    entry.quantity.toString(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _SquareIconButton(icon: Icons.add, onPressed: onIncrement),
                const Spacer(),
                Text(
                  '${entry.lineTotal.toStringAsFixed(2)} Gdes',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton carré avec icône pour les contrôles +/- de quantité dans le panier
class _SquareIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _SquareIconButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: const BorderSide(color: Color(0xFFD1D9E6)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Icon(icon, size: 16),
      ),
    );
  }
}

/// Panneau de saisie rapide de quantité par boutons prédéfinis (x1, x2, x3, x5, x10)
/// Affiche le produit sélectionné et son stock disponible
/// Désactivé si aucun article du panier n'est sélectionné
class _QuickQuantityPanel extends StatelessWidget {
  final _CartEntryData? selectedEntry;
  final ValueChanged<int> onQuickAdd;

  const _QuickQuantityPanel({
    required this.selectedEntry,
    required this.onQuickAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAFC),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titre contextuel selon sélection
          Text(
            selectedEntry == null
                ? 'Quantite rapide'
                : 'Quantite rapide - ${selectedEntry!.product.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          // Indication de stock ou instruction de sélection
          Text(
            selectedEntry == null
                ? 'Selectionnez une ligne du panier pour ajuster sa quantite.'
                : 'Stock dispo: ${selectedEntry!.product.quantityInStock}',
            style: const TextStyle(color: Color(0xFF617287)),
          ),
          const SizedBox(height: 12),
          // Chips pour quantités rapides: x1, x2, x3, x5, x10
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [1, 2, 3, 5, 10]
                .map(
                  (value) => ActionChip(
                    label: Text('x$value'),
                    // Désactivé si aucune sélection active
                    onPressed: selectedEntry == null
                        ? null
                        : () => onQuickAdd(value),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

/// Panneau droit du POS: catalogue de produits avec recherche et filtres par catégorie
/// Affiche les produits en grille, permet recherche textuelle et filtrage par catégorie
/// Responsive: colonnes variables selon la taille d'écran (tablet/desktop/mobile)
/// Support des aperçus d'achats récents en bas
class _CatalogPanel extends StatelessWidget {
  final List<Product> products;
  final List<Category> categories;
  final String? selectedCategoryId;
  final String? selectedParentCategoryId;
  final String searchQuery;
  final List<StockMovement> recentSales;
  final InventoryProvider inventory;
  final bool isTablet;
  final bool compact;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onParentCategorySelected;
  final ValueChanged<String?> onCategorySelected;
  final ValueChanged<Product> onAddToCart;

  const _CatalogPanel({
    required this.products,
    required this.categories,
    required this.selectedCategoryId,
    required this.selectedParentCategoryId,
    required this.searchQuery,
    required this.recentSales,
    required this.inventory,
    required this.isTablet,
    required this.onSearchChanged,
    required this.onParentCategorySelected,
    required this.onCategorySelected,
    required this.onAddToCart,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CatalogToolbar(
          selectedCategoryId: selectedCategoryId,
          selectedParentCategoryId: selectedParentCategoryId,
          categories: categories,
          productsCount: products.length,
          onSearchChanged: onSearchChanged,
          onParentCategorySelected: onParentCategorySelected,
          onCategorySelected: onCategorySelected,
        ),
        const SizedBox(height: 16),
        _ProductGrid(
          products: products,
          inventory: inventory,
          compact: compact,
          maxCrossAxisExtent: isTablet ? 220 : 180,
          onAddToCart: onAddToCart,
        ),
        // En mode desktop, on donne toute la hauteur disponible à la grille produits
        // pour une meilleure visibilité des cartes. L'historique reste visible en mode compact.
        if (compact) ...[
          const SizedBox(height: 16),
          _RecentSalesPanel(sales: recentSales, inventory: inventory),
        ],
      ],
    );
  }
}

/// Barre d'outils du catalogue: recherche textuelle et filtres par catégorie
/// Affiche recherche, compteur de produits, et chips de sélection de catégories
class _CatalogToolbar extends StatelessWidget {
  final String? selectedCategoryId;
  final String? selectedParentCategoryId;
  final List<Category> categories;
  final int productsCount;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onParentCategorySelected;
  final ValueChanged<String?> onCategorySelected;

  const _CatalogToolbar({
    required this.selectedCategoryId,
    required this.selectedParentCategoryId,
    required this.categories,
    required this.productsCount,
    required this.onSearchChanged,
    required this.onParentCategorySelected,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final parentCategories = categories
        .where((category) => category.parentId == null)
        .toList();

    final subCategories = selectedParentCategoryId == null
        ? const <Category>[]
        : categories
              .where(
                (category) => category.parentId == selectedParentCategoryId,
              )
              .toList();

    final parentById = <String, Category>{for (final c in categories) c.id: c};
    final selectedParentName = selectedParentCategoryId == null
        ? ''
        : (parentById[selectedParentCategoryId!]?.name ?? 'Parent');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      // Carte blanche avec ombre légère
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100D1B2A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête: titre + compteur
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Catalogue produits',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Touchez une carte produit pour l ajouter au panier.',
                      style: TextStyle(color: Color(0xFF617287)),
                    ),
                  ],
                ),
              ),
              // Badge de comptage
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  '$productsCount produits',
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Champ de recherche textuelle
          TextField(
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Rechercher par nom, code-barres ou description',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor:
                  Theme.of(context).inputDecorationTheme.fillColor ??
                  (Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.withValues(alpha: 0.1)
                      : const Color(0xFFF6F8FB)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Chips de filtrage par categories parents.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Chip "Tous" pour afficher toutes les catégories
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Tous'),
                    selected:
                        selectedParentCategoryId == null &&
                        selectedCategoryId == null,
                    onSelected: (_) {
                      onParentCategorySelected(null);
                      onCategorySelected(null);
                    },
                  ),
                ),
                ...parentCategories.map(
                  (category) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(category.name),
                      selected: selectedParentCategoryId == category.id,
                      onSelected: (_) {
                        onParentCategorySelected(category.id);
                        onCategorySelected(null);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (selectedParentCategoryId != null && subCategories.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('Tous $selectedParentName'),
                      selected: selectedCategoryId == null,
                      onSelected: (_) => onCategorySelected(null),
                    ),
                  ),
                  ...subCategories.map(
                    (subcategory) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(subcategory.name),
                        selected: selectedCategoryId == subcategory.id,
                        onSelected: (_) => onCategorySelected(subcategory.id),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Grille de produits avec nombre de colonnes adaptatif selon la taille
/// Rend _ProductTile pour chaque produit avec layout GridView flexible
/// Gère l'état vide et le scrolling
class _ProductGrid extends StatelessWidget {
  final List<Product> products;
  final InventoryProvider inventory;
  final bool compact;
  final double maxCrossAxisExtent;
  final ValueChanged<Product> onAddToCart;

  const _ProductGrid({
    required this.products,
    required this.inventory,
    required this.compact,
    required this.maxCrossAxisExtent,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    // Affiche un état vide si aucun produit ne correspond aux filtres/recherche
    final grid = products.isEmpty
        ? const _EmptyCatalogState()
        : GridView.builder(
            shrinkWrap: compact,
            physics: compact
                ? const NeverScrollableScrollPhysics()
                : const AlwaysScrollableScrollPhysics(),
            itemCount: products.length,
            // GridView adaptatif: maxCrossAxisExtent variables selon écran
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: maxCrossAxisExtent,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              mainAxisExtent: 340,
            ),
            itemBuilder: (context, index) {
              final product = products[index];
              // Récupère le nom de catégorie pour affichage
              final categoryName =
                  inventory.findCategoryById(product.categoryId ?? '')?.name ??
                  'Sans categorie';

              return _ProductTile(
                product: product,
                categoryName: categoryName,
                // Désactive les clics si le produit est en rupture de stock
                onAdd: product.quantityInStock <= 0
                    ? null
                    : () => onAddToCart(product),
              );
            },
          );

    // En mode compact ou vide, retourne juste la grille
    // Sinon, wraps dans un container Expanded avec styling
    if (compact || products.isEmpty) {
      return grid;
    }

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).scaffoldBackgroundColor
              : Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0x080D1B2A)
                  : const Color(0x100D1B2A),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: grid,
      ),
    );
  }
}

/// État d'affichage quand aucun produit ne correspond aux filtres/recherche
/// Affiche message vide avec icône
class _EmptyCatalogState extends StatelessWidget {
  const _EmptyCatalogState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).cardColor
            : Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icône de catalogue vide
          Icon(Icons.inventory_2_outlined, size: 40, color: Color(0xFF94A3B8)),
          SizedBox(height: 12),
          // Message d'état vide
          Text(
            'Aucun produit a afficher',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 4),
          // Suggestion d'action
          Text(
            'Essayez une autre recherche ou une autre categorie.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF617287)),
          ),
        ],
      ),
    );
  }
}

/// Tuile de produit pour le catalogue POS
/// Affiche: catégorie, image, nom, stock, prix et badge de disponibilité
/// Indicateurs visuels colorés pour états de stock (OK/Bas/Rupture)
/// Bouton "Ajouter" déclenche l'ajout au panier
class _ProductTile extends StatelessWidget {
  final Product product;
  final String categoryName;
  final VoidCallback? onAdd;

  const _ProductTile({
    required this.product,
    required this.categoryName,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    // Détermine l'état du stock pour affichage visuel
    final isOutOfStock = product.quantityInStock <= 0;
    final isLowStock =
        !isOutOfStock && product.quantityInStock <= product.minStockAlert;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onAdd,
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120D1B2A),
              blurRadius: 16,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // En-tête: catégorie + badge de stock
              Row(
                children: [
                  // Nom de la catégorie
                  Expanded(
                    child: Text(
                      categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF617287),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Badge coloré d'état de stock
                  _StockBadge(
                    label: isOutOfStock
                        ? 'Rupture'
                        : isLowStock
                        ? 'Bas'
                        : 'OK',
                    color: isOutOfStock
                        ? Theme.of(context).colorScheme.error
                        : isLowStock
                        ? Colors.orange
                        : Colors.green,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Image du produit
              Expanded(
                child: Center(child: _ProductThumb(product: product, size: 92)),
              ),
              const SizedBox(height: 10),
              // Nom du produit
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              // Quantité en stock
              Text(
                'Stock: ${product.quantityInStock}',
                style: const TextStyle(color: Color(0xFF617287)),
              ),
              const SizedBox(height: 10),
              // Pied: prix + bouton ajouter
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Prix unitaire
                  Text(
                    '${product.price.toStringAsFixed(2)} Gdes',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Bouton ajouter (désactivé en rupture de stock)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onAdd,
                      style: FilledButton.styleFrom(
                        backgroundColor: isOutOfStock
                            ? Colors.grey.withValues(alpha: 0.5)
                            : Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      child: const Text('Ajouter'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Petit badge coloré affichant le statut du stock (OK/Bas/Rupture)
/// Couleurs: vert (OK), orange (Bas), rouge (Rupture)
class _StockBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StockBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      // Texte coloré correspondant au statut
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Affiche l'image miniature d'un produit avec fallback gracieux
/// Charge depuis imageUrl si disponible, sinon affiche un placeholder avec initial
class _ProductThumb extends StatelessWidget {
  final Product product;
  final double size;

  const _ProductThumb({required this.product, required this.size});

  @override
  Widget build(BuildContext context) {
    final url = product.imageUrl?.trim();

    if (url != null && url.startsWith('data:image/')) {
      final commaIndex = url.indexOf(',');
      if (commaIndex > 0 && commaIndex < url.length - 1) {
        try {
          final raw = url.substring(commaIndex + 1);
          final bytes = base64Decode(raw);
          return ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _FallbackProductThumb(label: product.name, size: size),
            ),
          );
        } catch (_) {
          // Continue vers le fallback HTTP/placeholder.
        }
      }
    }

    final lowerUrl = url?.toLowerCase() ?? '';
    final uri = url == null ? null : Uri.tryParse(url);
    final path = uri?.path.toLowerCase() ?? lowerUrl;
    final isHttpImage =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        !path.endsWith('.svg');

    // Si l'URL d'image existe et n'est pas vide, charge l'image réseau
    if (url != null && url.isNotEmpty && isHttpImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // Si l'image échoue, affiche le fallback
          errorBuilder: (context, error, stackTrace) =>
              _FallbackProductThumb(label: product.name, size: size),
        ),
      );
    }

    // Pas d'image, affiche le fallback directement
    return _FallbackProductThumb(label: product.name, size: size);
  }
}

/// Placeholder d'image produit: gradient bleu avec première lettre du nom
/// Affiché quand l'image n'existe pas ou ne peut pas être chargée
class _FallbackProductThumb extends StatelessWidget {
  final String label;
  final double size;

  const _FallbackProductThumb({required this.label, required this.size});

  @override
  Widget build(BuildContext context) {
    final initial = label.trim().isEmpty ? '?' : label.trim()[0].toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: Theme.of(context).brightness == Brightness.dark
              ? [
                  Color.lerp(
                    Theme.of(context).primaryColor,
                    Color(0xFF000000),
                    0.5,
                  )!.withValues(alpha: 0.3),
                  Color.lerp(
                    Theme.of(context).primaryColor,
                    Color(0xFF000000),
                    0.7,
                  )!.withValues(alpha: 0.2),
                ]
              : const [Color(0xFFE8F7FB), Color(0xFFD5EEF4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w800,
          color: Theme.of(context).primaryColor,
        ),
      ),
    );
  }
}

/// Panneau affichant les ventes récentes enregistrées pendant la session
/// Montre les articles vendus au fil du temps avec détails (quantité, prix, notes)
class _RecentSalesPanel extends StatelessWidget {
  final List<StockMovement> sales;
  final InventoryProvider inventory;

  const _RecentSalesPanel({required this.sales, required this.inventory});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).scaffoldBackgroundColor
            : Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0x080D1B2A)
                : const Color(0x100D1B2A),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titre
          const Text(
            'Dernieres ventes',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          // Sous-titre
          Text(
            'Historique recent des tickets enregistres.',
            style: TextStyle(
              color: Theme.of(
                context,
              ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 14),
          // Affiche message vide ou liste des ventes
          if (sales.isEmpty)
            const Text('Aucune vente enregistree pour le moment.')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sales.length,
              separatorBuilder: (context, index) => const Divider(height: 18),
              itemBuilder: (context, index) {
                final sale = sales[index];
                final product = inventory.findProductById(sale.productId);
                final date = sale.createdAt;
                final dateText =
                    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                final price = (product?.price ?? 0) * sale.quantity;

                return Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.15),
                      foregroundColor: Theme.of(context).primaryColor,
                      child: const Icon(Icons.receipt_long),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product?.name ?? 'Produit inconnu',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$dateText • Qt: ${sale.quantity}',
                            style: const TextStyle(color: Color(0xFF617287)),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${price.toStringAsFixed(2)} Gdes',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Modèle de données interne représentant une ligne du panier
/// Stocke l'ID du produit et la quantité commandée
/// Permet la modification immutable via copyWith()
class _CartLine {
  final String productId;
  final int quantity;

  const _CartLine({required this.productId, required this.quantity});

  /// Retourne une copie avec certains champs modifiés
  _CartLine copyWith({String? productId, int? quantity}) {
    return _CartLine(
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
    );
  }
}

/// Modèle de données pour l'affichage d'un article du panier
/// Combine un Product avec sa quantité en panier
/// Calcule automatiquement le total de la ligne (prix unitaire × quantité)
class _CartEntryData {
  final Product product;
  final int quantity;

  const _CartEntryData({required this.product, required this.quantity});

  /// Calcule le montant total de cette ligne (prix unitaire × quantité)
  double get lineTotal => product.price * quantity;
}
