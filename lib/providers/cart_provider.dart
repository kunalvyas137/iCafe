import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../models/order.dart';
import 'printer_provider.dart';
import '../services/printer_service.dart';

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
  double get totalGst => _items.fold(0, (total, item) => total + item.gstAmount);
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

    final existingIndex =
        _items.indexWhere((item) => item.productId == product.id);
    if (existingIndex >= 0) {
      _items[existingIndex] =
          _items[existingIndex].copyWith(quantity: inCart + quantity);
    } else {
      _items.add(OrderItem(
        productId: product.id,
        productName: product.name,
        price: product.price,
        quantity: quantity,
        gstRate: product.gstRate,
      ));
    }
    notifyListeners();
    return null;
  }

  void incrementQuantity(String productId) {
    final index = _items.indexWhere((item) => item.productId == productId);
    if (index < 0) return;
    _items[index] = _items[index].copyWith(quantity: _items[index].quantity + 1);
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

  Future<void> checkout(PaymentMethod method, BuildContext context) async {
    final newOrder = CafeOrder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      items: List.from(_items),
      subtotal: subtotal,
      totalGst: totalGst,
      grandTotal: grandTotal,
      timestamp: DateTime.now(),
      status: OrderStatus.completed,
      paymentMethod: method,
    );

    try {
      final batch = FirebaseFirestore.instance.batch();

      // 1. Add order to batch
      final orderRef = FirebaseFirestore.instance.collection('orders').doc(newOrder.id);
      batch.set(orderRef, newOrder.toMap());

      // 2. Deduct inventory based on recipes
      for (var item in _items) {
        final productDoc = await FirebaseFirestore.instance.collection('products').doc(item.productId).get();
        if (!productDoc.exists) continue;

        final typeStr = productDoc.data()?['type'] ?? '';
        
        // If it's an inHouse product, we need to deduct its raw materials via the recipe engine
        if (typeStr == ProductType.inHouse.name) {
          final recipeDoc = await FirebaseFirestore.instance.collection('recipes').doc(item.productId).get();
          if (recipeDoc.exists) {
            final ingredients = recipeDoc.data()?['ingredients'] as List<dynamic>? ?? [];
            for (var ing in ingredients) {
              final rawMaterialId = ing['rawMaterialId'] as String;
              final quantityPerUnit = (ing['quantity'] as num).toDouble();
              final totalDeduction = quantityPerUnit * item.quantity;
              
              final rawMatRef = FirebaseFirestore.instance.collection('raw_materials').doc(rawMaterialId);
              batch.update(rawMatRef, {'currentStock': FieldValue.increment(-totalDeduction)});
            }
          }
        } else {
          // If it's an MRP product, deduct the direct product stock (if tracked)
          final hasStock = productDoc.data()?.containsKey('currentStock') ?? false;
          if (hasStock) {
             final productRef = FirebaseFirestore.instance.collection('products').doc(item.productId);
             batch.update(productRef, {'currentStock': FieldValue.increment(-item.quantity)});
          }
        }
      }

      await batch.commit();
      print('Order ${newOrder.id} successfully pushed to Firestore with Inventory Deduction');
      
      // Print the receipt
      if (context.mounted) {
        final printerProvider = context.read<PrinterProvider>();
        if (printerProvider.isConnected) {
          final bytes = await PrinterService.generateBillTicket(newOrder);
          final success = await printerProvider.printBytes(bytes);
          if (!success) {
            print('Failed to print receipt.');
          }
        }
      }

      clearCart();
    } catch (e) {
      print('Error pushing order to Firestore: $e');
    }
  }
}
