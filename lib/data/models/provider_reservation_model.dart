class ProviderReservation {
  final String id;
  final String businessId;
  final String providerId;
  final String clientName;
  final String serviceName;
  final double price;
  final DateTime date;
  final String time; // "HH:MM"
  final String status; // pending | completed | cancelled
  final String createdBy;
  final DateTime createdAt;

  const ProviderReservation({
    required this.id,
    required this.businessId,
    required this.providerId,
    required this.clientName,
    required this.serviceName,
    required this.price,
    required this.date,
    required this.time,
    required this.status,
    required this.createdBy,
    required this.createdAt,
  });

  factory ProviderReservation.fromJson(Map<String, dynamic> json) {
    return ProviderReservation(
      id: json['id']?.toString() ?? '',
      businessId: json['business_id']?.toString() ?? '',
      providerId: json['provider_id']?.toString() ?? '',
      clientName: json['client_name']?.toString() ?? '',
      serviceName: json['service_name']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      time: json['time']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      createdBy: json['created_by']?.toString() ?? 'provider',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'business_id': businessId,
        'provider_id': providerId,
        'client_name': clientName,
        'service_name': serviceName,
        'price': price,
        'date': date.toIso8601String().substring(0, 10),
        'time': time,
        'status': status,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
      };

  ProviderReservation copyWith({
    String? id,
    String? businessId,
    String? providerId,
    String? clientName,
    String? serviceName,
    double? price,
    DateTime? date,
    String? time,
    String? status,
    String? createdBy,
    DateTime? createdAt,
  }) {
    return ProviderReservation(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      providerId: providerId ?? this.providerId,
      clientName: clientName ?? this.clientName,
      serviceName: serviceName ?? this.serviceName,
      price: price ?? this.price,
      date: date ?? this.date,
      time: time ?? this.time,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
