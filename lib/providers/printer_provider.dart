import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrinterProvider with ChangeNotifier {
  static const _lastPrinterKey = 'lastPrinterMac';

  List<BluetoothInfo> _availablePrinters = [];
  String _connectedMac = '';
  String _rememberedMac = '';
  bool _isScanning = false;
  bool _isConnected = false;

  List<BluetoothInfo> get availablePrinters => _availablePrinters;
  String get connectedMac => _connectedMac;

  /// Printer this device last used, reconnected to on startup.
  String get rememberedMac => _rememberedMac;

  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;

  /// Reconnects to the printer this device last used. The pairing is per
  /// device, so it lives in local preferences rather than the store profile.
  Future<void> restoreLastPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final mac = prefs.getString(_lastPrinterKey) ?? '';
    if (mac.isEmpty) return;
    _rememberedMac = mac;
    notifyListeners();
    await scanPrinters();
    await connectPrinter(mac);
  }

  Future<void> scanPrinters() async {
    _isScanning = true;
    notifyListeners();

    try {
      final List<BluetoothInfo> listResult =
          await PrintBluetoothThermal.pairedBluetooths;
      _availablePrinters = listResult;
    } catch (e) {
      debugPrint('Error scanning printers: $e');
      _availablePrinters = [];
    }

    _isScanning = false;
    notifyListeners();
  }

  Future<bool> connectPrinter(String macAddress) async {
    try {
      final bool result = await PrintBluetoothThermal.connect(
        macPrinterAddress: macAddress,
      );
      if (result) {
        _connectedMac = macAddress;
        _rememberedMac = macAddress;
        _isConnected = true;
        notifyListeners();
        await _remember(macAddress);
        return true;
      }
    } catch (e) {
      debugPrint('Error connecting printer: $e');
    }
    _isConnected = false;
    notifyListeners();
    return false;
  }

  /// Drops the connection but keeps the pairing, so the next launch still
  /// reconnects; use [forgetPrinter] to stop that.
  Future<void> disconnectPrinter() async {
    try {
      await PrintBluetoothThermal.disconnect;
      _connectedMac = '';
      _isConnected = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error disconnecting printer: $e');
    }
  }

  Future<void> forgetPrinter() async {
    await disconnectPrinter();
    _rememberedMac = '';
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastPrinterKey);
  }

  Future<bool> printBytes(List<int> bytes) async {
    if (!_isConnected) return false;
    try {
      final bool result = await PrintBluetoothThermal.writeBytes(bytes);
      return result;
    } catch (e) {
      debugPrint('Error printing bytes: $e');
      return false;
    }
  }

  Future<void> _remember(String macAddress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastPrinterKey, macAddress);
    } catch (e) {
      debugPrint('Could not remember the printer: $e');
    }
  }
}
