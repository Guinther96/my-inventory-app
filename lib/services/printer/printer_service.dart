import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'printer_service_delegate.dart';
import 'printer_models.dart';
import 'printer_service_stub.dart'
    if (dart.library.html) 'printer_service_web.dart'
    if (dart.library.io) 'printer_service_io.dart';

class PrinterServiceException implements Exception {
  final String message;

  const PrinterServiceException(this.message);

  @override
  String toString() => message;
}

class PrinterService {
  static final PrinterPlatformDelegate _delegate =
      createPrinterPlatformDelegate();
  static const String _prefPrinterNameKey = 'preferred_printer_name';
  static const String _prefPrinterAddressKey = 'preferred_printer_address';

  static const int _lineWidth = 32;

  static bool get supportsPrinting => _delegate.supportsPrinting;

  static Future<bool> isConnected() => _delegate.isConnected();

  static Future<List<PrinterDeviceInfo>> getPairedBluetoothDevices() async {
    if (!supportsPrinting) {
      return const <PrinterDeviceInfo>[];
    }
    return _delegate.getPairedBluetoothDevices();
  }

  static Future<PrinterDeviceInfo?> getPreferredPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final address = (prefs.getString(_prefPrinterAddressKey) ?? '').trim();
    if (address.isEmpty) {
      return null;
    }
    final name = (prefs.getString(_prefPrinterNameKey) ?? 'Imprimante').trim();
    return PrinterDeviceInfo(name: name, address: address);
  }

  static Future<bool> connectBluetoothPrinter(PrinterDeviceInfo device) async {
    if (!supportsPrinting) {
      return false;
    }
    final connected = await _delegate.connectBluetoothPrinter(device);
    if (connected) {
      await _savePreferredPrinter(device);
    }
    return connected;
  }

  static Future<void> disconnect() => _delegate.disconnect();

  static Future<void> printTestReceipt({required String companyName}) async {
    final now = DateTime.now();
    final lines = <String>[
      _center('[SAAS POS]'),
      _center(companyName.isEmpty ? 'Mon entreprise' : companyName),
      _separator(),
      _center('Test imprimante'),
      'Date: ${DateFormat('dd/MM/yyyy HH:mm').format(now)}',
      _separator(),
      _center('Connexion OK'),
    ];
    await _printGuarded(lines);
  }

  static Future<void> printSaleReceipt({
    required String companyName,
    String? companyEmail,
    required List<Map<String, dynamic>> items,
    required double total,
  }) async {
    final now = DateTime.now();
    final transactionId = 'SALE-${now.millisecondsSinceEpoch}';

    final lines = <String>[
      _center('[SAAS POS]'),
      _center(companyName.isEmpty ? 'Mon entreprise' : companyName),
      _separator(),
      _center('Recu de vente'),
      'Date: ${DateFormat('dd/MM/yyyy HH:mm').format(now)}',
      'Transaction: $transactionId',
      _separator(),
    ];

    for (final item in items) {
      final name = (item['name'] ?? item['productName'] ?? 'Produit')
          .toString()
          .trim();
      final qty = _toInt(item['quantity'] ?? item['qty']);
      final price = _toDouble(item['price'] ?? item['unitPrice']);
      final lineTotal = qty * price;

      lines.add(_truncate(name));
      lines.add('$qty x ${_money(price)} = ${_money(lineTotal)}');
    }

    lines.addAll(<String>[
      _separator(),
      'Total: ${_money(total)}',
      _separator(),
    ]);

    await _printGuarded(
      lines,
      qrData: companyEmail,
      trailingLines: <String>[_center('Merci pour votre achat')],
    );
  }

  static Future<void> printServiceReceipt({
    required String companyName,
    String? companyEmail,
    required String serviceName,
    required double price,
    required String clientName,
    String? cashierName,
  }) async {
    final now = DateTime.now();
    final transactionId = 'SRV-${now.millisecondsSinceEpoch}';

    final lines = <String>[
      _center('[SAAS POS]'),
      _center(companyName.isEmpty ? 'Mon entreprise' : companyName),
      _separator(),
      _center('Recu de service'),
      'Date: ${DateFormat('dd/MM/yyyy HH:mm').format(now)}',
      'Transaction: $transactionId',
      _separator(),
      'Client: ${_truncate(clientName)}',
      if (cashierName != null && cashierName.isNotEmpty)
        'Vendeur: ${_truncate(cashierName)}',
      'Service: ${_truncate(serviceName)}',
      'Prix: ${_money(price)}',
      _separator(),
    ];

    await _printGuarded(
      lines,
      qrData: companyEmail,
      trailingLines: <String>[_center('Merci')],
    );
  }

  static Future<void> _printGuarded(
    List<String> lines, {
    String? qrData,
    List<String> trailingLines = const <String>[],
  }) async {
    if (!supportsPrinting) {
      throw const PrinterServiceException(
        'Impression non disponible sur cette plateforme.',
      );
    }

    if (!await isConnected()) {
      throw const PrinterServiceException('Imprimante non connectee.');
    }

    await _delegate.printLines(lines);
    final value = (qrData ?? '').trim();
    if (value.isNotEmpty) {
      await _delegate.printQrData(value);
    }
    if (trailingLines.isNotEmpty) {
      await _delegate.printLines(trailingLines);
    }
  }

  static Future<void> _savePreferredPrinter(PrinterDeviceInfo device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefPrinterNameKey, device.name);
    await prefs.setString(_prefPrinterAddressKey, device.address);
  }

  static String _center(String value) {
    final text = _truncate(value);
    if (text.length >= _lineWidth) {
      return text;
    }
    final leftPadding = ((_lineWidth - text.length) / 2).floor();
    return '${' ' * leftPadding}$text';
  }

  static String _separator() => '-' * _lineWidth;

  static String _truncate(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= _lineWidth) {
      return trimmed;
    }
    return '${trimmed.substring(0, _lineWidth - 3)}...';
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _toDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _money(double value) => value.toStringAsFixed(2);
}
