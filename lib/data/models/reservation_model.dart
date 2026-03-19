class Reservation {
  final String id;
  final String companyId;
  final String? clientId;
  final String clientName;
  final String? phone;
  final String serviceId;
  final DateTime reservedAt;
  final String status;
  final String? notes;
  final String? createdBy;
  final String? convertedOrderId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Reservation({
    required this.id,
    required this.companyId,
    this.clientId,
    required this.clientName,
    this.phone,
    required this.serviceId,
    required this.reservedAt,
    required this.status,
    this.notes,
    this.createdBy,
    this.convertedOrderId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Reservation.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] ?? json['createdAt'];
    final updatedAtRaw = json['updated_at'] ?? json['updatedAt'];
    final reservedAtRaw = json['reserved_at'] ?? json['reservedAt'];

    return Reservation(
      id: json['id']?.toString() ?? '',
      companyId: json['company_id']?.toString() ?? '',
      clientId: json['client_id']?.toString(),
      clientName: json['client_name']?.toString() ?? '',
      phone: json['phone']?.toString(),
      serviceId: json['service_id']?.toString() ?? '',
      reservedAt:
          DateTime.tryParse(reservedAtRaw?.toString() ?? '') ?? DateTime.now(),
      status: json['status']?.toString() ?? 'pending',
      notes: json['notes']?.toString(),
      createdBy: json['created_by']?.toString(),
      convertedOrderId: json['converted_order_id']?.toString(),
      createdAt:
          DateTime.tryParse(createdAtRaw?.toString() ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(updatedAtRaw?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Reservation copyWith({
    String? id,
    String? companyId,
    String? clientId,
    String? clientName,
    String? phone,
    String? serviceId,
    DateTime? reservedAt,
    String? status,
    String? notes,
    String? createdBy,
    String? convertedOrderId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Reservation(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      phone: phone ?? this.phone,
      serviceId: serviceId ?? this.serviceId,
      reservedAt: reservedAt ?? this.reservedAt,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      convertedOrderId: convertedOrderId ?? this.convertedOrderId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'company_id': companyId,
      'client_id': clientId,
      'client_name': clientName,
      'phone': phone,
      'service_id': serviceId,
      'reserved_at': reservedAt.toIso8601String(),
      'status': status,
      'notes': notes,
      'created_by': createdBy,
      'converted_order_id': convertedOrderId,
    };
  }
}
