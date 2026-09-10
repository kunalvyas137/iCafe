import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import '../models/order.dart';
import '../providers/cart_provider.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  List<Product> _catalog = const [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Product> _filtered(List<Product> products) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return products;
    return products.where((product) {
      return product.name.toLowerCase().contains(query) ||
          (product.sku?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  void _addToCart(Product product) {
    final error = context.read<CartProvider>().addProduct(product);
    if (error != null) {
      _showMessage(error, isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : null,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Product Grid Area
        Expanded(
          flex: 2,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search products by name or SKU...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                        onChanged: (value) => setState(() => _query = value),
                        onSubmitted: _onSearchSubmitted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner,
                          size: 32, color: Colors.blue),
                      tooltip: 'Scan barcode',
                      onPressed: () => _showBarcodeScanner(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('products')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Center(child: Text('Error loading products'));
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                          child: Text('No products available. Add them in Inventory.'));
                    }

                    _catalog = snapshot.data!.docs
                        .map((doc) => Product.fromMap(
                              doc.data() as Map<String, dynamic>,
                              doc.id,
                            ))
                        .toList();

                    final products = _filtered(_catalog);
                    if (products.isEmpty) {
                      return Center(
                        child: Text('No products match "${_query.trim()}".'),
                      );
                    }

                    return GridView.builder(
                      padding: const EdgeInsets.all(8.0),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 1.0,
                        crossAxisSpacing: 8.0,
                        mainAxisSpacing: 8.0,
                      ),
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        return _ProductTile(
                          product: products[index],
                          onTap: () => _addToCart(products[index]),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        // Cart / Checkout Pane
        Expanded(
          flex: 1,
          child: Consumer<CartProvider>(
            builder: (context, cart, child) {
              return Container(
                color: Colors.grey[50],
                child: Column(
                  children: [
                    AppBar(
                      title: const Text('Current Order'),
                      automaticallyImplyLeading: false,
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Clear cart',
                          onPressed:
                              cart.isEmpty ? null : () => _confirmClearCart(cart),
                        )
                      ],
                    ),
                    Expanded(
                      child: cart.isEmpty
                          ? const Center(
                              child: Text('Cart is empty. Tap a product to add it.'),
                            )
                          : ListView.builder(
                              itemCount: cart.items.length,
                              itemBuilder: (context, index) {
                                final item = cart.items[index];
                                return _CartLine(
                                  item: item,
                                  onIncrement: () =>
                                      _incrementLine(cart, item.productId),
                                  onDecrement: () =>
                                      cart.decrementQuantity(item.productId),
                                  onDelete: () => _removeLine(cart, item.productId),
                                );
                              },
                            ),
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Subtotal:'),
                              Text('₹${cart.subtotal.toStringAsFixed(2)}'),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('GST:'),
                              Text('₹${cart.totalGst.toStringAsFixed(2)}'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total:',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 20)),
                              Text('₹${cart.grandTotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 20)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    cart.isEmpty ? Colors.grey : Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              onPressed:
                                  cart.isEmpty ? null : () => _startCheckout(cart),
                              child: Text(
                                  'Charge ₹${cart.grandTotal.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 18)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _incrementLine(CartProvider cart, String productId) {
    final product = _catalog.where((p) => p.id == productId).firstOrNull;
    if (product == null) {
      cart.incrementQuantity(productId);
      return;
    }
    final error = cart.addProduct(product);
    if (error != null) _showMessage(error, isError: true);
  }

  void _removeLine(CartProvider cart, String productId) {
    final removed = cart.removeProduct(productId);
    if (removed == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed ${removed.item.productName}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => cart.restoreItem(removed),
          ),
        ),
      );
  }

  Future<void> _confirmClearCart(CartProvider cart) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear cart?'),
        content: Text(
          'This removes all ${cart.items.length} line item(s) from the current order.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep cart'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final cleared = cart.clearCart();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Cart cleared'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => cart.restoreItems(cleared),
          ),
        ),
      );
  }

  /// Re-checks the cart against current stock before taking payment.
  Future<void> _startCheckout(CartProvider cart) async {
    final catalog = {for (final product in _catalog) product.id: product};
    final issues = cart.stockIssues(catalog);
    if (issues.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Not enough stock'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: issues.map((issue) => Text('• $issue')).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    if (!mounted) return;
    _showPaymentModal(context, cart);
  }

  void _onSearchSubmitted(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    // A hardware barcode scanner types into the search box and submits, so a
    // submitted exact SKU match is treated the same as a camera scan.
    final match = _findBySku(query);
    if (match != null) {
      _addToCart(match);
      _searchController.clear();
      setState(() => _query = '');
      return;
    }
    final matches = _filtered(_catalog);
    if (matches.length == 1) {
      _addToCart(matches.first);
      _searchController.clear();
      setState(() => _query = '');
    }
  }

  Product? _findBySku(String code) {
    final normalized = code.trim().toLowerCase();
    for (final product in _catalog) {
      if ((product.sku ?? '').toLowerCase() == normalized ||
          product.id.toLowerCase() == normalized) {
        return product;
      }
    }
    return null;
  }

  /// Falls back to Firestore when the scanned SKU is not in the streamed
  /// catalogue (e.g. a product added on another till moments ago).
  Future<Product?> _lookupSku(String code) async {
    final local = _findBySku(code);
    if (local != null) return local;

    final query = await FirebaseFirestore.instance
        .collection('products')
        .where('sku', isEqualTo: code.trim())
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    final doc = query.docs.first;
    return Product.fromMap(doc.data(), doc.id);
  }

  void _showPaymentModal(BuildContext context, CartProvider cart) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Payment Method'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.qr_code),
                title: const Text('UPI QR Code'),
                onTap: () {
                  Navigator.pop(context);
                  _showUpiQr(context, cart);
                },
              ),
              ListTile(
                leading: const Icon(Icons.money),
                title: const Text('Cash'),
                onTap: () {
                  cart.checkout(PaymentMethod.cash, context);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.credit_card),
                title: const Text('Card (POS)'),
                onTap: () {
                  cart.checkout(PaymentMethod.card, context);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.card_giftcard),
                title: const Text('Sodexo / Other Card'),
                onTap: () {
                  cart.checkout(PaymentMethod.sodexo, context);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showUpiQr(BuildContext context, CartProvider cart) {
    const String upiId = 'cafe@upi'; // Replace with actual UPI ID
    const String payeeName = 'iCafe';
    final String upiUrl =
        'upi://pay?pa=$upiId&pn=$payeeName&am=${cart.grandTotal}&cu=INR';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Scan to Pay'),
          content: SizedBox(
            width: 250,
            height: 300,
            child: Column(
              children: [
                Text('Amount: ₹${cart.grandTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Expanded(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      color: Colors.white,
                      child: QrImageView(
                        data: upiUrl,
                        version: QrVersions.auto,
                        size: 200.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                cart.checkout(PaymentMethod.upi, context);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payment Successful')),
                );
              },
              child: const Text('Mark as Paid'),
            ),
          ],
        );
      },
    );
  }

  void _showBarcodeScanner(BuildContext context) {
    bool handling = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Scan Barcode'),
          content: SizedBox(
            width: 300,
            height: 300,
            child: MobileScanner(
              onDetect: (capture) async {
                if (handling) return;
                final code = capture.barcodes
                    .map((barcode) => barcode.rawValue)
                    .firstWhere((value) => value != null && value.isNotEmpty,
                        orElse: () => null);
                if (code == null) return;

                handling = true;
                final product = await _lookupSku(code);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (!mounted) return;

                if (product == null) {
                  _showMessage('No product with SKU $code.', isError: true);
                } else {
                  _addToCart(product);
                  if (context.mounted &&
                      context.read<CartProvider>().quantityOf(product.id) > 0) {
                    _showMessage('Added ${product.name}');
                  }
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _ProductTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final soldOut = product.isSoldOut;

    return Card(
      elevation: 2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InkWell(
            onTap: soldOut ? null : onTap,
            child: Opacity(
              opacity: soldOut ? 0.4 : 1.0,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: product.imageUrl != null
                        ? ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12)),
                            child: Image.network(
                              product.imageUrl!,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.fastfood,
                                      size: 40, color: Colors.amber),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.fastfood,
                                size: 40, color: Colors.amber)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 8.0, horizontal: 4.0),
                    child: Column(
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text('₹${product.price.toStringAsFixed(2)}'),
                        if (product.tracksStock)
                          Text(
                            'Stock: ${product.currentStock.toInt()}',
                            style: TextStyle(
                              fontSize: 11,
                              color: product.currentStock <= 0
                                  ? Colors.red
                                  : Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (soldOut)
            IgnorePointer(
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: Colors.red,
                  child: Text(
                    product.isAvailable ? 'OUT OF STOCK' : 'UNAVAILABLE',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CartLine extends StatelessWidget {
  final OrderItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onDelete;

  const _CartLine({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(item.productName),
      subtitle: Text(
        '₹${item.price.toStringAsFixed(2)} each • ₹${item.totalWithoutGst.toStringAsFixed(2)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: 'Decrease quantity',
            visualDensity: VisualDensity.compact,
            onPressed: onDecrement,
          ),
          SizedBox(
            width: 24,
            child: Text(
              '${item.quantity}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Increase quantity',
            visualDensity: VisualDensity.compact,
            onPressed: onIncrement,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove item',
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
