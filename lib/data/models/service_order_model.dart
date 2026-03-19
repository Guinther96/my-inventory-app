import 'service_order_item_model.dart';

class ServiceOrder {
  final String id;
  final String companyId;
  final String? clientId;
  final String clientName;
  final String? cashierId;
  final String? cashierName;
  final String? reservationId;
  final String? ticketNumber;
  final String? paymentMethod;
  final String paymentStatus;
  final double subtotalAmount;
  final double discountAmount;
  final double totalAmount;
  final double paidAmount;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ServiceOrderItem> items;

  ServiceOrder({
    required this.id,
    required this.companyId,
    this.clientId,
    required this.clientName,
    this.cashierId,
    this.cashierName,
    this.reservationId,
    this.ticketNumber,
    this.paymentMethod,
    required this.paymentStatus,
    required this.subtotalAmount,
    required this.discountAmount,
    required this.totalAmount,
    required this.paidAmount,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.items = const <ServiceOrderItem>[],
  });

  factory ServiceOrder.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] ?? json['createdAt'];
    final updatedAtRaw = json['updated_at'] ?? json['updatedAt'];

    final rawItems = json['service_order_items'];
    final items = rawItems is List<dynamic>
        ? rawItems
              .map(
                (e) => ServiceOrderItem.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList()
        : const <ServiceOrderItem>[];

    return ServiceOrder(
      id: json['id']?.toString() ?? '',
      companyId: json['company_id']?.toString() ?? '',
      clientId: json['client_id']?.toString(),
      clientName: json['client_name']?.toString() ?? '',
      cashierId: json['cashier_id']?.toString(),
      cashierName: json['cashier_name']?.toString(),
      reservationId: json['reservation_id']?.toString(),
      ticketNumber: json['ticket_number']?.toString(),
      paymentMethod: json['payment_method']?.toString(),
      paymentStatus: json['payment_status']?.toString() ?? 'paid',
      subtotalAmount:
          double.tryParse(json['subtotal_amount']?.toString() ?? '') ?? 0,
      discountAmount:
          double.tryParse(json['discount_amount']?.toString() ?? '') ?? 0,
      totalAmount: double.tryParse(json['total_amount']?.toString() ?? '') ?? 0,
      paidAmount: double.tryParse(json['paid_amount']?.toString() ?? '') ?? 0,
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
      'client_id': clientId,
      'client_name': clientName,
      'cashier_id': cashierId,
      'cashier_name': cashierName,
      'reservation_id': reservationId,
      'ticket_number': ticketNumber,
      'payment_method': paymentMethod,
      'payment_status': paymentStatus,
      'subtotal_amount': subtotalAmount,
      'discount_amount': discountAmount,
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'notes': notes,
    };
  }
}
