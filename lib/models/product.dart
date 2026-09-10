enum ProductType {
  mrp,
  inHouse,
}

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
  });

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
    );
  }
}
