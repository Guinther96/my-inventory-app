import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/category_model.dart';
import '../data/models/product_model.dart';
import '../data/models/stock_movement_model.dart';

// Service d'acces aux donnees inventaire dans Supabase.
// Toute lecture/ecriture passe par ce point pour centraliser les requetes SQL.
class InventorySupabaseService {
  // Client Supabase courant initialise dans main.dart.
  SupabaseClient get _client => Supabase.instance.client;

  // Normalise les valeurs de type mouvement pour rester compatibles
  // avec la contrainte SQL: entry | exit | adjustment.
  String _normalizeMovementType(String movementType) {
    final normalized = movementType.trim().toLowerCase();
    if (normalized == 'in') {
      return 'entry';
    }
    if (normalized == 'out') {
      return 'exit';
    }
    if (normalized == 'entry' || normalized == 'exit') {
      return normalized;
    }
    return 'adjustment';
  }

  // Recupere les categories de la company courante, triees par nom.
  Future<List<Category>> fetchCategories(String companyId) async {
    final rows = await _client
        .from('categories')
        .select()
        .eq('company_id', companyId)
        .order('name');

    // Convertit chaque ligne brute en modele Category.
    return (rows as List<dynamic>)
        .map((row) => Category.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  // Recupere les produits de la company courante, tries par nom.
  Future<List<Product>> fetchProducts(String companyId) async {
    final rows = await _client
        .from('products')
        .select()
        .eq('company_id', companyId)
        .order('name');

    return (rows as List<dynamic>).map((row) {
      final raw = Map<String, dynamic>.from(row as Map);
      // Compatibilite avec anciens schemas: quantity_in_stock/min_stock_alert.
      return Product.fromJson({
        ...raw,
        'quantity_in_stock': raw['quantity_in_stock'] ?? raw['quantity'],
        'min_stock_alert': raw['min_stock_alert'] ?? raw['min_stock'],
      });
    }).toList();
  }

  // Recupere les 100 derniers mouvements de stock de la company.
  Future<List<StockMovement>> fetchMovements(String companyId) async {
    final rows = await _client
        .from('stock_movements')
        .select()
        .eq('company_id', companyId)
        .order('created_at', ascending: false)
        .limit(100);

    return (rows as List<dynamic>).map((row) {
      final raw = Map<String, dynamic>.from(row as Map);
      // Compatibilite entre ancien champ movement_type et champ SQL type.
      return StockMovement.fromJson({
        ...raw,
        'movement_type': raw['type'] ?? raw['movement_type'],
      });
    }).toList();
  }

  // Cree ou met a jour une categorie.
  // isNew determine si on envoie explicitement l'id ou non.
  Future<Category> upsertCategory({
    required String companyId,
    required Category category,
    required bool isNew,
  }) async {
    // Payload minimal autorise par le schema categories.
    final payload = <String, dynamic>{
      if (!isNew) 'id': category.id,
      'name': category.name,
      'description': category.description,
      'parent_id': category.parentId,
      'company_id': companyId,
    };

    final row = await _client
        .from('categories')
        .upsert(payload)
        .select()
        .single();

    return Category.fromJson(Map<String, dynamic>.from(row));
  }

  // Supprime une categorie en verifiant l'appartenance a la company.
  Future<void> deleteCategory({
    required String companyId,
    required String categoryId,
  }) async {
    await _client
        .from('categories')
        .delete()
        .eq('id', categoryId)
        .eq('company_id', companyId);
  }

  // Cree ou met a jour un produit.
  Future<Product> upsertProduct({
    required String companyId,
    required Product product,
    required bool isNew,
  }) async {
    // Mapping du modele Flutter vers les colonnes SQL actuelles.
    final payload = <String, dynamic>{
      if (!isNew) 'id': product.id,
      'name': product.name,
      'description': product.description,
      'barcode': product.barcode,
      'price': product.price,
      'quantity': product.quantityInStock,
      'min_stock': product.minStockAlert,
      'category_id': product.categoryId,
      'company_id': companyId,
      'image_url': product.imageUrl,
    };

    final row = await _client
        .from('products')
        .upsert(payload)
        .select()
        .single();

    final raw = Map<String, dynamic>.from(row);
    // Compatibilite legacy sur les noms de colonnes quantite/seuil.
    return Product.fromJson({
      ...raw,
      'quantity_in_stock': raw['quantity_in_stock'] ?? raw['quantity'],
      'min_stock_alert': raw['min_stock_alert'] ?? raw['min_stock'],
    });
  }

  // Supprime un produit en verifiant l'appartenance a la company.
  Future<void> deleteProduct({
    required String companyId,
    required String productId,
  }) async {
    await _client
        .from('products')
        .delete()
        .eq('id', productId)
        .eq('company_id', companyId);
  }

  // Ajoute un mouvement de stock et met a jour la quantite du produit.
  // Retourne a la fois le produit mis a jour et le mouvement cree.
  Future<Map<String, dynamic>> addStockMovement({
    required String companyId,
    required String productId,
    required String movementType,
    required int quantity,
    String? notes,
  }) async {
    // Validation metier locale, en plus de la contrainte SQL (> 0).
    if (quantity <= 0) {
      throw Exception('La quantite doit etre superieure a zero.');
    }

    final normalizedType = _normalizeMovementType(movementType);

    if (normalizedType == 'exit') {
      try {
        final rpcResult = await _client.rpc(
          'process_sale_exit',
          params: {
            'p_company_id': companyId,
            'p_product_id': productId,
            'p_quantity': quantity,
            'p_notes': notes,
          },
        );

        final rpcMap = Map<String, dynamic>.from(rpcResult as Map);
        final rpcProduct = Map<String, dynamic>.from(rpcMap['product'] as Map);
        final rpcMovement = Map<String, dynamic>.from(
          rpcMap['movement'] as Map,
        );
        return {'product': rpcProduct, 'movement': rpcMovement};
      } on PostgrestException catch (e) {
        // Si la fonction RPC n'existe pas encore en base, on retombe sur
        // l'ancien flux pour compatibilite manager, puis on gere l'echec plus bas.
        if (e.code != '42883') {
          rethrow;
        }
      }
    }

    // Lit l'etat courant du produit pour calculer la nouvelle quantite.
    final productRow = await _client
        .from('products')
        .select('id, quantity, company_id, name, min_stock, price, category_id')
        .eq('id', productId)
        .eq('company_id', companyId)
        .maybeSingle();

    if (productRow == null) {
      throw Exception(
        'Produit introuvable ou inaccessible pour cette entreprise.',
      );
    }

    final currentQty = (productRow['quantity'] as num?)?.toInt() ?? 0;
    int nextQty = currentQty;

    // Regles de calcul selon le type de mouvement.
    if (normalizedType == 'entry') {
      nextQty = currentQty + quantity;
    } else if (normalizedType == 'exit') {
      nextQty = currentQty - quantity;
      // Protection locale pour eviter une quantite negative.
      if (nextQty < 0) {
        nextQty = 0;
      }
    } else {
      // Adjustment: quantity represente la valeur finale en stock.
      nextQty = quantity;
    }

    // Persiste la nouvelle quantite sur le produit cible.
    final updatedProduct = await _client
        .from('products')
        .update({'quantity': nextQty})
        .eq('id', productId)
        .eq('company_id', companyId)
        .select()
        .maybeSingle();

    if (updatedProduct == null) {
      throw Exception(
        'Mise a jour de stock refusee (droits insuffisants). '
        'Appliquez la migration SQL process_sale_exit pour permettre l encaissement seller.',
      );
    }

    // Cree la trace de mouvement pour l'historique.
    final movementRow = await _client
        .from('stock_movements')
        .insert({
          'product_id': productId,
          // user_id est optionnel, lie a l'utilisateur connecte si disponible.
          'user_id': _client.auth.currentUser?.id,
          // seller_id tracke le vendeur sur les mouvements de vente (type exit).
          if (normalizedType == 'exit')
            'seller_id': _client.auth.currentUser?.id,
          'type': normalizedType,
          'quantity': quantity,
          'company_id': companyId,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        })
        .select()
        .maybeSingle();

    if (movementRow == null) {
      throw Exception('Creation du mouvement de stock echouee.');
    }

    // Reponse utile au provider: produit + mouvement crees.
    return {'product': updatedProduct, 'movement': movementRow};
  }

  // Purge toutes les donnees inventaire d'une company.
  // Ordre important pour respecter les FK (mouvements -> produits -> categories).
  Future<void> clearCompanyData(String companyId) async {
    await _client.from('stock_movements').delete().eq('company_id', companyId);
    await _client.from('products').delete().eq('company_id', companyId);
    await _client.from('categories').delete().eq('company_id', companyId);
  }
}
