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

  test('unified product model defaults and round-trips correctly', () {
    // 1. Raw material defaults
    final ingredient = Product(
      id: 'm1',
      name: 'Sugar',
      type: ProductType.rawMaterial,
      unit: 'kg',
      currentStock: 10,
    );
    expect(ingredient.isSellable, isFalse);
    expect(ingredient.isIngredient, isTrue);
    expect(ingredient.tracksStock, isTrue);

    // 2. Direct MRP resale defaults
    final drink = Product(
      id: 'p2',
      name: 'Red Bull',
      type: ProductType.mrp,
      unit: 'can',
      price: 125,
      currentStock: 24,
      costPrice: 85,
    );
    expect(drink.isSellable, isTrue);
    expect(drink.isIngredient, isFalse);
    expect(drink.tracksStock, isTrue);
    expect(drink.costPrice, 85);

    // 3. Round-trip serialization
    final map = drink.toMap();
    final restored = Product.fromMap(map, 'p2');
    expect(restored.name, 'Red Bull');
    expect(restored.unit, 'can');
    expect(restored.costPrice, 85);
    expect(restored.isSellable, isTrue);
    expect(restored.isIngredient, isFalse);

    // 4. Backward compatibility from legacy map without new fields
    final legacyMap = {
      'name': 'Espresso Beans',
      'type': 'rawMaterial',
      'currentStock': 5.0,
      'unit': 'kg',
    };
    final legacyProduct = Product.fromMap(legacyMap, 'rm1');
    expect(legacyProduct.isSellable, isFalse);
    expect(legacyProduct.isIngredient, isTrue);
    expect(legacyProduct.tracksStock, isTrue);
  });

  test('product category round-trips and fallback heuristic classifies items', () {
    final custom = Product(
      id: 'c1',
      name: 'Special Combo',
      type: ProductType.inHouse,
      price: 250,
      category: 'Combos & Meals',
    );
    expect(custom.category, 'Combos & Meals');
    expect(custom.displayCategory, 'Combos & Meals');

    final map = custom.toMap();
    expect(map['category'], 'Combos & Meals');
    final restored = Product.fromMap(map, 'c1');
    expect(restored.category, 'Combos & Meals');
    expect(restored.displayCategory, 'Combos & Meals');

    // Test heuristic classification for backwards compatibility
    expect(
      Product(id: '1', name: 'Cold Coffee', type: ProductType.inHouse).displayCategory,
      'Coffee & Tea',
    );
    expect(
      Product(id: '2', name: 'Masala Chai', type: ProductType.inHouse).displayCategory,
      'Coffee & Tea',
    );
    expect(
      Product(id: '3', name: 'Coca Cola Can', type: ProductType.mrp).displayCategory,
      'Beverages',
    );
    expect(
      Product(id: '4', name: 'Haldiram Bhel', type: ProductType.mrp).displayCategory,
      'Snacks & Food',
    );
    expect(
      Product(id: '5', name: 'Chocolate Brownie', type: ProductType.inHouse).displayCategory,
      'Bakery & Desserts',
    );
    expect(
      Product(id: '6', name: 'Fresh Guava Plate', type: ProductType.inHouse).displayCategory,
      'Fresh Fruits',
    );
    expect(
      Product(id: '7', name: 'Notebook', type: ProductType.mrp).displayCategory,
      'General',
    );
  });
}
