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

class InventoryService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _products =>
      _db.collection('products');
  static CollectionReference<Map<String, dynamic>> get _materials =>
      _db.collection('raw_materials');
  static CollectionReference<Map<String, dynamic>> get _recipes =>
      _db.collection('recipes');

  static Stream<List<Product>> watchProducts() {
    return _products
        .orderBy('name')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Product.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  static Stream<List<RawMaterial>> watchRawMaterials() {
    return _materials
        .orderBy('name')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => RawMaterial.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  static Future<Recipe?> loadRecipe(String productId) async {
    final snap = await _recipes.doc(productId).get();
    final data = snap.data();
    return data == null ? null : Recipe.fromMap(data, snap.id);
  }

  static Future<String> createProduct(Product product) async {
    final ref = _products.doc();
    await ref.set(product.toMap()..['id'] = ref.id);
    return ref.id;
  }

  static Future<void> updateProduct(Product product) {
    return _products
        .doc(product.id)
        .update(product.toMap()..['id'] = product.id);
  }

  static Future<void> setAvailability(String productId, bool isAvailable) {
    return _products.doc(productId).update({'isAvailable': isAvailable});
  }

  /// Removes a product and the recipe keyed by its id, so a deleted in-house
  /// item cannot leave an orphan recipe behind.
  static Future<void> deleteProduct(String productId) async {
    final batch = _db.batch();
    batch.delete(_products.doc(productId));
    batch.delete(_recipes.doc(productId));
    await batch.commit();
  }

  static Future<String> createRawMaterial(RawMaterial material) async {
    final ref = _materials.doc();
    await ref.set(material.toMap()..['id'] = ref.id);
    return ref.id;
  }

  static Future<void> updateRawMaterial(RawMaterial material) {
    return _materials
        .doc(material.id)
        .update(material.toMap()..['id'] = material.id);
  }

  /// Applies a signed [delta] to stock. Reading inside a transaction keeps a
  /// manual correction from racing a sale and driving stock negative.
  static Future<double> adjustRawMaterialStock(
    String materialId,
    double delta, {
    String? reason,
  }) async {
    if (delta == 0) {
      throw InventoryException('Enter an amount to add or remove.');
    }
    final ref = _materials.doc(materialId);

    return _db.runTransaction<double>((transaction) async {
      final snap = await transaction.get(ref);
      final data = snap.data();
      if (data == null) {
        throw InventoryException('This material no longer exists.');
      }
      final material = RawMaterial.fromMap(data, snap.id);
      final updated = material.currentStock + delta;
      if (updated < 0) {
        throw InventoryException(
          'Only ${material.currentStock.toStringAsFixed(2)} ${material.unit} in stock.',
        );
      }
      transaction.update(ref, {
        'currentStock': updated,
        'lastAdjustedAt': FieldValue.serverTimestamp(),
        if (reason != null && reason.trim().isNotEmpty)
          'lastAdjustmentReason': reason.trim(),
      });
      return updated;
    });
  }

  /// Refuses to delete a material that a recipe still consumes, which would
  /// otherwise make those products silently un-sellable at checkout.
  static Future<void> deleteRawMaterial(String materialId) async {
    final users = await _recipeNamesUsing(materialId);
    if (users.isNotEmpty) {
      throw InventoryException(
        'Still used by ${users.length} recipe(s). Remove it from them first.',
      );
    }
    await _materials.doc(materialId).delete();
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
