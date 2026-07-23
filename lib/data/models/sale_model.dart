import '../../core/utils/currency.dart';
import 'sale_item_model.dart';

class Sale {
  final String id;
  final String companyId;
  final String? cashierId;
  final String? cashierName;
  final String paymentCurrency;
  final double? exchangeRate;
  final double subtotalAmount;
  final bool taxEnabled;
  final String? taxName;
  final String? taxType;
  final double? taxValue;
  final double taxAmount;
  final double totalAmount;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<SaleItem> items;

  Sale({
    required this.id,
    required this.companyId,
    this.cashierId,
    this.cashierName,
    this.paymentCurrency = 'HTG',
    this.exchangeRate,
    required this.subtotalAmount,
    this.taxEnabled = false,
    this.taxName,
    this.taxType,
    this.taxValue,
    required this.taxAmount,
    required this.totalAmount,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.items = const <SaleItem>[],
  });

  bool get isTaxPercentage => taxType == 'percentage';

  factory Sale.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] ?? json['createdAt'];
    final updatedAtRaw = json['updated_at'] ?? json['updatedAt'];

    final rawItems = json['items'] ?? json['sale_items'];
    final items = rawItems is List<dynamic>
        ? rawItems
              .map((e) => SaleItem.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()
        : const <SaleItem>[];

    return Sale(
      id: json['id']?.toString() ?? '',
      companyId: json['company_id']?.toString() ?? '',
      cashierId: json['cashier_id']?.toString(),
      cashierName: json['cashier_name']?.toString(),
      paymentCurrency: normalizeCurrencyCode(
        json['payment_currency']?.toString(),
      ),
      exchangeRate: double.tryParse(json['exchange_rate']?.toString() ?? ''),
      subtotalAmount:
          double.tryParse(json['subtotal_amount']?.toString() ?? '') ?? 0,
      taxEnabled: json['tax_enabled'] == true,
      taxName: json['tax_name']?.toString(),
      taxType: json['tax_type']?.toString(),
      taxValue: double.tryParse(json['tax_value']?.toString() ?? ''),
      taxAmount: double.tryParse(json['tax_amount']?.toString() ?? '') ?? 0,
      totalAmount: double.tryParse(json['total_amount']?.toString() ?? '') ?? 0,
      notes: json['notes']?.toString(),
      createdAt:
          DateTime.tryParse(createdAtRaw?.toString() ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(updatedAtRaw?.toString() ?? '') ?? DateTime.now(),
      items: items,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'company_id': companyId,
      'cashier_id': cashierId,
      'cashier_name': cashierName,
      'payment_currency': paymentCurrency,
      if (exchangeRate != null) 'exchange_rate': exchangeRate,
      'subtotal_amount': subtotalAmount,
      'tax_enabled': taxEnabled,
      'tax_name': taxName,
      'tax_type': taxType,
      'tax_value': taxValue,
      'tax_amount': taxAmount,
      'total_amount': totalAmount,
      'notes': notes,
    };
  }
}
