enum AppCurrency {
  htg,
  usd;

  String get code => this == AppCurrency.htg ? 'HTG' : 'USD';

  String get label =>
      this == AppCurrency.htg ? 'Gourde (HTG)' : 'Dollar (USD)';

  static AppCurrency fromCode(String? raw) {
    final normalized = (raw ?? '').trim().toUpperCase();
    return normalized == 'USD' ? AppCurrency.usd : AppCurrency.htg;
  }
}

const List<String> kSupportedCurrencies = <String>['HTG', 'USD'];

String normalizeCurrencyCode(String? raw) => AppCurrency.fromCode(raw).code;

String formatMoney(double amount, String? currencyCode) {
  return '${amount.toStringAsFixed(2)} ${normalizeCurrencyCode(currencyCode)}';
}

/// Formatte un ensemble de montants regroupes par devise en une chaine
/// lisible, ex: "500.00 HTG + 10.00 USD". Un stock ou un chiffre d'affaires
/// mixte HTG/USD ne peut pas etre resume par un seul nombre.
String formatMoneyByCurrency(Map<String, double> amountsByCurrency) {
  if (amountsByCurrency.isEmpty) {
    return formatMoney(0, 'HTG');
  }
  return amountsByCurrency.entries
      .map((entry) => formatMoney(entry.value, entry.key))
      .join(' + ');
}

/// Converts [amount] expressed in [fromCurrency] into [toCurrency] using the
/// company's configured USD to HTG rate (1 USD = [usdToHtgRate] HTG).
/// Returns null if a conversion is required but no rate is configured.
double? convertAmount({
  required double amount,
  required String fromCurrency,
  required String toCurrency,
  required double? usdToHtgRate,
}) {
  final from = normalizeCurrencyCode(fromCurrency);
  final to = normalizeCurrencyCode(toCurrency);

  if (from == to) {
    return amount;
  }

  if (usdToHtgRate == null || usdToHtgRate <= 0) {
    return null;
  }

  if (from == 'USD' && to == 'HTG') {
    return amount * usdToHtgRate;
  }

  if (from == 'HTG' && to == 'USD') {
    return amount / usdToHtgRate;
  }

  return null;
}

double _round2(double value) => double.parse(value.toStringAsFixed(2));

/// Resultat du calcul de taxe: montants deja arrondis a 2 decimales et
/// exprimes dans la devise de paiement du ticket.
class TaxCalculationResult {
  final double subtotal;
  final double taxAmount;
  final double total;

  const TaxCalculationResult({
    required this.subtotal,
    required this.taxAmount,
    required this.total,
  });
}

/// Calcule la taxe configurable sur [subtotal] (deja exprime dans
/// [paymentCurrency]). Retourne null si une conversion de devise est requise
/// (taxe a montant fixe dans une devise differente du paiement) mais qu'aucun
/// taux de change n'est configure — meme convention que [convertAmount].
///
/// Utilisee a la fois pour l'apercu panier cote client et, pour les
/// services, comme calcul faisant autorite avant insertion (ServiceOrderService).
TaxCalculationResult? calculateTax({
  required double subtotal,
  required bool taxEnabled,
  required String taxType,
  required double taxValue,
  String? taxCurrency,
  required String paymentCurrency,
  double? usdToHtgRate,
}) {
  final normalizedPayment = normalizeCurrencyCode(paymentCurrency);
  final subtotalRounded = _round2(subtotal);

  if (!taxEnabled) {
    return TaxCalculationResult(
      subtotal: subtotalRounded,
      taxAmount: 0,
      total: subtotalRounded,
    );
  }

  double rawTax;
  if (taxType == 'fixed') {
    final normalizedTaxCurrency = normalizeCurrencyCode(
      taxCurrency ?? normalizedPayment,
    );
    final converted = convertAmount(
      amount: taxValue,
      fromCurrency: normalizedTaxCurrency,
      toCurrency: normalizedPayment,
      usdToHtgRate: usdToHtgRate,
    );
    if (converted == null) {
      return null;
    }
    rawTax = converted;
  } else {
    rawTax = subtotal * taxValue / 100;
  }

  final taxAmount = _round2(rawTax);
  final total = _round2(subtotalRounded + taxAmount);
  return TaxCalculationResult(
    subtotal: subtotalRounded,
    taxAmount: taxAmount,
    total: total,
  );
}
