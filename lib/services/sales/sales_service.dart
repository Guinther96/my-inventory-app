import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/currency.dart';
import '../../data/models/sale_model.dart';

/// Une ligne de panier a encaisser (produit + quantite), transmise telle
/// quelle au RPC process_sale_checkout qui fait autorite sur le prix, la
/// devise et le calcul de taxe.
class CartItemInput {
  final String productId;
  final int quantity;

  const CartItemInput({required this.productId, required this.quantity});

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'quantity': quantity,
  };
}

/// Totaux de ventes (produits ou services) agreges par devise, utilises
/// pour le bloc rapports "Ventes & taxes".
class SalesTaxTotals {
  final int count;
  final double subtotal;
  final double taxAmount;
  final double total;

  const SalesTaxTotals({
    this.count = 0,
    this.subtotal = 0,
    this.taxAmount = 0,
    this.total = 0,
  });

  SalesTaxTotals operator +(SalesTaxTotals other) => SalesTaxTotals(
    count: count + other.count,
    subtotal: subtotal + other.subtotal,
    taxAmount: taxAmount + other.taxAmount,
    total: total + other.total,
  );
}

class SalesService {
  SupabaseClient get _client => Supabase.instance.client;

  /// Encaisse tout le panier en une seule transaction serveur: le RPC
  /// recalcule prix/devise/taxe depuis la base (jamais confiance au client),
  /// decremente le stock et cree l'en-tete `sales` + les lignes `sale_items`
  /// + les mouvements de stock correspondants.
  Future<Sale> checkoutCart({
    required String companyId,
    required List<CartItemInput> items,
    String? paymentCurrency,
    String? notes,
  }) async {
    if (items.isEmpty) {
      throw Exception('Le panier est vide.');
    }

    final result = await _client.rpc(
      'process_sale_checkout',
      params: {
        'p_company_id': companyId,
        'p_items': items.map((item) => item.toJson()).toList(),
        'p_payment_currency': paymentCurrency,
        'p_notes': notes,
      },
    );

    final resultMap = Map<String, dynamic>.from(result as Map);
    final saleJson = Map<String, dynamic>.from(resultMap['sale'] as Map);
    final itemsJson = (resultMap['items'] as List<dynamic>? ?? [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    return Sale.fromJson({...saleJson, 'items': itemsJson});
  }

  /// Ventes produits de la company, pour les rapports. Agregation cote
  /// client par devise, coherent avec le style de reports_screen.dart.
  Future<Map<String, SalesTaxTotals>> fetchSalesTotals(String companyId) async {
    final rows = await _client
        .from('sales')
        .select('subtotal_amount, tax_amount, total_amount, payment_currency')
        .eq('company_id', companyId);

    final totals = <String, SalesTaxTotals>{};
    for (final row in (rows as List<dynamic>)) {
      final map = Map<String, dynamic>.from(row as Map);
      final currency = normalizeCurrencyCode(
        map['payment_currency']?.toString(),
      );
      final entry = SalesTaxTotals(
        count: 1,
        subtotal: double.tryParse(map['subtotal_amount']?.toString() ?? '') ?? 0,
        taxAmount: double.tryParse(map['tax_amount']?.toString() ?? '') ?? 0,
        total: double.tryParse(map['total_amount']?.toString() ?? '') ?? 0,
      );
      totals.update(
        currency,
        (value) => value + entry,
        ifAbsent: () => entry,
      );
    }
    return totals;
  }
}
