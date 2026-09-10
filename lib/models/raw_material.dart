class RawMaterial {
  final String id;
  final String name;
  final String unit; // kg, liters, pieces, grams
  final double currentStock;
  final double reorderLevel;

  RawMaterial({
    required this.id,
    required this.name,
    required this.unit,
    required this.currentStock,
    required this.reorderLevel,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'unit': unit,
      'currentStock': currentStock,
      'reorderLevel': reorderLevel,
    };
  }

  factory RawMaterial.fromMap(Map<String, dynamic> map, String id) {
    return RawMaterial(
      id: id,
      name: map['name'] ?? '',
      unit: map['unit'] ?? '',
      currentStock: (map['currentStock'] ?? 0.0).toDouble(),
      reorderLevel: (map['reorderLevel'] ?? 0.0).toDouble(),
    );
  }
}
