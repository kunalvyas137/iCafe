class RecipeIngredient {
  final String rawMaterialId;
  final double quantity;

  RecipeIngredient({
    required this.rawMaterialId,
    required this.quantity,
  });

  Map<String, dynamic> toMap() {
    return {
      'rawMaterialId': rawMaterialId,
      'quantity': quantity,
    };
  }

  factory RecipeIngredient.fromMap(Map<String, dynamic> map) {
    return RecipeIngredient(
      rawMaterialId: map['rawMaterialId'] ?? '',
      quantity: (map['quantity'] ?? 0.0).toDouble(),
    );
  }
}

class Recipe {
  final String productId;
  final List<RecipeIngredient> ingredients;

  Recipe({
    required this.productId,
    required this.ingredients,
  });

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'ingredients': ingredients.map((x) => x.toMap()).toList(),
    };
  }

  factory Recipe.fromMap(Map<String, dynamic> map, String id) {
    return Recipe(
      productId: map['productId'] ?? id, // often recipe ID matches product ID
      ingredients: List<RecipeIngredient>.from(
        (map['ingredients'] ?? []).map((x) => RecipeIngredient.fromMap(x)),
      ),
    );
  }
}
