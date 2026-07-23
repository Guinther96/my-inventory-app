import '../../core/utils/currency.dart';

class SaleItem {
  final String id;
  final String saleId;
  final String? productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final String productCurrency;
  final double lineTotal;
  final String? stockMovementId;
  final DateTime createdAt;

  SaleItem({
    required this.id,
    required this.saleId,
    this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.productCurrency = 'HTG',
    required this.lineTotal,
    this.stockMovementId,
    required this.createdAt,
  });

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] ?? json['createdAt'];

    return SaleItem(
      id: json['id']?.toString() ?? '',
      saleId: json['sale_id']?.toString() ?? '',
      productId: json['product_id']?.toString(),
      productName: json['product_name']?.toString() ?? '',
      quantity: int.tryParse(json['quantity']?.toString() ?? '') ?? 1,
      unitPrice: double.tryParse(json['unit_price']?.toString() ?? '') ?? 0,
      productCurrency: normalizeCurrencyCode(
        json['product_currency']?.toString(),
      ),
      lineTotal: double.tryParse(json['line_total']?.toString() ?? '') ?? 0,
      stockMovementId: json['stock_movement_id']?.toString(),
      createdAt:
          DateTime.tryParse(createdAtRaw?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'sale_id': saleId,
      'product_id': productId,
      'product_name': productName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'product_currency': productCurrency,
      'line_total': lineTotal,
      if (stockMovementId != null) 'stock_movement_id': stockMovementId,
    };
  }
}
