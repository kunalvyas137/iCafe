import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../models/order.dart';
import 'printer_provider.dart';
import '../services/printer_service.dart';

class CartProvider with ChangeNotifier {
  final List<OrderItem> _items = [];

  List<OrderItem> get items => _items;

  double get subtotal => _items.fold(0, (sum, item) => sum + item.totalWithoutGst);
  double get totalGst => _items.fold(0, (sum, item) => sum + item.gstAmount);
  double get grandTotal => subtotal + totalGst;

  void addProduct(Product product) {
    final existingIndex = _items.indexWhere((item) => item.productId == product.id);
    if (existingIndex >= 0) {
      final existingItem = _items[existingIndex];
      _items[existingIndex] = OrderItem(
        productId: existingItem.productId,
        productName: existingItem.productName,
        price: existingItem.price,
        quantity: existingItem.quantity + 1,
        gstRate: existingItem.gstRate,
      );
    } else {
      _items.add(OrderItem(
        productId: product.id,
        productName: product.name,
        price: product.price,
        quantity: 1,
        gstRate: product.gstRate,
      ));
    }
    notifyListeners();
  }

  void removeProduct(String productId) {
    _items.removeWhere((item) => item.productId == productId);
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }

  Future<void> checkout(PaymentMethod method, BuildContext context) async {
    final newOrder = CafeOrder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      items: List.from(_items),
      subtotal: subtotal,
      totalGst: totalGst,
      grandTotal: grandTotal,
      timestamp: DateTime.now(),
      status: OrderStatus.completed,
      paymentMethod: method,
    );

    try {
      final batch = FirebaseFirestore.instance.batch();

      // 1. Add order to batch
      final orderRef = FirebaseFirestore.instance.collection('orders').doc(newOrder.id);
      batch.set(orderRef, newOrder.toMap());

      // 2. Deduct inventory based on recipes
      for (var item in _items) {
        final productDoc = await FirebaseFirestore.instance.collection('products').doc(item.productId).get();
        if (!productDoc.exists) continue;

        final typeStr = productDoc.data()?['type'] ?? '';
        
        // If it's an inHouse product, we need to deduct its raw materials via the recipe engine
        if (typeStr == ProductType.inHouse.name) {
          final recipeDoc = await FirebaseFirestore.instance.collection('recipes').doc(item.productId).get();
          if (recipeDoc.exists) {
            final ingredients = recipeDoc.data()?['ingredients'] as List<dynamic>? ?? [];
            for (var ing in ingredients) {
              final rawMaterialId = ing['rawMaterialId'] as String;
              final quantityPerUnit = (ing['quantity'] as num).toDouble();
              final totalDeduction = quantityPerUnit * item.quantity;
              
              final rawMatRef = FirebaseFirestore.instance.collection('raw_materials').doc(rawMaterialId);
              batch.update(rawMatRef, {'currentStock': FieldValue.increment(-totalDeduction)});
            }
          }
        } else {
          // If it's an MRP product, deduct the direct product stock (if tracked)
          final hasStock = productDoc.data()?.containsKey('currentStock') ?? false;
          if (hasStock) {
             final productRef = FirebaseFirestore.instance.collection('products').doc(item.productId);
             batch.update(productRef, {'currentStock': FieldValue.increment(-item.quantity)});
          }
        }
      }

      await batch.commit();
      print('Order ${newOrder.id} successfully pushed to Firestore with Inventory Deduction');
      
      // Print the receipt
      if (context.mounted) {
        final printerProvider = context.read<PrinterProvider>();
        if (printerProvider.isConnected) {
          final bytes = await PrinterService.generateBillTicket(newOrder);
          final success = await printerProvider.printBytes(bytes);
          if (!success) {
            print('Failed to print receipt.');
          }
        }
      }

      clearCart();
    } catch (e) {
      print('Error pushing order to Firestore: $e');
    }
  }
}
