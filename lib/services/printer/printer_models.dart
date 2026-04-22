class PrinterDeviceInfo {
  final String name;
  final String address;

  const PrinterDeviceInfo({required this.name, required this.address});

  String get label => '$name ($address)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PrinterDeviceInfo && other.address == address);

  @override
  int get hashCode => address.hashCode;
}