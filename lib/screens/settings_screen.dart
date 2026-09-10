import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/printer_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Start scanning when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PrinterProvider>().scanPrinters();
    });
  }

  @override
  Widget build(BuildContext context) {
    final printerProvider = context.watch<PrinterProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bluetooth POS Printers',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: printerProvider.isScanning
                      ? null
                      : () => printerProvider.scanPrinters(),
                  icon: const Icon(Icons.refresh),
                  label: Text(printerProvider.isScanning ? 'Scanning...' : 'Scan for Printers'),
                ),
                const SizedBox(width: 16),
                if (printerProvider.isConnected)
                  ElevatedButton.icon(
                    onPressed: () => printerProvider.disconnectPrinter(),
                    icon: const Icon(Icons.bluetooth_disabled),
                    label: const Text('Disconnect'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (printerProvider.isConnected)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[300]!),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      'Connected to: ${printerProvider.connectedMac}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                elevation: 4,
                child: printerProvider.availablePrinters.isEmpty
                    ? const Center(child: Text('No printers found. Make sure Bluetooth is on and paired.'))
                    : ListView.builder(
                        itemCount: printerProvider.availablePrinters.length,
                        itemBuilder: (context, index) {
                          final printer = printerProvider.availablePrinters[index];
                          final isThisConnected = printerProvider.connectedMac == printer.macAdress;

                          return ListTile(
                            leading: const Icon(Icons.print),
                            title: Text(printer.name.isEmpty ? 'Unknown Device' : printer.name),
                            subtitle: Text(printer.macAdress),
                            trailing: isThisConnected
                                ? const Chip(
                                    label: Text('Connected'),
                                    backgroundColor: Colors.green,
                                    labelStyle: TextStyle(color: Colors.white),
                                  )
                                : ElevatedButton(
                                    onPressed: () => printerProvider.connectPrinter(printer.macAdress),
                                    child: const Text('Connect'),
                                  ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
