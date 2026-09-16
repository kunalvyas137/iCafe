import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/product.dart';
import '../models/raw_material.dart';
import '../models/recipe.dart';

/// An inventory change that was refused before anything was written.
class InventoryException implements Exception {
  final String message;
  InventoryException(this.message);

  @override
  String toString() => message;
}

/// A single delivered line: added to [targetId], or booked as a new
/// material/product when it is null.
class StockReceipt {
  const StockReceipt({
    required this.name,
    required this.quantity,
    required this.unit,
    this.targetId,
    this.reason,
    this.isMrpProduct = false,
    this.price = 0.0,
  });

  final String name;
  final double quantity;
  final String unit;
  final String? targetId;
  final String? reason;
  final bool isMrpProduct;
  final double price;
}

class InventoryService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _products =>
      _db.collection('products');
  static CollectionReference<Map<String, dynamic>> get _materials =>
      _db.collection('raw_materials');
  static CollectionReference<Map<String, dynamic>> get _recipes =>
      _db.collection('recipes');

  static bool _migrationChecked = false;

  /// Ensures legacy raw_materials documents are safely mirrored to products collection.
  static Future<void> ensureMigrated() async {
    if (_migrationChecked) return;
    _migrationChecked = true;
    try {
      final snap = await _materials.get();
      if (snap.docs.isEmpty) return;

      final batch = _db.batch();
      var needCommit = false;
      for (final doc in snap.docs) {
        final prodSnap = await _products.doc(doc.id).get();
        if (!prodSnap.exists) {
          final data = doc.data();
          final product = Product(
            id: doc.id,
            name: data['name'] ?? '',
            type: ProductType.rawMaterial,
            unit: (data['unit'] ?? 'kg').toString(),
            currentStock: (data['currentStock'] ?? 0.0).toDouble(),
            reorderLevel: (data['reorderLevel'] ?? 0.0).toDouble(),
            isSellable: false,
            isIngredient: true,
          );
          batch.set(_products.doc(doc.id), product.toMap());
          needCommit = true;
        }
      }
      if (needCommit) {
        await batch.commit();
      }
    } catch (_) {
      // Non-fatal, continue with existing data
    }
  }

  /// Streams products. If [sellableOnly] is true, returns only items marked as sellable on POS.
  static Stream<List<Product>> watchProducts({bool? sellableOnly}) {
    return _products
        .orderBy('name')
        .snapshots()
        .map(
          (snap) {
            final list = snap.docs
                .map((doc) => Product.fromMap(doc.data(), doc.id))
                .toList();
            if (sellableOnly == true) {
              return list.where((p) => p.isSellable).toList();
            }
            return list;
          },
        );
  }

  /// Look up a product by its SKU / barcode. Returns null if not found.
  static Future<Product?> findBySku(String sku) async {
    if (sku.trim().isEmpty) return null;
    final q = await _products
        .where('sku', isEqualTo: sku.trim())
        .limit(1)
        .get();
    if (q.docs.isNotEmpty) {
      final doc = q.docs.first;
      return Product.fromMap(doc.data(), doc.id);
    }
    // Also check by document ID (some flows use the ID as the SKU)
    final byId = await _products.doc(sku.trim()).get();
    if (byId.exists) return Product.fromMap(byId.data()!, byId.id);
    return null;
  }

  /// Streams raw materials / ingredients. Reads unified products collection with fallback to raw_materials.
  static Stream<List<RawMaterial>> watchRawMaterials() {
    return _products
        .orderBy('name')
        .snapshots()
        .map((snap) {
          final products = snap.docs
              .map((doc) => Product.fromMap(doc.data(), doc.id))
              .where((p) => p.isIngredient || p.type == ProductType.rawMaterial)
              .map((p) => RawMaterial(
                    id: p.id,
                    name: p.name,
                    unit: p.unit,
                    currentStock: p.currentStock,
                    reorderLevel: p.reorderLevel,
                  ))
              .toList();
          return products;
        });
  }

  static Future<Recipe?> loadRecipe(String productId) async {
    final snap = await _recipes.doc(productId).get();
    final data = snap.data();
    return data == null ? null : Recipe.fromMap(data, snap.id);
  }

  static Future<String> createProduct(Product product) async {
    final ref = product.id.isEmpty ? _products.doc() : _products.doc(product.id);
    final id = ref.id;
    final toSave = product.copyWith(id: id);
    await ref.set(toSave.toMap()..['id'] = id);

    // If it's an ingredient or raw material, mirror to raw_materials collection for backwards compatibility
    if (toSave.isIngredient || toSave.type == ProductType.rawMaterial) {
      await _materials.doc(id).set(
        RawMaterial(
          id: id,
          name: toSave.name,
          unit: toSave.unit,
          currentStock: toSave.currentStock,
          reorderLevel: toSave.reorderLevel,
        ).toMap(),
        SetOptions(merge: true),
      );
    }
    return id;
  }

  static Future<void> updateProduct(Product product) async {
    await _products
        .doc(product.id)
        .update(product.toMap()..['id'] = product.id);

    // Mirror updates to raw_materials if it is an ingredient
    if (product.isIngredient || product.type == ProductType.rawMaterial) {
      await _materials.doc(product.id).set(
        RawMaterial(
          id: product.id,
          name: product.name,
          unit: product.unit,
          currentStock: product.currentStock,
          reorderLevel: product.reorderLevel,
        ).toMap(),
        SetOptions(merge: true),
      );
    }
  }

  static Future<void> setAvailability(String productId, bool isAvailable) {
    return _products.doc(productId).update({'isAvailable': isAvailable});
  }

  /// Instantly publishes an inventory item to the POS menu with a given selling price and GST rate.
  static Future<void> publishToPos(
    String productId, {
    required double price,
    required double gstRate,
  }) async {
    await _products.doc(productId).update({
      'type': ProductType.mrp.name,
      'isSellable': true,
      'price': price,
      'gstRate': gstRate,
      'isAvailable': true,
    });
  }

  /// Hides/removes an item from the POS menu while keeping it in inventory.
  static Future<void> removeFromPos(String productId) async {
    await _products.doc(productId).update({
      'isSellable': false,
      'isAvailable': false,
    });
  }

  /// Removes a product and its recipe.
  static Future<void> deleteProduct(String productId) async {
    final batch = _db.batch();
    batch.delete(_products.doc(productId));
    batch.delete(_materials.doc(productId));
    batch.delete(_recipes.doc(productId));
    await batch.commit();
  }

  static Future<String> createRawMaterial(RawMaterial material) async {
    final ref = material.id.isEmpty ? _products.doc() : _products.doc(material.id);
    final id = ref.id;
    final product = Product(
      id: id,
      name: material.name,
      type: ProductType.rawMaterial,
      unit: material.unit,
      currentStock: material.currentStock,
      reorderLevel: material.reorderLevel,
      isSellable: false,
      isIngredient: true,
    );
    await ref.set(product.toMap()..['id'] = id);
    await _materials.doc(id).set(material.toMap()..['id'] = id);
    return id;
  }

  static Future<void> updateRawMaterial(RawMaterial material) async {
    await _products.doc(material.id).set({
      'name': material.name,
      'unit': material.unit,
      'currentStock': material.currentStock,
      'reorderLevel': material.reorderLevel,
      'isIngredient': true,
    }, SetOptions(merge: true));

    await _materials
        .doc(material.id)
        .set(material.toMap()..['id'] = material.id, SetOptions(merge: true));
  }

  /// Books delivered items directly into unified products inventory.
  /// Any MRP/resale product is immediately available on POS with its selling price.
  static Future<int> receiveStock(List<StockReceipt> receipts) async {
    if (receipts.isEmpty) {
      throw InventoryException('Nothing to receive.');
    }

    var created = 0;
    for (final receipt in receipts) {
      if (receipt.quantity <= 0) continue;
      final targetId = receipt.targetId;

      if (targetId == null) {
        // Create new item in unified products collection
        final isSellable = receipt.isMrpProduct;
        final sellPrice = receipt.price > 0 ? receipt.price * 1.5 : 10.0;
        final newProduct = Product(
          id: '',
          name: receipt.name,
          type: isSellable ? ProductType.mrp : ProductType.rawMaterial,
          price: isSellable ? sellPrice : 0.0,
          costPrice: receipt.price > 0 ? receipt.price : null,
          gstRate: 0,
          currentStock: receipt.quantity,
          reorderLevel: 0,
          unit: receipt.unit.isEmpty ? 'pcs' : receipt.unit,
          isAvailable: true,
          isSellable: isSellable,
          isIngredient: !isSellable,
        );
        await createProduct(newProduct);
        created++;
      } else {
        await _db.runTransaction<void>((transaction) async {
          final prodRef = _products.doc(targetId);
          final snap = await transaction.get(prodRef);
          if (snap.exists) {
            final data = snap.data()!;
            final currentStock = (data['currentStock'] as num? ?? 0).toDouble();
            final updates = <String, dynamic>{
              'currentStock': currentStock + receipt.quantity,
              if (receipt.price > 0) 'costPrice': receipt.price,
            };
            if (receipt.isMrpProduct) {
              updates['isSellable'] = true;
              updates['type'] = ProductType.mrp.name;
              if ((data['price'] as num? ?? 0) <= 0 && receipt.price > 0) {
                updates['price'] = receipt.price * 1.5;
              }
            }
            transaction.update(prodRef, updates);

            // Sync legacy raw_materials doc if present
            final rawRef = _materials.doc(targetId);
            final rawSnap = await transaction.get(rawRef);
            if (rawSnap.exists) {
              final rawStock = (rawSnap.data()?['currentStock'] as num? ?? 0).toDouble();
              transaction.update(rawRef, {'currentStock': rawStock + receipt.quantity});
            }
          } else {
            // Target was in legacy raw_materials
            final rawRef = _materials.doc(targetId);
            final rawSnap = await transaction.get(rawRef);
            if (!rawSnap.exists) throw InventoryException('Item not found.');
            final rawData = rawSnap.data()!;
            final currentStock = (rawData['currentStock'] as num? ?? 0).toDouble();
            final updatedStock = currentStock + receipt.quantity;
            transaction.update(rawRef, {'currentStock': updatedStock});

            // Mirror into products
            final newProd = Product(
              id: targetId,
              name: rawData['name'] ?? receipt.name,
              type: receipt.isMrpProduct ? ProductType.mrp : ProductType.rawMaterial,
              unit: rawData['unit'] ?? receipt.unit,
              currentStock: updatedStock,
              reorderLevel: (rawData['reorderLevel'] ?? 0.0).toDouble(),
              isSellable: receipt.isMrpProduct,
              isIngredient: true,
            );
            transaction.set(prodRef, newProd.toMap());
          }
        });
      }
    }
    return created;
  }

  /// Adjusts stock for any inventory item (product or raw material) by [delta].
  static Future<double> adjustStock(
    String itemId,
    double delta, {
    String? reason,
  }) async {
    if (delta == 0) {
      throw InventoryException('Enter an amount to add or remove.');
    }
    final prodRef = _products.doc(itemId);
    final rawRef = _materials.doc(itemId);

    return _db.runTransaction<double>((transaction) async {
      final prodSnap = await transaction.get(prodRef);
      final rawSnap = await transaction.get(rawRef);

      if (!prodSnap.exists && !rawSnap.exists) {
        throw InventoryException('This item no longer exists.');
      }

      final data = prodSnap.data() ?? rawSnap.data()!;
      final currentStock = (data['currentStock'] as num? ?? 0).toDouble();
      final unit = (data['unit'] ?? 'pcs').toString();
      final updated = currentStock + delta;

      if (updated < 0) {
        throw InventoryException(
          'Only ${currentStock.toStringAsFixed(2)} $unit in stock.',
        );
      }

      if (prodSnap.exists) {
        transaction.update(prodRef, {
          'currentStock': updated,
          'lastAdjustedAt': FieldValue.serverTimestamp(),
          if (reason != null && reason.trim().isNotEmpty)
            'lastAdjustmentReason': reason.trim(),
        });
      }

      if (rawSnap.exists) {
        transaction.update(rawRef, {
          'currentStock': updated,
          'lastAdjustedAt': FieldValue.serverTimestamp(),
          if (reason != null && reason.trim().isNotEmpty)
            'lastAdjustmentReason': reason.trim(),
        });
      }

      return updated;
    });
  }

  /// Backwards-compatible alias for adjustStock.
  static Future<double> adjustRawMaterialStock(
    String materialId,
    double delta, {
    String? reason,
  }) {
    return adjustStock(materialId, delta, reason: reason);
  }

  /// Transfers [quantity] from a raw material to an MRP product's stock.
  static Future<void> transferStock(
    String rawMaterialId,
    String productId,
    double quantity, {
    String? reason,
  }) async {
    if (quantity <= 0) {
      throw InventoryException('Quantity to transfer must be positive.');
    }
    final sourceRef = _products.doc(rawMaterialId);
    final destRef = _products.doc(productId);

    return _db.runTransaction<void>((transaction) async {
      final sourceSnap = await transaction.get(sourceRef);
      final destSnap = await transaction.get(destRef);

      if (!sourceSnap.exists || !destSnap.exists) {
        throw InventoryException('One of the items no longer exists.');
      }

      final sourceData = sourceSnap.data()!;
      final destData = destSnap.data()!;

      final sourceStock = (sourceData['currentStock'] as num? ?? 0).toDouble();
      final destStock = (destData['currentStock'] as num? ?? 0).toDouble();
      final unit = (sourceData['unit'] ?? 'pcs').toString();

      final updatedSource = sourceStock - quantity;
      if (updatedSource < 0) {
        throw InventoryException(
          'Cannot transfer $quantity. Only ${sourceStock.toStringAsFixed(2)} $unit in stock.',
        );
      }

      transaction.update(sourceRef, {
        'currentStock': updatedSource,
        'lastAdjustedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(destRef, {
        'currentStock': destStock + quantity,
      });
    });
  }

  /// Deletes a raw material if not used in any recipes.
  static Future<void> deleteRawMaterial(String materialId) async {
    final users = await _recipeNamesUsing(materialId);
    if (users.isNotEmpty) {
      throw InventoryException(
        'Still used by ${users.length} recipe(s). Remove it from them first.',
      );
    }
    final batch = _db.batch();
    batch.delete(_products.doc(materialId));
    batch.delete(_materials.doc(materialId));
    await batch.commit();
  }

  static Future<List<String>> _recipeNamesUsing(String materialId) async {
    final snap = await _recipes.get();
    final matches = <String>[];
    for (final doc in snap.docs) {
      final recipe = Recipe.fromMap(doc.data(), doc.id);
      final uses = recipe.ingredients.any(
        (ingredient) => ingredient.rawMaterialId == materialId,
      );
      if (uses) matches.add(recipe.productId);
    }
    return matches;
  }

  static Future<void> saveRecipe(Recipe recipe) {
    return _recipes.doc(recipe.productId).set(recipe.toMap());
  }

  static Future<void> deleteRecipe(String productId) {
    return _recipes.doc(productId).delete();
  }
}
