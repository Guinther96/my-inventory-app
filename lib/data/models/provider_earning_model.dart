class ProviderEarning {
  final String id;
  final String providerId;
  final String reservationId;
  final double amount;
  final DateTime createdAt;

  const ProviderEarning({
    required this.id,
    required this.providerId,
    required this.reservationId,
    required this.amount,
    required this.createdAt,
  });

  factory ProviderEarning.fromJson(Map<String, dynamic> json) {
    return ProviderEarning(
      id: json['id']?.toString() ?? '',
      providerId: json['provider_id']?.toString() ?? '',
      reservationId: json['reservation_id']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'provider_id': providerId,
        'reservation_id': reservationId,
        'amount': amount,
        'created_at': createdAt.toIso8601String(),
      };
}
