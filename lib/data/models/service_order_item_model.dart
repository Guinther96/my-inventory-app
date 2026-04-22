class ServiceOrderItem {
  final String id;
  final String serviceOrderId;
  final String? serviceId;
  final String serviceName;
  final double unitPrice;
  final int quantity;
  final double lineTotal;
  final String? providerId;
  final String? providerName;
  final DateTime createdAt;

  ServiceOrderItem({
    required this.id,
    required this.serviceOrderId,
    this.serviceId,
    required this.serviceName,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
    this.providerId,
    this.providerName,
    required this.createdAt,
  });

  factory ServiceOrderItem.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] ?? json['createdAt'];

    return ServiceOrderItem(
      id: json['id']?.toString() ?? '',
      serviceOrderId: json['service_order_id']?.toString() ?? '',
      serviceId: json['service_id']?.toString(),
      serviceName: json['service_name']?.toString() ?? '',
      unitPrice: double.tryParse(json['unit_price']?.toString() ?? '') ?? 0,
      quantity: int.tryParse(json['quantity']?.toString() ?? '') ?? 1,
      lineTotal: double.tryParse(json['line_total']?.toString() ?? '') ?? 0,
      providerId: json['provider_id']?.toString(),
      providerName: json['provider_name']?.toString(),
      createdAt:
          DateTime.tryParse(createdAtRaw?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'service_order_id': serviceOrderId,
      'service_id': serviceId,
      'service_name': serviceName,
      'unit_price': unitPrice,
      'quantity': quantity,
      'line_total': lineTotal,
      if (providerId != null) 'provider_id': providerId,
      if (providerName != null) 'provider_name': providerName,
    };
  }
}
