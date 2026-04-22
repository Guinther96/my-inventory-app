import 'printer_service_delegate.dart';
import 'printer_models.dart';

PrinterPlatformDelegate createPrinterPlatformDelegate() {
  return _WebPrinterPlatformDelegate();
}

class _WebPrinterPlatformDelegate implements PrinterPlatformDelegate {
  @override
  bool get supportsPrinting => false;

  @override
  Future<bool> isConnected() async => false;

  @override
  Future<List<PrinterDeviceInfo>> getPairedBluetoothDevices() async =>
      const <PrinterDeviceInfo>[];

  @override
  Future<bool> connectBluetoothPrinter(PrinterDeviceInfo device) async => false;

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> printLines(List<String> lines) async {
    throw UnsupportedError('Impression Bluetooth non supportee sur Web.');
  }

  @override
  Future<void> printQrData(String data) async {
    throw UnsupportedError('Impression QR non supportee sur Web.');
  }
}
