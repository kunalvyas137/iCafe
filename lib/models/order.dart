enum PaymentMethod { cash, upi, card, sodexo, other }
enum OrderStatus { pending, completed, cancelled }

class OrderItem {
  final String productId;
  final String productName;
  final double price;
  final int quantity;
  final double gstRate;
  
  double get totalWithoutGst => price * quantity;
  double get gstAmount => totalWithoutGst * (gstRate / 100);
  double get totalWithGst => totalWithoutGst + gstAmount;

  OrderItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    required this.gstRate,
  });

  OrderItem copyWith({int? quantity}) {
    return OrderItem(
      productId: productId,
      productName: productName,
      price: price,
      quantity: quantity ?? this.quantity,
      gstRate: gstRate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'price': price,
      'quantity': quantity,
      'gstRate': gstRate,
    };
  }

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      productId: map['productId'] ?? '',
      productName: map['productName'] ?? '',
      price: (map['price'] ?? 0.0).toDouble(),
      quantity: map['quantity']?.toInt() ?? 0,
      gstRate: (map['gstRate'] ?? 0.0).toDouble(),
    );
  }
}

class CafeOrder {
  final String id;
  final DateTime timestamp;
  final List<OrderItem> items;
  final double subtotal; // Without GST
  final double totalGst;
  final double grandTotal;
  final PaymentMethod paymentMethod;
  final OrderStatus status;

  CafeOrder({
    required this.id,
    required this.timestamp,
    required this.items,
    required this.subtotal,
    required this.totalGst,
    required this.grandTotal,
    required this.paymentMethod,
    required this.status,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'items': items.map((x) => x.toMap()).toList(),
      'subtotal': subtotal,
      'totalGst': totalGst,
      'grandTotal': grandTotal,
      'paymentMethod': paymentMethod.name,
      'status': status.name,
    };
  }

  factory CafeOrder.fromMap(Map<String, dynamic> map, String id) {
    return CafeOrder(
      id: id,
      timestamp: DateTime.parse(map['timestamp']),
      items: List<OrderItem>.from(
        (map['items'] ?? []).map((x) => OrderItem.fromMap(x)),
      ),
      subtotal: (map['subtotal'] ?? 0.0).toDouble(),
      totalGst: (map['totalGst'] ?? 0.0).toDouble(),
      grandTotal: (map['grandTotal'] ?? 0.0).toDouble(),
      paymentMethod: PaymentMethod.values.firstWhere(
        (e) => e.name == map['paymentMethod'],
        orElse: () => PaymentMethod.cash,
      ),
      status: OrderStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => OrderStatus.pending,
      ),
    );
  }
}
