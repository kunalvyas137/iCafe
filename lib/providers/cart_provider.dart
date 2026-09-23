import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/order.dart';
import '../services/order_service.dart';

/// A line item removed from the cart, kept so the removal can be undone.
class RemovedCartItem {
  final int index;
  final OrderItem item;

  RemovedCartItem(this.index, this.item);
}

class CartProvider with ChangeNotifier {
  final List<OrderItem> _items = [];

  List<OrderItem> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;

  double get subtotal =>
      _items.fold(0, (total, item) => total + item.totalWithoutGst);
  double get totalGst =>
      _items.fold(0, (total, item) => total + item.gstAmount);
  double get grandTotal => subtotal + totalGst;

  int quantityOf(String productId) {
    return _items
        .where((item) => item.productId == productId)
        .fold(0, (sum, item) => sum + item.quantity);
  }

  /// Adds [quantity] of [product], capped at the available stock for products
  /// that track it. Returns an error message when nothing could be added.
  String? addProduct(
    Product product, {
    int quantity = 1,
    List<String>? modifiers,
    String? notes,
  }) {
    if (!product.isAvailable) {
      return '${product.name} is marked unavailable.';
    }

    final inCart = quantityOf(product.id);
    if (product.tracksStock && inCart + quantity > product.currentStock) {
      final remaining = product.currentStock.toInt() - inCart;
      if (remaining <= 0) {
        return '${product.name} is out of stock.';
      }
      return 'Only $remaining of ${product.name} left in stock.';
    }

    final mods = modifiers ?? const <String>[];
    final trimmedNotes = notes?.trim();

    final existingIndex = _items.indexWhere(
      (item) =>
          item.productId == product.id &&
          listEquals(item.modifiers, mods) &&
          (item.notes ?? '') == (trimmedNotes ?? ''),
    );
    if (existingIndex >= 0) {
      _items[existingIndex] = _items[existingIndex].copyWith(
        quantity: _items[existingIndex].quantity + quantity,
      );
    } else {
      _items.add(
        OrderItem(
          productId: product.id,
          productName: product.name,
          price: product.price,
          quantity: quantity,
          gstRate: product.gstRate,
          modifiers: mods,
          notes: trimmedNotes,
          isTaxInclusive: product.isTaxInclusive,
        ),
      );
    }
    notifyListeners();
    return null;
  }

  void incrementQuantity(String productId) {
    final index = _items.indexWhere((item) => item.productId == productId);
    if (index < 0) return;
    incrementQuantityAt(index);
  }

  void incrementQuantityAt(int index) {
    if (index < 0 || index >= _items.length) return;
    _items[index] = _items[index].copyWith(
      quantity: _items[index].quantity + 1,
    );
    notifyListeners();
  }

  /// Decreases the line quantity, removing the line when it reaches zero.
  void decrementQuantity(String productId) {
    final index = _items.indexWhere((item) => item.productId == productId);
    if (index < 0) return;
    decrementQuantityAt(index);
  }

  void decrementQuantityAt(int index) {
    if (index < 0 || index >= _items.length) return;
    final quantity = _items[index].quantity - 1;
    if (quantity <= 0) {
      _items.removeAt(index);
    } else {
      _items[index] = _items[index].copyWith(quantity: quantity);
    }
    notifyListeners();
  }

  RemovedCartItem? removeProduct(String productId) {
    final index = _items.indexWhere((item) => item.productId == productId);
    if (index < 0) return null;
    return removeItemAt(index);
  }

  RemovedCartItem? removeItemAt(int index) {
    if (index < 0 || index >= _items.length) return null;
    final removed = RemovedCartItem(index, _items.removeAt(index));
    notifyListeners();
    return removed;
  }

  void updateItemModifiers({
    required int index,
    List<String>? modifiers,
    String? notes,
  }) {
    if (index < 0 || index >= _items.length) return;
    _items[index] = _items[index].copyWith(
      modifiers: modifiers ?? _items[index].modifiers,
      notes: notes,
    );
    notifyListeners();
  }

  /// Puts a removed line back. A line is unique by product, modifiers and
  /// notes, so if an identical line was rung up again in the meantime the
  /// restored quantity merges into it instead of becoming a second line.
  void restoreItem(RemovedCartItem removed) {
    _mergeIn(removed.item, at: removed.index);
    notifyListeners();
  }

  List<OrderItem> clearCart() {
    final cleared = List<OrderItem>.from(_items);
    _items.clear();
    notifyListeners();
    return cleared;
  }

  /// Puts a cleared cart back, merging into anything rung up since the clear
  /// rather than discarding it.
  void restoreItems(List<OrderItem> items) {
    if (items.isEmpty) return;
    for (final item in items) {
      _mergeIn(item);
    }
    notifyListeners();
  }

  void _mergeIn(OrderItem item, {int? at}) {
    final index = _items.indexWhere(
      (line) =>
          line.productId == item.productId &&
          listEquals(line.modifiers, item.modifiers) &&
          (line.notes ?? '') == (item.notes ?? ''),
    );
    if (index >= 0) {
      _items[index] = _items[index].copyWith(
        quantity: _items[index].quantity + item.quantity,
      );
      return;
    }
    _items.insert((at ?? _items.length).clamp(0, _items.length), item);
  }

  /// Checks the cart against the current catalogue, returning one message per
  /// line item that can no longer be fulfilled.
  List<String> stockIssues(Map<String, Product> catalog) {
    final issues = <String>[];
    final seen = <String>{};
    for (final item in _items) {
      if (!seen.add(item.productId)) continue;
      final product = catalog[item.productId];
      if (product == null) {
        issues.add('${item.productName} is no longer in the catalogue.');
        continue;
      }
      if (!product.isAvailable) {
        issues.add('${product.name} is marked unavailable.');
        continue;
      }
      final inCart = quantityOf(item.productId);
      if (product.tracksStock && inCart > product.currentStock) {
        issues.add(
          '${product.name}: only ${product.currentStock.toInt()} left, $inCart in cart.',
        );
      }
    }
    return issues;
  }

  /// Commits the cart through [OrderService]. The cart is only emptied once
  /// the transaction has succeeded, so a failed payment keeps the till intact.
  /// Throws [CheckoutException] (or a Firestore error) on failure.
  Future<CafeOrder> checkout({
    required PaymentMethod method,
    double? cashTendered,
    String? notes,
    String? tableLabel,
    String? customerName,
  }) async {
    final order = await OrderService.placeOrder(
      items: List<OrderItem>.from(_items),
      paymentMethod: method,
      cashTendered: cashTendered,
      notes: notes,
      tableLabel: tableLabel,
      customerName: customerName,
    );
    clearCart();
    return order;
  }
}
