import 'package:flutter_test/flutter_test.dart';
import 'package:icafe/models/order.dart';
import 'package:icafe/services/sales_report.dart';

CafeOrder _order({
  required DateTime at,
  PaymentMethod method = PaymentMethod.cash,
  OrderStatus status = OrderStatus.completed,
  List<OrderItem>? items,
}) {
  final lines =
      items ??
      [
        OrderItem(
          productId: 'p1',
          productName: 'Cold Coffee',
          price: 100,
          quantity: 1,
          gstRate: 5,
        ),
      ];
  final subtotal = lines.fold(0.0, (sum, item) => sum + item.totalWithoutGst);
  final gst = lines.fold(0.0, (sum, item) => sum + item.gstAmount);

  return CafeOrder(
    id: 'o${at.microsecondsSinceEpoch}',
    timestamp: at,
    items: lines,
    subtotal: subtotal,
    totalGst: gst,
    grandTotal: subtotal + gst,
    paymentMethod: method,
    status: status,
  );
}

void main() {
  test('cancelled orders are reported separately from revenue', () {
    final report = SalesReport.fromOrders([
      _order(at: DateTime(2026, 1, 5, 10)),
      _order(at: DateTime(2026, 1, 5, 11), status: OrderStatus.cancelled),
      _order(at: DateTime(2026, 1, 5, 12), status: OrderStatus.pending),
    ]);

    expect(report.orderCount, 1);
    expect(report.grossSales, closeTo(105, 0.001));
    expect(report.cancelledCount, 1);
    expect(report.cancelledValue, closeTo(105, 0.001));
  });

  test('payment rows are totalled and ordered by value', () {
    final report = SalesReport.fromOrders([
      _order(at: DateTime(2026, 1, 5, 10)),
      _order(at: DateTime(2026, 1, 5, 11), method: PaymentMethod.upi),
      _order(at: DateTime(2026, 1, 5, 12), method: PaymentMethod.upi),
    ]);

    expect(report.byPaymentMethod.first.method, PaymentMethod.upi);
    expect(report.byPaymentMethod.first.orderCount, 2);
    expect(report.byPaymentMethod.first.total, closeTo(210, 0.001));
    expect(report.byPaymentMethod.last.method, PaymentMethod.cash);
  });

  test('GST is grouped by rate and split into CGST/SGST', () {
    final report = SalesReport.fromOrders([
      _order(
        at: DateTime(2026, 1, 5, 10),
        items: [
          OrderItem(
            productId: 'p1',
            productName: 'Cold Coffee',
            price: 100,
            quantity: 2,
            gstRate: 5,
          ),
          OrderItem(
            productId: 'p2',
            productName: 'Chips',
            price: 50,
            quantity: 1,
            gstRate: 12,
          ),
        ],
      ),
    ]);

    expect(report.byGstRate.map((row) => row.rate), [5, 12]);
    expect(report.byGstRate.first.taxableValue, closeTo(200, 0.001));
    expect(report.byGstRate.first.gstAmount, closeTo(10, 0.001));
    expect(report.byGstRate.first.halfGst, closeTo(5, 0.001));
    expect(report.totalGst, closeTo(16, 0.001));
  });

  test('sales are bucketed by calendar day and by hour of day', () {
    final report = SalesReport.fromOrders([
      _order(at: DateTime(2026, 1, 5, 9, 30)),
      _order(at: DateTime(2026, 1, 5, 9, 45)),
      _order(at: DateTime(2026, 1, 6, 18)),
    ]);

    expect(report.byDay.map((row) => row.day), [
      DateTime(2026, 1, 5),
      DateTime(2026, 1, 6),
    ]);
    expect(report.byDay.first.orderCount, 2);
    expect(report.byHour.length, 24);
    expect(report.byHour[9], closeTo(210, 0.001));
    expect(report.byHour[18], closeTo(105, 0.001));
    expect(report.byHour[3], 0);
  });

  test('top items rank by quantity sold', () {
    final report = SalesReport.fromOrders([
      _order(
        at: DateTime(2026, 1, 5, 10),
        items: [
          OrderItem(
            productId: 'p1',
            productName: 'Cold Coffee',
            price: 100,
            quantity: 1,
            gstRate: 5,
          ),
          OrderItem(
            productId: 'p2',
            productName: 'Chips',
            price: 20,
            quantity: 4,
            gstRate: 12,
          ),
        ],
      ),
    ]);

    expect(report.topItems.first.name, 'Chips');
    expect(report.topItems.first.quantity, 4);
    expect(report.topItems.first.total, closeTo(89.6, 0.001));
  });

  test('an empty period reports no sales rather than dividing by zero', () {
    final report = SalesReport.fromOrders(const <CafeOrder>[]);
    expect(report.isEmpty, isTrue);
    expect(report.averageOrderValue, 0);
    expect(report.toCsv(), contains('Summary,All sales,0'));
  });

  test('CSV export covers every section and quotes risky item names', () {
    final report = SalesReport.fromOrders([
      _order(
        at: DateTime(2026, 1, 5, 10),
        method: PaymentMethod.upi,
        items: [
          OrderItem(
            productId: 'p1',
            productName: 'Coffee, large',
            price: 100,
            quantity: 1,
            gstRate: 5,
          ),
        ],
      ),
    ]);

    final csv = report.toCsv();
    expect(csv.split('\n').first, startsWith('Section,Label,Orders'));
    expect(csv, contains('Payment,upi,1,,,105.00'));
    expect(csv, contains('GST,5%,,100.00,5.00,105.00'));
    expect(csv, contains('Day,2026-01-05,1,,,105.00'));
    expect(csv, contains('Hour,10:00,,,,105.00'));
    expect(csv, contains('Item,"Coffee, large",1,,,105.00'));
  });
}
