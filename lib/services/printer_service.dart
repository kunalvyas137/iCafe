import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:image/image.dart' as img;
import '../models/order.dart';
import '../models/store_settings.dart';
import 'sales_report.dart';

class PrinterService {
  /// Generates the ESC/POS ticket (bytes) for a given CafeOrder.
  /// This can be sent to either a Bluetooth or Network printer.
  static Future<List<int>> generateBillTicket(
    CafeOrder order, {
    StoreSettings store = StoreSettings.defaults,
    String? logoAssetPath,
    bool reprint = false,
  }) async {
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
        debugPrint('Error loading logo for print: $e');
      }
    }

    // 2. Header
    bytes += generator.text(
      store.storeName,
      styles: const PosStyles(
        align: PosAlign.center,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
      linesAfter: 1,
    );
    for (final line in [store.addressLine1, store.addressLine2]) {
      if (line.trim().isNotEmpty) {
        bytes += generator.text(
          line,
          styles: const PosStyles(align: PosAlign.center),
        );
      }
    }
    if (store.phone.trim().isNotEmpty) {
      bytes += generator.text(
        'Tel: ${store.phone}',
        styles: const PosStyles(align: PosAlign.center),
      );
    }
    if (store.gstin.trim().isNotEmpty) {
      bytes += generator.text(
        'GSTIN: ${store.gstin}',
        styles: const PosStyles(align: PosAlign.center),
      );
    }
    if (order.status == OrderStatus.cancelled) {
      bytes += generator.text(
        '*** CANCELLED ***',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
    } else if (reprint) {
      bytes += generator.text(
        '*** REPRINT ***',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
    }
    bytes += generator.text(
      'Order ${order.displayNumber}',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.text(
      'Date: ${order.timestamp.toString().substring(0, 16)}',
      styles: const PosStyles(align: PosAlign.center),
    );
    if (order.tableLabel != null) {
      bytes += generator.text(
        'Table: ${order.tableLabel}',
        styles: const PosStyles(align: PosAlign.center),
      );
    }
    if (order.customerName != null) {
      bytes += generator.text(
        'Customer: ${order.customerName}',
        styles: const PosStyles(align: PosAlign.center),
      );
    }
    bytes += generator.hr();

    // 3. Items
    bytes += generator.row([
      PosColumn(text: 'Item', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(
        text: 'Qty',
        width: 2,
        styles: const PosStyles(bold: true, align: PosAlign.center),
      ),
      PosColumn(
        text: 'Price',
        width: 4,
        styles: const PosStyles(bold: true, align: PosAlign.right),
      ),
    ]);

    for (var item in order.items) {
      bytes += generator.row([
        PosColumn(text: item.productName, width: 6),
        PosColumn(
          text: '${item.quantity}',
          width: 2,
          styles: const PosStyles(align: PosAlign.center),
        ),
        PosColumn(
          text: 'Rs ${item.totalWithoutGst.toStringAsFixed(2)}',
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      if (item.modifiers.isNotEmpty) {
        bytes += generator.text(
          '   >> ${item.modifiers.join(", ")}',
          styles: const PosStyles(align: PosAlign.left),
        );
      }
      if (item.notes != null && item.notes!.trim().isNotEmpty) {
        bytes += generator.text(
          '   Note: ${item.notes!}',
          styles: const PosStyles(align: PosAlign.left),
        );
      }
    }
    bytes += generator.hr();

    // 4. Totals
    bytes += _amountRow(generator, 'Subtotal', order.subtotal);
    final rates = order.gstByRate.keys.toList()..sort();
    for (final rate in rates) {
      bytes += _amountRow(
        generator,
        'GST @ ${rate.toStringAsFixed(rate.truncateToDouble() == rate ? 0 : 2)}%',
        order.gstByRate[rate]!,
      );
    }
    bytes += generator.row([
      PosColumn(text: 'TOTAL', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(
        text: 'Rs ${order.grandTotal.toStringAsFixed(2)}',
        width: 6,
        styles: const PosStyles(bold: true, align: PosAlign.right),
      ),
    ]);
    bytes += _amountRow(
      generator,
      'Paid by',
      0,
      textValue: _paymentLabel(order.paymentMethod),
    );
    final tendered = order.cashTendered;
    if (tendered != null) {
      bytes += _amountRow(generator, 'Cash', tendered);
      bytes += _amountRow(generator, 'Change', order.changeDue ?? 0);
    }

    // 5. Footer
    if (order.notes != null) {
      bytes += generator.hr();
      bytes += generator.text('Note: ${order.notes}');
    }
    bytes += generator.feed(2);
    if (store.receiptFooter.trim().isNotEmpty) {
      bytes += generator.text(
        store.receiptFooter,
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
    }
    bytes += generator.feed(2);
    bytes += generator.cut();

    return bytes;
  }

  /// End-of-day summary ticket: totals, payment split and GST for [label].
  static Future<List<int>> generateSalesReportTicket(
    SalesReport report, {
    required String label,
    StoreSettings store = StoreSettings.defaults,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);
    List<int> bytes = [];

    bytes += generator.text(
      store.storeName,
      styles: const PosStyles(
        align: PosAlign.center,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );
    bytes += generator.text(
      'SALES REPORT',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.text(
      label,
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.hr();

    void row(String left, String right, {bool bold = false}) {
      bytes += generator.row([
        PosColumn(
          text: left,
          width: 7,
          styles: PosStyles(bold: bold),
        ),
        PosColumn(
          text: right,
          width: 5,
          styles: PosStyles(align: PosAlign.right, bold: bold),
        ),
      ]);
    }

    row('Orders', '${report.orderCount}');
    row('Net sales', report.netSales.toStringAsFixed(2));
    row('GST', report.totalGst.toStringAsFixed(2));
    row('Gross sales', report.grossSales.toStringAsFixed(2), bold: true);
    row('Average order', report.averageOrderValue.toStringAsFixed(2));
    if (report.cancelledCount > 0) {
      row(
        'Cancelled (${report.cancelledCount})',
        report.cancelledValue.toStringAsFixed(2),
      );
    }

    if (report.byPaymentMethod.isNotEmpty) {
      bytes += generator.hr();
      bytes += generator.text('Payments', styles: const PosStyles(bold: true));
      for (final payment in report.byPaymentMethod) {
        row(
          '${payment.method.name.toUpperCase()} (${payment.orderCount})',
          payment.total.toStringAsFixed(2),
        );
      }
    }

    if (report.byGstRate.isNotEmpty) {
      bytes += generator.hr();
      bytes += generator.text(
        'GST summary',
        styles: const PosStyles(bold: true),
      );
      for (final gst in report.byGstRate) {
        row(
          'GST ${gst.rate.toStringAsFixed(0)}% on ${gst.taxableValue.toStringAsFixed(2)}',
          gst.gstAmount.toStringAsFixed(2),
        );
      }
    }

    bytes += generator.hr();
    bytes += generator.text(
      'Printed ${DateTime.now().toString().substring(0, 16)}',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.feed(2);
    bytes += generator.cut();

    return bytes;
  }

  /// Short ticket used by the Settings screen to confirm a printer works.
  static Future<List<int>> generateTestTicket({
    StoreSettings store = StoreSettings.defaults,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);
    List<int> bytes = [];

    bytes += generator.text(
      store.storeName,
      styles: const PosStyles(
        align: PosAlign.center,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
      linesAfter: 1,
    );
    bytes += generator.text(
      'Printer test page',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.text(
      DateTime.now().toString().substring(0, 19),
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.hr();
    bytes += generator.text(
      'If you can read this, the printer is ready.',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.feed(2);
    bytes += generator.cut();

    return bytes;
  }

  static List<int> _amountRow(
    Generator generator,
    String label,
    double amount, {
    String? textValue,
  }) {
    return generator.row([
      PosColumn(text: label, width: 6),
      PosColumn(
        text: textValue ?? 'Rs ${amount.toStringAsFixed(2)}',
        width: 6,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
  }

  static String _paymentLabel(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.upi:
        return 'UPI';
      case PaymentMethod.card:
        return 'Card';
      case PaymentMethod.sodexo:
        return 'Sodexo';
      case PaymentMethod.other:
        return 'Other';
    }
  }
}
