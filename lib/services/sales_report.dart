import 'package:intl/intl.dart';

import '../models/order.dart';

class PaymentBreakdownRow {
  const PaymentBreakdownRow({
    required this.method,
    required this.orderCount,
    required this.total,
  });

  final PaymentMethod method;
  final int orderCount;
  final double total;
}

class GstBreakdownRow {
  const GstBreakdownRow({
    required this.rate,
    required this.taxableValue,
    required this.gstAmount,
  });

  final double rate;
  final double taxableValue;
  final double gstAmount;

  /// Intra-state sales are split evenly between CGST and SGST on the return.
  double get halfGst => gstAmount / 2;
}

class DailySalesRow {
  const DailySalesRow({
    required this.day,
    required this.orderCount,
    required this.total,
  });

  final DateTime day;
  final int orderCount;
  final double total;
}

class TopItemRow {
  const TopItemRow({
    required this.name,
    required this.quantity,
    required this.total,
  });

  final String name;
  final int quantity;
  final double total;
}

/// Everything the reports screen shows, derived in one pass so the figures on
/// screen and in the exports can never disagree.
class SalesReport {
  SalesReport({
    required this.orderCount,
    required this.netSales,
    required this.totalGst,
    required this.grossSales,
    required this.cancelledCount,
    required this.cancelledValue,
    required this.byPaymentMethod,
    required this.byGstRate,
    required this.byDay,
    required this.byHour,
    required this.topItems,
  });

  final int orderCount;

  /// Revenue before tax.
  final double netSales;
  final double totalGst;

  /// What was actually collected, tax included.
  final double grossSales;

  final int cancelledCount;
  final double cancelledValue;

  final List<PaymentBreakdownRow> byPaymentMethod;
  final List<GstBreakdownRow> byGstRate;
  final List<DailySalesRow> byDay;

  /// Gross sales for hours 0-23; hours with no sales are 0.
  final List<double> byHour;

  final List<TopItemRow> topItems;

  double get averageOrderValue => orderCount == 0 ? 0 : grossSales / orderCount;

  bool get isEmpty => orderCount == 0;

  /// Cancelled orders are counted separately and never as revenue.
  factory SalesReport.fromOrders(Iterable<CafeOrder> orders) {
    var orderCount = 0;
    var netSales = 0.0;
    var totalGst = 0.0;
    var grossSales = 0.0;
    var cancelledCount = 0;
    var cancelledValue = 0.0;

    final payments = <PaymentMethod, List<double>>{};
    final gstTaxable = <double, double>{};
    final gstAmounts = <double, double>{};
    final days = <DateTime, List<double>>{};
    final hours = List<double>.filled(24, 0);
    final itemQty = <String, int>{};
    final itemTotal = <String, double>{};

    for (final order in orders) {
      if (!order.countsTowardsSales) {
        if (order.isCancelled) {
          cancelledCount++;
          cancelledValue += order.grandTotal;
        }
        continue;
      }

      orderCount++;
      netSales += order.subtotal;
      totalGst += order.totalGst;
      grossSales += order.grandTotal;

      payments.putIfAbsent(order.paymentMethod, () => []).add(order.grandTotal);

      for (final item in order.items) {
        gstTaxable.update(
          item.gstRate,
          (value) => value + item.totalWithoutGst,
          ifAbsent: () => item.totalWithoutGst,
        );
        gstAmounts.update(
          item.gstRate,
          (value) => value + item.gstAmount,
          ifAbsent: () => item.gstAmount,
        );
        itemQty.update(
          item.productName,
          (value) => value + item.quantity,
          ifAbsent: () => item.quantity,
        );
        itemTotal.update(
          item.productName,
          (value) => value + item.totalWithGst,
          ifAbsent: () => item.totalWithGst,
        );
      }

      final day = DateTime(
        order.timestamp.year,
        order.timestamp.month,
        order.timestamp.day,
      );
      days.putIfAbsent(day, () => []).add(order.grandTotal);
      hours[order.timestamp.hour] += order.grandTotal;
    }

    final byPaymentMethod =
        payments.entries
            .map(
              (entry) => PaymentBreakdownRow(
                method: entry.key,
                orderCount: entry.value.length,
                total: entry.value.fold(0.0, (sum, value) => sum + value),
              ),
            )
            .toList()
          ..sort((a, b) => b.total.compareTo(a.total));

    final byGstRate =
        gstAmounts.keys
            .map(
              (rate) => GstBreakdownRow(
                rate: rate,
                taxableValue: gstTaxable[rate] ?? 0,
                gstAmount: gstAmounts[rate] ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => a.rate.compareTo(b.rate));

    final byDay =
        days.entries
            .map(
              (entry) => DailySalesRow(
                day: entry.key,
                orderCount: entry.value.length,
                total: entry.value.fold(0.0, (sum, value) => sum + value),
              ),
            )
            .toList()
          ..sort((a, b) => a.day.compareTo(b.day));

    final topItems =
        itemQty.keys
            .map(
              (name) => TopItemRow(
                name: name,
                quantity: itemQty[name] ?? 0,
                total: itemTotal[name] ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => b.quantity.compareTo(a.quantity));

    return SalesReport(
      orderCount: orderCount,
      netSales: netSales,
      totalGst: totalGst,
      grossSales: grossSales,
      cancelledCount: cancelledCount,
      cancelledValue: cancelledValue,
      byPaymentMethod: byPaymentMethod,
      byGstRate: byGstRate,
      byDay: byDay,
      byHour: hours,
      topItems: topItems,
    );
  }

  String toCsv() {
    final dayFormat = DateFormat('yyyy-MM-dd');
    final rows = <List<String>>[
      ['Section', 'Label', 'Orders', 'Taxable value', 'GST', 'Total'],
      [
        'Summary',
        'All sales',
        '$orderCount',
        _money(netSales),
        _money(totalGst),
        _money(grossSales),
      ],
      [
        'Summary',
        'Cancelled',
        '$cancelledCount',
        '',
        '',
        _money(cancelledValue),
      ],
      for (final row in byPaymentMethod)
        [
          'Payment',
          row.method.name,
          '${row.orderCount}',
          '',
          '',
          _money(row.total),
        ],
      for (final row in byGstRate)
        [
          'GST',
          '${_rate(row.rate)}%',
          '',
          _money(row.taxableValue),
          _money(row.gstAmount),
          _money(row.taxableValue + row.gstAmount),
        ],
      for (final row in byDay)
        [
          'Day',
          dayFormat.format(row.day),
          '${row.orderCount}',
          '',
          '',
          _money(row.total),
        ],
      for (var hour = 0; hour < byHour.length; hour++)
        if (byHour[hour] > 0)
          [
            'Hour',
            '${hour.toString().padLeft(2, '0')}:00',
            '',
            '',
            '',
            _money(byHour[hour]),
          ],
      for (final row in topItems)
        ['Item', row.name, '${row.quantity}', '', '', _money(row.total)],
    ];

    return rows.map((row) => row.map(_escapeCsv).join(',')).join('\n');
  }

  static String _money(double value) => value.toStringAsFixed(2);

  static String _rate(double rate) =>
      rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : '$rate';

  static String _escapeCsv(String value) {
    if (value.contains(RegExp('[",\n]'))) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
