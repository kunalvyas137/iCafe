import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class PrinterProvider with ChangeNotifier {
  List<BluetoothInfo> _availablePrinters = [];
  String _connectedMac = '';
  bool _isScanning = false;
  bool _isConnected = false;

  List<BluetoothInfo> get availablePrinters => _availablePrinters;
  String get connectedMac => _connectedMac;
  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;

  Future<void> scanPrinters() async {
    _isScanning = true;
    notifyListeners();

    try {
      final List<BluetoothInfo> listResult = await PrintBluetoothThermal.pairedBluetooths;
      _availablePrinters = listResult;
    } catch (e) {
      print("Error scanning printers: $e");
      _availablePrinters = [];
    }

    _isScanning = false;
    notifyListeners();
  }

  Future<bool> connectPrinter(String macAddress) async {
    try {
      final bool result = await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
      if (result) {
        _connectedMac = macAddress;
        _isConnected = true;
        notifyListeners();
        return true;
      }
    } catch (e) {
      print("Error connecting printer: $e");
    }
    _isConnected = false;
    notifyListeners();
    return false;
  }

  Future<void> disconnectPrinter() async {
    try {
      await PrintBluetoothThermal.disconnect;
      _connectedMac = '';
      _isConnected = false;
      notifyListeners();
    } catch (e) {
      print("Error disconnecting printer: $e");
    }
  }

  Future<bool> printBytes(List<int> bytes) async {
    if (!_isConnected) return false;
    try {
      final bool result = await PrintBluetoothThermal.writeBytes(bytes);
      return result;
    } catch (e) {
      print("Error printing bytes: $e");
      return false;
    }
  }
}
