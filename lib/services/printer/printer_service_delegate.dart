import 'printer_models.dart';

abstract class PrinterPlatformDelegate {
  bool get supportsPrinting;

  Future<bool> isConnected();

  Future<List<PrinterDeviceInfo>> getPairedBluetoothDevices();

  Future<bool> connectBluetoothPrinter(PrinterDeviceInfo device);

  Future<void> disconnect();

  Future<void> printLines(List<String> lines);

  Future<void> printQrData(String data);
}
