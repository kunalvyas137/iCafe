import 'package:flutter_test/flutter_test.dart';
import 'package:icafe/models/product.dart';
import 'package:icafe/models/raw_material.dart';

Product _product({
  ProductType type = ProductType.mrp,
  double stock = 10,
  double reorderLevel = 0,
  bool isAvailable = true,
}) {
  return Product(
    id: 'p1',
    name: 'Cold Coffee',
    type: type,
    price: 120,
    gstRate: 5,
    isAvailable: isAvailable,
    currentStock: stock,
    reorderLevel: reorderLevel,
  );
}

void main() {
  test('a low-stock alert needs a reorder level to be set', () {
    expect(_product(stock: 2).isLowStock, isFalse);
    expect(_product(stock: 2, reorderLevel: 3).isLowStock, isTrue);
    expect(_product(stock: 5, reorderLevel: 3).isLowStock, isFalse);
  });

  test('sold out takes over from low stock at zero', () {
    final product = _product(stock: 0, reorderLevel: 3);
    expect(product.isSoldOut, isTrue);
    expect(product.isLowStock, isFalse);
  });

  test('in-house products never raise a stock alert of their own', () {
    final product = _product(
      type: ProductType.inHouse,
      stock: 0,
      reorderLevel: 5,
    );
    expect(product.isLowStock, isFalse);
    expect(product.isSoldOut, isFalse);
  });

  test('the reorder level round-trips and defaults to off', () {
    final restored = Product.fromMap(_product(reorderLevel: 4).toMap(), 'p1');
    expect(restored.reorderLevel, 4);

    final legacy = Product.fromMap({'name': 'Tea', 'type': 'mrp'}, 'p2');
    expect(legacy.reorderLevel, 0);
    expect(legacy.isLowStock, isFalse);
  });

  test('editing a product keeps the fields that were not touched', () {
    final updated = _product(reorderLevel: 4).copyWith(price: 140);
    expect(updated.price, 140);
    expect(updated.reorderLevel, 4);
    expect(updated.gstRate, 5);
    expect(updated.id, 'p1');
  });

  test('a raw material is low at or below its reorder level', () {
    RawMaterial material(double stock) => RawMaterial(
      id: 'm1',
      name: 'Milk',
      unit: 'l',
      currentStock: stock,
      reorderLevel: 5,
    );

    expect(material(5).isLowStock, isTrue);
    expect(material(4.9).isLowStock, isTrue);
    expect(material(5.1).isLowStock, isFalse);
    expect(material(0).isOutOfStock, isTrue);
  });
}
