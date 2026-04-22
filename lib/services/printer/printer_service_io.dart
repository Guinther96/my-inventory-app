import 'package:blue_thermal_printer/blue_thermal_printer.dart';

import 'printer_service_delegate.dart';
import 'printer_models.dart';

PrinterPlatformDelegate createPrinterPlatformDelegate() {
  return _IoPrinterPlatformDelegate();
}

class _IoPrinterPlatformDelegate implements PrinterPlatformDelegate {
  final BlueThermalPrinter _printer = BlueThermalPrinter.instance;

  @override
  bool get supportsPrinting => true;

  @override
  Future<bool> isConnected() async {
    try {
      final connected = await _printer.isConnected;
      return connected ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<PrinterDeviceInfo>> getPairedBluetoothDevices() async {
    try {
      final bonded = await _printer.getBondedDevices();

      final devices = <PrinterDeviceInfo>[];
      for (final device in bonded) {
        final address = (device.address ?? '').trim();
        if (address.isEmpty) {
          continue;
        }
        final name = (device.name ?? 'Imprimante').trim();
        devices.add(PrinterDeviceInfo(name: name, address: address));
      }
      return devices;
    } catch (_) {
      return const <PrinterDeviceInfo>[];
    }
  }

  @override
  Future<bool> connectBluetoothPrinter(PrinterDeviceInfo target) async {
    try {
      final bonded = await _printer.getBondedDevices();
      if (bonded.isEmpty) {
        return false;
      }

      BluetoothDevice? selected;
      for (final device in bonded) {
        if ((device.address ?? '').toLowerCase() ==
            target.address.toLowerCase()) {
          selected = device;
          break;
        }
      }

      if (selected == null) {
        return false;
      }

      if (await isConnected()) {
        await _printer.disconnect();
      }

      await _printer.connect(selected);
      return await isConnected();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _printer.disconnect();
    } catch (_) {
      // Ignore: disconnect should be best-effort.
    }
  }

  @override
  Future<void> printLines(List<String> lines) async {
    for (final line in lines) {
      await _printer.printCustom(line, 1, 0);
    }
    await _printer.printNewLine();
    await _printer.printNewLine();
    await _printer.paperCut();
  }

  @override
  Future<void> printQrData(String data) async {
    final value = data.trim();
    if (value.isEmpty) {
      return;
    }

    final dynamic printer = _printer;
    try {
      await printer.printQRcode(value, 200, 200, 1);
      await _printer.printNewLine();
      return;
    } catch (_) {
      // Some printer SDK builds may not expose QR API; fallback to plain text.
    }

    await _printer.printCustom('QR: $value', 1, 1);
    await _printer.printNewLine();
  }
}
