import 'package:flutter_test/flutter_test.dart';
import 'package:icafe/models/order.dart';
import 'package:icafe/services/order_service.dart';

OrderItem _item({
  String id = 'p1',
  String name = 'Latte',
  double price = 100,
  int quantity = 1,
  double gstRate = 5,
}) {
  return OrderItem(
    productId: id,
    productName: name,
    price: price,
    quantity: quantity,
    gstRate: gstRate,
  );
}

CafeOrder _order({
  int orderNumber = 14,
  double? cashTendered,
  List<OrderItem>? items,
  PaymentMethod method = PaymentMethod.cash,
}) {
  final lines = items ?? [_item()];
  final subtotal = lines.fold<double>(
    0,
    (total, item) => total + item.totalWithoutGst,
  );
  final gst = lines.fold<double>(0, (total, item) => total + item.gstAmount);
  return CafeOrder(
    id: 'abc123',
    timestamp: DateTime(2026, 9, 10, 14, 30),
    items: lines,
    subtotal: subtotal,
    totalGst: gst,
    grandTotal: subtotal + gst,
    paymentMethod: method,
    status: OrderStatus.completed,
    orderNumber: orderNumber,
    dayKey: '20260910',
    cashTendered: cashTendered,
  );
}

void main() {
  test('the daily sequence is zero-padded for the receipt', () {
    expect(_order(orderNumber: 14).displayNumber, '#014');
  });

  test('orders written before daily numbering fall back to the doc id', () {
    expect(_order(orderNumber: 0).displayNumber, '#abc123');
  });

  test('change is only computed when cash was tendered', () {
    expect(_order().changeDue, isNull);
    expect(_order(cashTendered: 200).changeDue, closeTo(95, 0.0001));
  });

  test('change never goes negative', () {
    expect(_order(cashTendered: 10).changeDue, 0);
  });

  test('GST is grouped by rate for the tax summary', () {
    final order = _order(
      items: [
        _item(price: 100, gstRate: 5),
        _item(id: 'p2', name: 'Tea', price: 100, gstRate: 5),
        _item(id: 'p3', name: 'Cake', price: 200, gstRate: 18),
      ],
    );

    expect(order.gstByRate[5], closeTo(10, 0.0001));
    expect(order.gstByRate[18], closeTo(36, 0.0001));
  });

  test('the new fields survive a Firestore round-trip', () {
    final order = CafeOrder(
      id: 'abc123',
      timestamp: DateTime(2026, 9, 10, 14, 30),
      items: [_item()],
      subtotal: 100,
      totalGst: 5,
      grandTotal: 105,
      paymentMethod: PaymentMethod.upi,
      status: OrderStatus.completed,
      orderNumber: 7,
      dayKey: '20260910',
      notes: 'No sugar',
      tableLabel: '4',
      customerName: 'Asha',
      cashierId: 'uid-1',
    );

    final restored = CafeOrder.fromMap(order.toMap(), 'abc123');

    expect(restored.orderNumber, 7);
    expect(restored.dayKey, '20260910');
    expect(restored.notes, 'No sugar');
    expect(restored.tableLabel, '4');
    expect(restored.customerName, 'Asha');
    expect(restored.cashierId, 'uid-1');
    expect(restored.paymentMethod, PaymentMethod.upi);
    expect(restored.cashTendered, isNull);
  });

  test('only completed orders count towards sales totals', () {
    final completed = _order();
    expect(completed.countsTowardsSales, isTrue);
    expect(completed.isCancelled, isFalse);

    final cancelled = CafeOrder.fromMap({
      ...completed.toMap(),
      'status': 'cancelled',
    }, completed.id);
    expect(cancelled.countsTowardsSales, isFalse);
    expect(cancelled.isCancelled, isTrue);
  });

  test('the void audit trail round-trips', () {
    final base = _order();
    final cancelled = CafeOrder(
      id: base.id,
      timestamp: base.timestamp,
      items: base.items,
      subtotal: base.subtotal,
      totalGst: base.totalGst,
      grandTotal: base.grandTotal,
      paymentMethod: base.paymentMethod,
      status: OrderStatus.cancelled,
      orderNumber: base.orderNumber,
      dayKey: base.dayKey,
      cancelledAt: DateTime(2026, 9, 10, 15),
      cancelledBy: 'uid-1',
      cancelReason: 'Wrong item rung up',
    );

    final restored = CafeOrder.fromMap(cancelled.toMap(), base.id);

    expect(restored.status, OrderStatus.cancelled);
    expect(restored.cancelledAt, DateTime(2026, 9, 10, 15));
    expect(restored.cancelledBy, 'uid-1');
    expect(restored.cancelReason, 'Wrong item rung up');
  });

  test('the counter key buckets orders by local calendar day', () {
    expect(OrderService.dayKeyFor(DateTime(2026, 1, 5, 23, 59)), '20260105');
    expect(OrderService.dayKeyFor(DateTime(2026, 12, 31)), '20261231');
  });
}
