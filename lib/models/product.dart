enum ProductType { mrp, inHouse, rawMaterial }

class Product {
  final String id;
  final String name;
  final ProductType type;
  final double price;
  final double gstRate; // e.g., 5.0, 12.0, 18.0
  final String? sku;
  final String? imageUrl;
  final bool isAvailable;
  final double currentStock;
  final double reorderLevel;
  final String unit;
  final double? costPrice;
  final String? category;
  final bool isSellable;
  final bool isIngredient;

  Product({
    required this.id,
    required this.name,
    required this.type,
    this.price = 0.0,
    this.gstRate = 0.0,
    this.sku,
    this.imageUrl,
    this.isAvailable = true,
    this.currentStock = 0,
    this.reorderLevel = 0,
    this.unit = 'pcs',
    this.costPrice,
    this.category,
    bool? isSellable,
    bool? isIngredient,
  })  : isSellable = isSellable ?? (type != ProductType.rawMaterial),
        isIngredient = isIngredient ?? (type == ProductType.rawMaterial);

  Product copyWith({
    String? id,
    String? name,
    ProductType? type,
    double? price,
    double? gstRate,
    String? sku,
    String? imageUrl,
    bool? isAvailable,
    double? currentStock,
    double? reorderLevel,
    String? unit,
    double? costPrice,
    String? category,
    bool? isSellable,
    bool? isIngredient,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      price: price ?? this.price,
      gstRate: gstRate ?? this.gstRate,
      sku: sku ?? this.sku,
      imageUrl: imageUrl ?? this.imageUrl,
      isAvailable: isAvailable ?? this.isAvailable,
      currentStock: currentStock ?? this.currentStock,
      reorderLevel: reorderLevel ?? this.reorderLevel,
      unit: unit ?? this.unit,
      costPrice: costPrice ?? this.costPrice,
      category: category ?? this.category,
      isSellable: isSellable ?? this.isSellable,
      isIngredient: isIngredient ?? this.isIngredient,
    );
  }

  /// In-house products are made to order and draw down raw materials through
  /// their recipe, whereas MRP and raw materials carry their own stock count.
  bool get tracksStock => type == ProductType.mrp || type == ProductType.rawMaterial;

  bool get isSoldOut => !isAvailable || (tracksStock && currentStock <= 0);

  bool get isLowStock =>
      tracksStock &&
      reorderLevel > 0 &&
      currentStock > 0 &&
      currentStock <= reorderLevel;

  /// Returns the explicit category if set, or intelligently infers a sensible
  /// café category from the product name for seamless backwards compatibility.
  String get displayCategory {
    if (category != null && category!.trim().isNotEmpty) {
      return category!.trim();
    }
    final n = name.toLowerCase();
    if (n.contains('coffee') ||
        n.contains('tea') ||
        n.contains('chai') ||
        n.contains('espresso') ||
        n.contains('latte') ||
        n.contains('cappuccino') ||
        n.contains('mocha')) {
      return 'Coffee & Tea';
    }
    if (n.contains('coke') ||
        (n.contains('cola') && !n.contains('chocolate')) ||
        n.contains('coca') ||
        n.contains('pepsi') ||
        n.contains('thumbs') ||
        n.contains('sprite') ||
        n.contains('fanta') ||
        n.contains('limca') ||
        n.contains('bull') ||
        n.contains('ginger ale') ||
        n.contains('schweppes') ||
        n.contains('tonic') ||
        n.contains('water') ||
        n.contains('juice') ||
        n.contains('shake') ||
        n.contains('smoothie') ||
        n.contains('soda') ||
        n.contains('drink') ||
        n.contains('beer')) {
      return 'Beverages';
    }
    if (n.contains('bhel') ||
        n.contains('chips') ||
        n.contains('peanut') ||
        n.contains('snack') ||
        n.contains('popcorn') ||
        n.contains('biscuit') ||
        n.contains('fries') ||
        n.contains('burger') ||
        n.contains('sandwich') ||
        n.contains('puff') ||
        n.contains('samosa') ||
        n.contains('toast')) {
      return 'Snacks & Food';
    }
    if (n.contains('cake') ||
        n.contains('pastry') ||
        n.contains('cookie') ||
        n.contains('muffin') ||
        n.contains('dessert') ||
        n.contains('brownie') ||
        n.contains('chocolate') ||
        n.contains('ice cream') ||
        n.contains('sweet')) {
      return 'Bakery & Desserts';
    }
    if (n.contains('guava') ||
        n.contains('amrud') ||
        n.contains('apple') ||
        n.contains('banana') ||
        n.contains('orange') ||
        n.contains('fruit')) {
      return 'Fresh Fruits';
    }
    return 'General';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'price': price,
      'gstRate': gstRate,
      'sku': sku,
      'imageUrl': imageUrl,
      'isAvailable': isAvailable,
      'currentStock': currentStock,
      'reorderLevel': reorderLevel,
      'unit': unit,
      if (costPrice != null) 'costPrice': costPrice,
      if (category != null && category!.trim().isNotEmpty)
        'category': category!.trim(),
      'isSellable': isSellable,
      'isIngredient': isIngredient,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map, String id) {
    final typeStr = map['type'] as String?;
    final ProductType type;
    if (typeStr == 'inHouse') {
      type = ProductType.inHouse;
    } else if (typeStr == 'rawMaterial') {
      type = ProductType.rawMaterial;
    } else {
      type = ProductType.mrp;
    }

    final defaultIsSellable = type != ProductType.rawMaterial;
    final defaultIsIngredient = type == ProductType.rawMaterial;

    return Product(
      id: id,
      name: map['name'] ?? '',
      type: type,
      price: (map['price'] ?? 0.0).toDouble(),
      gstRate: (map['gstRate'] ?? 0.0).toDouble(),
      sku: map['sku'],
      imageUrl: map['imageUrl'],
      isAvailable: map['isAvailable'] ?? true,
      currentStock: (map['currentStock'] ?? 0.0).toDouble(),
      reorderLevel: (map['reorderLevel'] ?? 0.0).toDouble(),
      unit: (map['unit'] ?? 'pcs').toString(),
      costPrice: (map['costPrice'] as num?)?.toDouble(),
      category: map['category'] as String?,
      isSellable: map['isSellable'] ?? defaultIsSellable,
      isIngredient: map['isIngredient'] ?? defaultIsIngredient,
    );
  }
}
