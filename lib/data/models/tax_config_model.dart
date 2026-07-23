import '../../core/utils/currency.dart';

/// Configuration de taxe/frais d'une entreprise (section "Taxes et frais"
/// des parametres). Stockee sur public.companies (tax_enabled, tax_name,
/// tax_type, tax_value, tax_currency).
class TaxConfig {
  final bool enabled;
  final String name;
  final String type; // 'fixed' | 'percentage'
  final double value;
  final String? currency; // pertinent seulement si type == 'fixed'

  const TaxConfig({
    required this.enabled,
    required this.name,
    required this.type,
    required this.value,
    this.currency,
  });

  static const TaxConfig disabled = TaxConfig(
    enabled: false,
    name: 'Taxe',
    type: 'percentage',
    value: 0,
    currency: null,
  );

  bool get isFixed => type == 'fixed';
  bool get isPercentage => type == 'percentage';

  factory TaxConfig.fromJson(Map<String, dynamic> json) {
    final rawType = json['tax_type']?.toString().trim().toLowerCase();
    final rawCurrency = json['tax_currency']?.toString();

    return TaxConfig(
      enabled: json['tax_enabled'] == true,
      name: (json['tax_name']?.toString().trim().isNotEmpty ?? false)
          ? json['tax_name'].toString().trim()
          : 'Taxe',
      type: rawType == 'fixed' ? 'fixed' : 'percentage',
      value: double.tryParse(json['tax_value']?.toString() ?? '') ?? 0,
      currency: (rawCurrency != null && rawCurrency.trim().isNotEmpty)
          ? normalizeCurrencyCode(rawCurrency)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tax_enabled': enabled,
      'tax_name': name,
      'tax_type': type,
      'tax_value': value,
      'tax_currency': isFixed ? normalizeCurrencyCode(currency) : null,
    };
  }

  TaxConfig copyWith({
    bool? enabled,
    String? name,
    String? type,
    double? value,
    String? currency,
  }) {
    return TaxConfig(
      enabled: enabled ?? this.enabled,
      name: name ?? this.name,
      type: type ?? this.type,
      value: value ?? this.value,
      currency: currency ?? this.currency,
    );
  }
}
