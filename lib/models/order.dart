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

  /// Sequence within [dayKey], shown on the receipt instead of the raw id.
  final int orderNumber;

  /// `yyyyMMdd` bucket the [orderNumber] was allocated from.
  final String dayKey;

  final double? cashTendered;
  final String? notes;
  final String? tableLabel;
  final String? customerName;
  final String? cashierId;

  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancelReason;

  CafeOrder({
    required this.id,
    required this.timestamp,
    required this.items,
    required this.subtotal,
    required this.totalGst,
    required this.grandTotal,
    required this.paymentMethod,
    required this.status,
    this.orderNumber = 0,
    this.dayKey = '',
    this.cashTendered,
    this.notes,
    this.tableLabel,
    this.customerName,
    this.cashierId,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason,
  });

  /// Human-friendly reference such as `#014`, reset every day.
  String get displayNumber =>
      orderNumber > 0 ? '#${orderNumber.toString().padLeft(3, '0')}' : '#$id';

  bool get isCancelled => status == OrderStatus.cancelled;

  /// Cancelled orders are excluded from every revenue figure.
  bool get countsTowardsSales => status == OrderStatus.completed;

  double? get changeDue {
    final tendered = cashTendered;
    if (tendered == null) return null;
    final change = tendered - grandTotal;
    return change > 0 ? change : 0;
  }

  /// GST totals keyed by rate, for the receipt's tax summary.
  Map<double, double> get gstByRate {
    final byRate = <double, double>{};
    for (final item in items) {
      byRate.update(
        item.gstRate,
        (value) => value + item.gstAmount,
        ifAbsent: () => item.gstAmount,
      );
    }
    return byRate;
  }

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
      'orderNumber': orderNumber,
      'dayKey': dayKey,
      if (cashTendered != null) 'cashTendered': cashTendered,
      if (notes != null) 'notes': notes,
      if (tableLabel != null) 'tableLabel': tableLabel,
      if (customerName != null) 'customerName': customerName,
      if (cashierId != null) 'cashierId': cashierId,
      if (cancelledAt != null) 'cancelledAt': cancelledAt!.toIso8601String(),
      if (cancelledBy != null) 'cancelledBy': cancelledBy,
      if (cancelReason != null) 'cancelReason': cancelReason,
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
      orderNumber: (map['orderNumber'] as num?)?.toInt() ?? 0,
      dayKey: map['dayKey'] as String? ?? '',
      cashTendered: (map['cashTendered'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      tableLabel: map['tableLabel'] as String?,
      customerName: map['customerName'] as String?,
      cashierId: map['cashierId'] as String?,
      cancelledAt: map['cancelledAt'] == null
          ? null
          : DateTime.tryParse(map['cancelledAt'] as String),
      cancelledBy: map['cancelledBy'] as String?,
      cancelReason: map['cancelReason'] as String?,
    );
  }
}
