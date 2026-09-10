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
    final index = _items.indexWhere((item) => item.productId == productId);
    return index < 0 ? 0 : _items[index].quantity;
  }

  /// Adds [quantity] of [product], capped at the available stock for products
  /// that track it. Returns an error message when nothing could be added.
  String? addProduct(Product product, {int quantity = 1}) {
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

    final existingIndex = _items.indexWhere(
      (item) => item.productId == product.id,
    );
    if (existingIndex >= 0) {
      _items[existingIndex] = _items[existingIndex].copyWith(
        quantity: inCart + quantity,
      );
    } else {
      _items.add(
        OrderItem(
          productId: product.id,
          productName: product.name,
          price: product.price,
          quantity: quantity,
          gstRate: product.gstRate,
        ),
      );
    }
    notifyListeners();
    return null;
  }

  void incrementQuantity(String productId) {
    final index = _items.indexWhere((item) => item.productId == productId);
    if (index < 0) return;
    _items[index] = _items[index].copyWith(
      quantity: _items[index].quantity + 1,
    );
    notifyListeners();
  }

  /// Decreases the line quantity, removing the line when it reaches zero.
  void decrementQuantity(String productId) {
    final index = _items.indexWhere((item) => item.productId == productId);
    if (index < 0) return;
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
    final removed = RemovedCartItem(index, _items.removeAt(index));
    notifyListeners();
    return removed;
  }

  void restoreItem(RemovedCartItem removed) {
    final index = removed.index.clamp(0, _items.length);
    _items.insert(index, removed.item);
    notifyListeners();
  }

  List<OrderItem> clearCart() {
    final cleared = List<OrderItem>.from(_items);
    _items.clear();
    notifyListeners();
    return cleared;
  }

  void restoreItems(List<OrderItem> items) {
    if (items.isEmpty) return;
    _items
      ..clear()
      ..addAll(items);
    notifyListeners();
  }

  /// Checks the cart against the current catalogue, returning one message per
  /// line item that can no longer be fulfilled.
  List<String> stockIssues(Map<String, Product> catalog) {
    final issues = <String>[];
    for (final item in _items) {
      final product = catalog[item.productId];
      if (product == null) {
        issues.add('${item.productName} is no longer in the catalogue.');
        continue;
      }
      if (!product.isAvailable) {
        issues.add('${product.name} is marked unavailable.');
        continue;
      }
      if (product.tracksStock && item.quantity > product.currentStock) {
        issues.add(
          '${product.name}: only ${product.currentStock.toInt()} left, ${item.quantity} in cart.',
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
