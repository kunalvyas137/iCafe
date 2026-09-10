import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/raw_material.dart';
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

      final productSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final item in items) {
        productSnaps[item.productId] = await transaction.get(
          _db.collection('products').doc(item.productId),
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
      for (final item in items) {
        final recipe = recipes[item.productId];
        if (recipe == null) continue;
        for (final ingredient in recipe.ingredients) {
          materialUsage.update(
            ingredient.rawMaterialId,
            (value) => value + ingredient.quantity * item.quantity,
            ifAbsent: () => ingredient.quantity * item.quantity,
          );
        }
      }

      final materialSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final materialId in materialUsage.keys) {
        materialSnaps[materialId] = await transaction.get(
          _db.collection('raw_materials').doc(materialId),
        );
      }

      // Validation, still before any write.
      final problems = <String>[];
      for (final item in items) {
        final snap = productSnaps[item.productId]!;
        final data = snap.data();
        if (data == null) {
          problems.add('${item.productName} is no longer in the catalogue.');
          continue;
        }
        final product = Product.fromMap(data, snap.id);
        if (!product.isAvailable) {
          problems.add('${product.name} is marked unavailable.');
        } else if (product.tracksStock &&
            item.quantity > product.currentStock) {
          problems.add(
            '${product.name}: only ${product.currentStock.toInt()} left, ${item.quantity} in cart.',
          );
        }
      }

      materialUsage.forEach((materialId, required) {
        final snap = materialSnaps[materialId]!;
        final data = snap.data();
        if (data == null) {
          problems.add('A recipe ingredient ($materialId) is missing.');
          return;
        }
        final material = RawMaterial.fromMap(data, snap.id);
        if (material.currentStock < required) {
          problems.add(
            '${material.name}: needs ${required.toStringAsFixed(2)} ${material.unit}, ${material.currentStock.toStringAsFixed(2)} in stock.',
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
        status: OrderStatus.completed,
        orderNumber: orderNumber,
        dayKey: dayKey,
        cashTendered: paymentMethod == PaymentMethod.cash ? cashTendered : null,
        notes: _trimToNull(notes),
        tableLabel: _trimToNull(tableLabel),
        customerName: _trimToNull(customerName),
        cashierId: FirebaseAuth.instance.currentUser?.uid,
      );

      transaction.set(counterRef, {
        'lastNumber': orderNumber,
        'dayKey': dayKey,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(orderRef, order.toMap());

      for (final item in items) {
        final data = productSnaps[item.productId]!.data()!;
        final product = Product.fromMap(data, item.productId);
        if (product.type == ProductType.mrp) {
          transaction.update(_db.collection('products').doc(item.productId), {
            'currentStock': FieldValue.increment(-item.quantity),
          });
        }
      }

      materialUsage.forEach((materialId, required) {
        transaction.update(_db.collection('raw_materials').doc(materialId), {
          'currentStock': FieldValue.increment(-required),
        });
      });

      return order;
    });
  }

  static String? _trimToNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
