import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/recipe.dart';

/// A checkout that was refused before anything was written.
class CheckoutException implements Exception {
  final String message;
  CheckoutException(this.message);

  @override
  String toString() => message;
}

class OrderService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static String dayKeyFor(DateTime when) {
    final month = when.month.toString().padLeft(2, '0');
    final day = when.day.toString().padLeft(2, '0');
    return '${when.year}$month$day';
  }

  /// Commits an order and the stock it consumes in a single transaction, so a
  /// failure anywhere leaves neither a half-deducted inventory nor a phantom
  /// order. Throws [CheckoutException] when stock ran out between the cart
  /// being built and this call.
  static Future<CafeOrder> placeOrder({
    required List<OrderItem> items,
    required PaymentMethod paymentMethod,
    double? cashTendered,
    String? notes,
    String? tableLabel,
    String? customerName,
    DateTime? now,
  }) async {
    if (items.isEmpty) {
      throw CheckoutException('The cart is empty.');
    }

    final timestamp = now ?? DateTime.now();
    final dayKey = dayKeyFor(timestamp);
    final orderRef = _db.collection('orders').doc();
    final counterRef = _db.collection('counters').doc('orders_$dayKey');

    return _db.runTransaction<CafeOrder>((transaction) async {
      // Firestore requires every read to happen before the first write.
      final counterSnap = await transaction.get(counterRef);

      // Stock is validated and deducted per product, not per line: the same
      // product appears on several lines when modifiers differ, and each
      // line would otherwise pass the stock check on its own.
      final quantities = <String, int>{};
      final names = <String, String>{};
      for (final item in items) {
        quantities.update(
          item.productId,
          (value) => value + item.quantity,
          ifAbsent: () => item.quantity,
        );
        names[item.productId] = item.productName;
      }

      final productSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final productId in quantities.keys) {
        productSnaps[productId] = await transaction.get(
          _db.collection('products').doc(productId),
        );
      }

      final recipes = <String, Recipe>{};
      for (final entry in productSnaps.entries) {
        final data = entry.value.data();
        if (data == null) continue;
        if (data['type'] != ProductType.inHouse.name) continue;
        final recipeSnap = await transaction.get(
          _db.collection('recipes').doc(entry.key),
        );
        final recipeData = recipeSnap.data();
        if (recipeData != null) {
          recipes[entry.key] = Recipe.fromMap(recipeData, recipeSnap.id);
        }
      }

      // Sum raw-material usage across lines first: two products can share an
      // ingredient, and Firestore forbids reading the same doc twice.
      final materialUsage = <String, double>{};
      quantities.forEach((productId, quantity) {
        final recipe = recipes[productId];
        if (recipe == null) return;
        for (final ingredient in recipe.ingredients) {
          materialUsage.update(
            ingredient.rawMaterialId,
            (value) => value + ingredient.quantity * quantity,
            ifAbsent: () => ingredient.quantity * quantity,
          );
        }
      });

      final materials = await _readMaterials(transaction, materialUsage.keys);

      // Validation, still before any write.
      final problems = <String>[];
      final productDeductions = <String, double>{};
      quantities.forEach((productId, quantity) {
        final snap = productSnaps[productId]!;
        final data = snap.data();
        if (data == null) {
          problems.add('${names[productId]} is no longer in the catalogue.');
          return;
        }
        final product = Product.fromMap(data, snap.id);
        if (!product.isAvailable) {
          problems.add('${product.name} is marked unavailable.');
          return;
        }
        if (product.tracksStock && quantity > product.currentStock) {
          problems.add(
            '${product.name}: only ${product.currentStock.toInt()} left, $quantity in cart.',
          );
          return;
        }
        // An in-house product consumes stock only through its recipe, so
        // selling one without a recipe would leave inventory overstated.
        if (product.type == ProductType.inHouse &&
            (recipes[productId]?.ingredients.isEmpty ?? true)) {
          problems.add(
            '${product.name} has no recipe, so its stock cannot be tracked.',
          );
          return;
        }
        if (product.type == ProductType.mrp) {
          productDeductions[productId] = quantity.toDouble();
        }
      });

      materialUsage.forEach((materialId, required) {
        final data = materials[materialId]!.snapshot.data();
        if (data == null) {
          problems.add('A recipe ingredient ($materialId) is missing.');
          return;
        }
        final currentStock = (data['currentStock'] as num? ?? 0).toDouble();
        final name = data['name'] ?? 'Ingredient';
        final unit = (data['unit'] ?? 'pcs').toString();
        if (currentStock < required) {
          problems.add(
            '$name: needs ${required.toStringAsFixed(2)} $unit, ${currentStock.toStringAsFixed(2)} in stock.',
          );
        }
      });

      if (problems.isNotEmpty) {
        throw CheckoutException(problems.join('\n'));
      }

      final subtotal = items.fold<double>(
        0,
        (total, item) => total + item.totalWithoutGst,
      );
      final totalGst = items.fold<double>(
        0,
        (total, item) => total + item.gstAmount,
      );
      final orderNumber =
          ((counterSnap.data()?['lastNumber'] as num?)?.toInt() ?? 0) + 1;

      final order = CafeOrder(
        id: orderRef.id,
        timestamp: timestamp,
        items: items,
        subtotal: subtotal,
        totalGst: totalGst,
        grandTotal: subtotal + totalGst,
        paymentMethod: paymentMethod,
        status: OrderStatus.pending,
        orderNumber: orderNumber,
        dayKey: dayKey,
        cashTendered: paymentMethod == PaymentMethod.cash ? cashTendered : null,
        notes: _trimToNull(notes),
        tableLabel: _trimToNull(tableLabel),
        customerName: _trimToNull(customerName),
        cashierId: FirebaseAuth.instance.currentUser?.uid,
        productDeductions: productDeductions,
        materialDeductions: Map<String, double>.from(materialUsage),
        hasStockRecord: true,
      );

      transaction.set(counterRef, {
        'lastNumber': orderNumber,
        'dayKey': dayKey,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(orderRef, order.toMap());

      productDeductions.forEach((productId, quantity) {
        transaction.update(_db.collection('products').doc(productId), {
          'currentStock': FieldValue.increment(-quantity),
        });
      });

      materialUsage.forEach((materialId, required) {
        transaction.update(materials[materialId]!.ref, {
          'currentStock': FieldValue.increment(-required),
        });
      });

      return order;
    });
  }

  /// Ingredients live in `products` since the unified inventory, but older
  /// ones may only exist in `raw_materials`; resolve each to wherever it is.
  static Future<Map<String, _MaterialDoc>> _readMaterials(
    Transaction transaction,
    Iterable<String> materialIds,
  ) async {
    final result = <String, _MaterialDoc>{};
    for (final materialId in materialIds) {
      var ref = _db.collection('products').doc(materialId);
      var snap = await transaction.get(ref);
      if (!snap.exists || snap.data() == null) {
        ref = _db.collection('raw_materials').doc(materialId);
        snap = await transaction.get(ref);
      }
      result[materialId] = _MaterialDoc(ref, snap);
    }
    return result;
  }

  /// Orders placed inside [day], newest first.
  static Stream<List<CafeOrder>> watchDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return _db
        .collection('orders')
        .where('timestamp', isGreaterThanOrEqualTo: start.toIso8601String())
        .where('timestamp', isLessThan: end.toIso8601String())
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => CafeOrder.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  /// Live stream of all [pending] and [preparing] orders across any day,
  /// sorted oldest-first so the longest-waiting order is at the top.
  static Stream<List<CafeOrder>> watchActiveOrders() {
    return _db
        .collection('orders')
        .where('status', whereIn: [
          OrderStatus.pending.name,
          OrderStatus.preparing.name,
        ])
        .snapshots()
        .map(
          (snap) {
            final orders = snap.docs
                .map((doc) => CafeOrder.fromMap(doc.data(), doc.id))
                .toList();
            orders.sort((a, b) => a.timestamp.compareTo(b.timestamp));
            return orders;
          },
        );
  }

  /// Alerts the chef: transitions order from [pending] → [preparing].
  static Future<void> alertChef(CafeOrder order) async {
    if (!order.isPending) {
      throw CheckoutException('Order ${order.displayNumber} is not pending.');
    }
    await _db.collection('orders').doc(order.id).update({
      'status': OrderStatus.preparing.name,
      'alertedChefAt': DateTime.now().toIso8601String(),
    });
  }

  /// Closes a prepared order as delivered: transitions [preparing] → [completed].
  /// This is the point at which the order starts counting toward revenue.
  static Future<void> closeOrder(CafeOrder order) async {
    if (!order.isPreparing) {
      throw CheckoutException(
          'Order ${order.displayNumber} is not in the preparing state.');
    }
    await _db.collection('orders').doc(order.id).update({
      'status': OrderStatus.completed.name,
    });
  }

  /// Voids an order and puts the stock it consumed back, in one transaction so
  /// an order can never be marked cancelled without its stock returning.
  static Future<CafeOrder> cancelOrder(
    CafeOrder order, {
    required String reason,
    DateTime? now,
  }) async {
    if (order.isCancelled) {
      throw CheckoutException('This order is already cancelled.');
    }

    final orderRef = _db.collection('orders').doc(order.id);

    return _db.runTransaction<CafeOrder>((transaction) async {
      final orderSnap = await transaction.get(orderRef);
      final data = orderSnap.data();
      if (data == null) {
        throw CheckoutException('This order no longer exists.');
      }
      final current = CafeOrder.fromMap(data, orderSnap.id);
      if (current.isCancelled) {
        throw CheckoutException('This order is already cancelled.');
      }

      // Replay the exact movements recorded at checkout. Only orders that
      // predate the stock record fall back to the current catalogue.
      var productReturns = current.productDeductions;
      var materialReturns = current.materialDeductions;
      if (!current.hasStockRecord) {
        final legacy = await _legacyReturns(transaction, current);
        productReturns = legacy.products;
        materialReturns = legacy.materials;
      }

      final materials = await _readMaterials(transaction, materialReturns.keys);

      final cancelled = CafeOrder(
        id: current.id,
        timestamp: current.timestamp,
        items: current.items,
        subtotal: current.subtotal,
        totalGst: current.totalGst,
        grandTotal: current.grandTotal,
        paymentMethod: current.paymentMethod,
        status: OrderStatus.cancelled,
        orderNumber: current.orderNumber,
        dayKey: current.dayKey,
        cashTendered: current.cashTendered,
        notes: current.notes,
        tableLabel: current.tableLabel,
        customerName: current.customerName,
        cashierId: current.cashierId,
        cancelledAt: now ?? DateTime.now(),
        cancelledBy: FirebaseAuth.instance.currentUser?.uid,
        cancelReason: reason.trim(),
        productDeductions: current.productDeductions,
        materialDeductions: current.materialDeductions,
        hasStockRecord: current.hasStockRecord,
      );

      transaction.update(orderRef, {
        'status': OrderStatus.cancelled.name,
        'cancelledAt': cancelled.cancelledAt!.toIso8601String(),
        if (cancelled.cancelledBy != null) 'cancelledBy': cancelled.cancelledBy,
        'cancelReason': cancelled.cancelReason,
      });

      productReturns.forEach((productId, quantity) {
        transaction.update(_db.collection('products').doc(productId), {
          'currentStock': FieldValue.increment(quantity),
        });
      });

      materialReturns.forEach((materialId, quantity) {
        final material = materials[materialId]!;
        if (!material.snapshot.exists) return;
        transaction.update(material.ref, {
          'currentStock': FieldValue.increment(quantity),
        });
      });

      return cancelled;
    });
  }

  /// Reconstructs what an order written before deductions were persisted
  /// would have taken, from the catalogue and recipes as they stand today.
  static Future<_StockReturns> _legacyReturns(
    Transaction transaction,
    CafeOrder order,
  ) async {
    final quantities = <String, int>{};
    for (final item in order.items) {
      quantities.update(
        item.productId,
        (value) => value + item.quantity,
        ifAbsent: () => item.quantity,
      );
    }

    final products = <String, double>{};
    final materials = <String, double>{};
    for (final entry in quantities.entries) {
      final snap = await transaction.get(
        _db.collection('products').doc(entry.key),
      );
      final data = snap.data();
      if (data == null) continue;
      if (data['type'] == ProductType.mrp.name) {
        products[entry.key] = entry.value.toDouble();
        continue;
      }
      if (data['type'] != ProductType.inHouse.name) continue;
      final recipeSnap = await transaction.get(
        _db.collection('recipes').doc(entry.key),
      );
      final recipeData = recipeSnap.data();
      if (recipeData == null) continue;
      for (final ingredient in Recipe.fromMap(recipeData, recipeSnap.id).ingredients) {
        materials.update(
          ingredient.rawMaterialId,
          (value) => value + ingredient.quantity * entry.value,
          ifAbsent: () => ingredient.quantity * entry.value,
        );
      }
    }
    return _StockReturns(products, materials);
  }

  static String? _trimToNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

class _MaterialDoc {
  const _MaterialDoc(this.ref, this.snapshot);
  final DocumentReference<Map<String, dynamic>> ref;
  final DocumentSnapshot<Map<String, dynamic>> snapshot;
}

class _StockReturns {
  const _StockReturns(this.products, this.materials);
  final Map<String, double> products;
  final Map<String, double> materials;
}
