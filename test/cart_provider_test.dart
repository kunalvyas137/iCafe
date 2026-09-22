import 'package:flutter_test/flutter_test.dart';
import 'package:icafe/models/product.dart';
import 'package:icafe/providers/cart_provider.dart';

Product _product({
  String id = 'p1',
  String name = 'Latte',
  ProductType type = ProductType.mrp,
  double price = 100,
  double gstRate = 5,
  bool isAvailable = true,
  double currentStock = 10,
  bool isTaxInclusive = false,
}) {
  return Product(
    id: id,
    name: name,
    type: type,
    price: price,
    gstRate: gstRate,
    isAvailable: isAvailable,
    currentStock: currentStock,
    isTaxInclusive: isTaxInclusive,
  );
}

void main() {
  test('adding the same product twice increments the line quantity', () {
    final cart = CartProvider();
    expect(cart.addProduct(_product()), isNull);
    expect(cart.addProduct(_product()), isNull);

    expect(cart.items, hasLength(1));
    expect(cart.quantityOf('p1'), 2);
  });

  test('totals include per-item GST (exclusive)', () {
    final cart = CartProvider();
    cart.addProduct(_product(price: 100, gstRate: 5, isTaxInclusive: false));
    cart.addProduct(_product(id: 'p2', name: 'Bun', price: 50, gstRate: 12, isTaxInclusive: false));

    expect(cart.subtotal, 150);
    expect(cart.totalGst, closeTo(11, 0.0001));
    expect(cart.grandTotal, closeTo(161, 0.0001));
  });

  test('totals include per-item GST (inclusive)', () {
    final cart = CartProvider();
    cart.addProduct(_product(price: 100, gstRate: 5, isTaxInclusive: true));
    cart.addProduct(_product(id: 'p2', name: 'Bun', price: 50, gstRate: 12, isTaxInclusive: true));

    // 100 / 1.05 = 95.238
    // 50 / 1.12 = 44.642
    // totalWithoutGst = 139.88
    // gstAmount = 10.119
    // grandTotal = 150
    expect(cart.subtotal, closeTo(139.8809, 0.0001));
    expect(cart.totalGst, closeTo(10.1190, 0.0001));
    expect(cart.grandTotal, closeTo(150, 0.0001));
  });

  test('cannot add more than the tracked stock', () {
    final cart = CartProvider();
    cart.addProduct(_product(currentStock: 1));

    expect(cart.addProduct(_product(currentStock: 1)), contains('out of stock'));
    expect(cart.quantityOf('p1'), 1);
  });

  test('unavailable products are rejected', () {
    final cart = CartProvider();
    expect(cart.addProduct(_product(isAvailable: false)), contains('unavailable'));
    expect(cart.isEmpty, isTrue);
  });

  test('in-house products are not limited by product stock', () {
    final cart = CartProvider();
    final samosa = _product(
      id: 'p9',
      name: 'Samosa',
      type: ProductType.inHouse,
      currentStock: 0,
    );

    expect(cart.addProduct(samosa), isNull);
    expect(cart.quantityOf('p9'), 1);
  });

  test('decrement removes the line at zero', () {
    final cart = CartProvider();
    cart.addProduct(_product());
    cart.decrementQuantity('p1');

    expect(cart.isEmpty, isTrue);
  });

  test('a removed line can be restored at its original position', () {
    final cart = CartProvider();
    cart.addProduct(_product(id: 'a', name: 'A'));
    cart.addProduct(_product(id: 'b', name: 'B'));
    cart.addProduct(_product(id: 'c', name: 'C'));

    final removed = cart.removeProduct('b');
    expect(removed, isNotNull);
    expect(cart.items.map((i) => i.productId), ['a', 'c']);

    cart.restoreItem(removed!);
    expect(cart.items.map((i) => i.productId), ['a', 'b', 'c']);
  });

  test('clearing returns the items so the clear can be undone', () {
    final cart = CartProvider();
    cart.addProduct(_product());
    final cleared = cart.clearCart();

    expect(cart.isEmpty, isTrue);
    cart.restoreItems(cleared);
    expect(cart.quantityOf('p1'), 1);
  });

  test('stockIssues reports stale lines against the live catalogue', () {
    final cart = CartProvider();
    cart.addProduct(_product(id: 'a', name: 'A', currentStock: 5), quantity: 3);
    cart.addProduct(_product(id: 'b', name: 'B', currentStock: 5));

    final issues = cart.stockIssues({
      'a': _product(id: 'a', name: 'A', currentStock: 1),
    });

    expect(issues, hasLength(2));
    expect(issues.first, contains('only 1 left'));
    expect(issues.last, contains('no longer in the catalogue'));
  });

  test('updateItemModifiers updates modifiers and notes on a cart line', () {
    final cart = CartProvider();
    cart.addProduct(_product());

    expect(cart.items.first.modifiers, isEmpty);
    expect(cart.items.first.notes, isNull);

    cart.updateItemModifiers(
      index: 0,
      modifiers: ['Oat Milk', 'Less Sugar (50%)'],
      notes: 'Warm well',
    );

    expect(cart.items.first.modifiers, ['Oat Milk', 'Less Sugar (50%)']);
    expect(cart.items.first.notes, 'Warm well');
  });

  test('items with different modifiers are tracked as distinct lines', () {
    final cart = CartProvider();
    final latte = _product(id: 'latte', name: 'Latte', currentStock: 5);

    // Add 1 Latte with Oat Milk
    cart.addProduct(latte, modifiers: ['Oat Milk']);
    // Add 1 Latte with Almond Milk
    cart.addProduct(latte, modifiers: ['Almond Milk']);

    expect(cart.items, hasLength(2));
    expect(cart.quantityOf('latte'), 2);
    expect(cart.items[0].modifiers, ['Oat Milk']);
    expect(cart.items[1].modifiers, ['Almond Milk']);

    // Adding matching modifiers increments the matching line
    cart.addProduct(latte, modifiers: ['Oat Milk']);
    expect(cart.items, hasLength(2));
    expect(cart.items[0].quantity, 2);
    expect(cart.items[1].quantity, 1);
    expect(cart.quantityOf('latte'), 3);
  });

  test('index-based increment, decrement, and removal operate on the correct line', () {
    final cart = CartProvider();
    final coffee = _product(id: 'c1', name: 'Coffee', currentStock: 10);
    cart.addProduct(coffee, modifiers: ['Oat Milk']);
    cart.addProduct(coffee, modifiers: ['No Sugar']);

    cart.incrementQuantityAt(1);
    expect(cart.items[1].quantity, 2);
    expect(cart.items[0].quantity, 1);

    cart.decrementQuantityAt(1);
    expect(cart.items[1].quantity, 1);

    final removed = cart.removeItemAt(0);
    expect(removed?.item.modifiers, ['Oat Milk']);
    expect(cart.items, hasLength(1));
    expect(cart.items[0].modifiers, ['No Sugar']);
  });
}
