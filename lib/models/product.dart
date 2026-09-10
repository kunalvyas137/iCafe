enum ProductType { mrp, inHouse }

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

  /// Stock at or below this triggers the low-stock alert. 0 disables it.
  final double reorderLevel;

  Product({
    required this.id,
    required this.name,
    required this.type,
    required this.price,
    required this.gstRate,
    this.sku,
    this.imageUrl,
    this.isAvailable = true,
    this.currentStock = 0,
    this.reorderLevel = 0,
  });

  Product copyWith({
    String? name,
    ProductType? type,
    double? price,
    double? gstRate,
    String? sku,
    bool? isAvailable,
    double? currentStock,
    double? reorderLevel,
  }) {
    return Product(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      price: price ?? this.price,
      gstRate: gstRate ?? this.gstRate,
      sku: sku ?? this.sku,
      imageUrl: imageUrl,
      isAvailable: isAvailable ?? this.isAvailable,
      currentStock: currentStock ?? this.currentStock,
      reorderLevel: reorderLevel ?? this.reorderLevel,
    );
  }

  /// In-house products are made to order and draw down raw materials through
  /// their recipe, so only MRP products carry their own stock count.
  bool get tracksStock => type == ProductType.mrp;

  bool get isSoldOut => !isAvailable || (tracksStock && currentStock <= 0);

  bool get isLowStock =>
      tracksStock &&
      reorderLevel > 0 &&
      currentStock > 0 &&
      currentStock <= reorderLevel;

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
    };
  }

  factory Product.fromMap(Map<String, dynamic> map, String id) {
    return Product(
      id: id,
      name: map['name'] ?? '',
      type: map['type'] == 'inHouse' ? ProductType.inHouse : ProductType.mrp,
      price: (map['price'] ?? 0.0).toDouble(),
      gstRate: (map['gstRate'] ?? 0.0).toDouble(),
      sku: map['sku'],
      imageUrl: map['imageUrl'],
      isAvailable: map['isAvailable'] ?? true,
      currentStock: (map['currentStock'] ?? 0.0).toDouble(),
      reorderLevel: (map['reorderLevel'] ?? 0.0).toDouble(),
    );
  }
}
