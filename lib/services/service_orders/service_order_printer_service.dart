import 'package:flutter/foundation.dart';

import '../../data/models/service_order_model.dart';
import '../features/feature_service.dart';
import '../printer/printer_service.dart';

/// Service for handling printing of service orders.
/// Encapsulates all printer logic for service order validation and receipts.
class ServiceOrderPrinterService {
  /// Prints a service order receipt if printer is available and enabled.
  ///
  /// Returns `true` if print was attempted or printer is disabled,
  /// `false` if printer is not connected.
  Future<bool> printServiceOrderReceipt({
    required ServiceOrder order,
    required String companyName,
    String? companyEmail,
  }) async {
    // Check if printing is enabled via feature flag
    if (!FeatureService.isEnabled('print')) {
      debugPrint('Printing is disabled via feature flag');
      return true;
    }

    try {
      // Check if printer is connected
      final connected = await PrinterService.isConnected();
      if (!connected) {
        debugPrint('Printer not connected for service order: ${order.id}');
        return false;
      }

      // Format service name(s)
      final serviceName = order.items.length == 1
          ? order.items.first.serviceName
          : 'Commande de ${order.items.length} services';

      // Send to printer
      await PrinterService.printServiceReceipt(
        companyName: companyName,
        companyEmail: companyEmail,
        serviceName: serviceName,
        price: order.totalAmount,
        clientName: order.clientName,
        cashierName: order.cashierName,
      );

      debugPrint('Service order printed successfully: ${order.id}');
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error printing service order receipt: $e');
      debugPrint('StackTrace: $stackTrace');
      return false;
    }
  }

  /// Validates printer is ready before service order submission.
  ///
  /// Returns `PrinterStatus` with connection state and any error message.
  Future<PrinterStatus> validatePrinterReady() async {
    if (!FeatureService.isEnabled('print')) {
      return const PrinterStatus(
        isEnabled: false,
        isConnected: false,
        message: 'Printing is disabled',
      );
    }

    try {
      final connected = await PrinterService.isConnected();
      return PrinterStatus(
        isEnabled: true,
        isConnected: connected,
        message: connected
            ? 'Imprimante disponible'
            : 'Imprimante non connectee',
      );
    } catch (e) {
      return PrinterStatus(
        isEnabled: true,
        isConnected: false,
        message: 'Erreur de connexion imprimante: $e',
      );
    }
  }

  /// Creates a silent print attempt that logs but doesn't throw.
  ///
  /// Used internally to print without blocking the service order save.
  Future<PrintResult> silentPrintServiceOrder({
    required ServiceOrder order,
    required String companyName,
    String? companyEmail,
  }) async {
    try {
      final success = await printServiceOrderReceipt(
        order: order,
        companyName: companyName,
        companyEmail: companyEmail,
      );

      return PrintResult(
        success: success,
        message: success ? 'Ticket imprime' : 'Imprimante non connectee',
      );
    } catch (e) {
      return PrintResult(success: false, message: 'Erreur impression: $e');
    }
  }
}

/// Result of a printer operation.
class PrintResult {
  final bool success;
  final String message;

  const PrintResult({required this.success, required this.message});

  @override
  String toString() => 'PrintResult(success: $success, message: $message)';
}

/// Status of the printer for validation.
class PrinterStatus {
  final bool isEnabled;
  final bool isConnected;
  final String message;

  const PrinterStatus({
    required this.isEnabled,
    required this.isConnected,
    required this.message,
  });

  bool get isReady => isEnabled && isConnected;

  @override
  String toString() =>
      'PrinterStatus(enabled: $isEnabled, connected: $isConnected, message: $message)';
}
