import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:image/image.dart' as img;
import '../models/order.dart';

class PrinterService {
  /// Generates the ESC/POS ticket (bytes) for a given CafeOrder.
  /// This can be sent to either a Bluetooth or Network printer.
  static Future<List<int>> generateBillTicket(CafeOrder order, {String? logoAssetPath}) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);
    List<int> bytes = [];

    // 1. Print Customizable Logo (if provided)
    if (logoAssetPath != null && logoAssetPath.isNotEmpty) {
      try {
        final ByteData data = await rootBundle.load(logoAssetPath);
        final Uint8List imageBytes = data.buffer.asUint8List();
        final img.Image? image = img.decodeImage(imageBytes);
        if (image != null) {
          // Resize image if necessary to fit the receipt
          img.Image resizedImage = img.copyResize(image, width: 200);
          bytes += generator.image(resizedImage);
        }
      } catch (e) {
        print("Error loading logo for print: $e");
      }
    }

    // 2. Header
    bytes += generator.text(
      'iCafe',
      styles: const PosStyles(
        align: PosAlign.center,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
      linesAfter: 1,
    );
    bytes += generator.text('123 Coffee Street, Cafe City', styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('Tel: +123456789', styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('Order ID: ${order.id}', styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('Date: ${order.timestamp.toString().substring(0, 16)}', styles: const PosStyles(align: PosAlign.center));
    bytes += generator.hr();

    // 3. Items
    bytes += generator.row([
      PosColumn(text: 'Item', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text: 'Qty', width: 2, styles: const PosStyles(bold: true, align: PosAlign.center)),
      PosColumn(text: 'Price', width: 4, styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]);

    for (var item in order.items) {
      bytes += generator.row([
        PosColumn(text: item.productName, width: 6),
        PosColumn(text: '${item.quantity}', width: 2, styles: const PosStyles(align: PosAlign.center)),
        PosColumn(text: 'Rs ${(item.price * item.quantity).toStringAsFixed(2)}', width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    bytes += generator.hr();

    // 4. Totals
    bytes += generator.row([
      PosColumn(text: 'TOTAL', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text: 'Rs ${order.grandTotal.toStringAsFixed(2)}', width: 6, styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]);
    
    // 5. Footer
    bytes += generator.feed(2);
    bytes += generator.text('Thank you for your visit!', styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.feed(2);
    bytes += generator.cut();

    return bytes;
  }
}
