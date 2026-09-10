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
                        decoration: InputDecoration(
                          hintText: 'Search products...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner, size: 32, color: Colors.blue),
                      onPressed: () {
                        _showBarcodeScanner(context);
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('products').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Center(child: Text('Error loading products'));
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(child: Text('No products available. Add them in Firebase.'));
                    }

                    final products = snapshot.data!.docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return Product(
                        id: doc.id,
                        name: data['name'] ?? '',
                        type: data['type'] == ProductType.inHouse.name ? ProductType.inHouse : ProductType.mrp,
                        price: (data['price'] ?? 0.0).toDouble(),
                        gstRate: (data['gstRate'] ?? 0.0).toDouble(),
                        imageUrl: data['imageUrl'],
                      );
                    }).toList();

                    return GridView.builder(
                      padding: const EdgeInsets.all(8.0),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 1.0,
                        crossAxisSpacing: 8.0,
                        mainAxisSpacing: 8.0,
                      ),
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final product = products[index];
                        return Card(
                          elevation: 2,
                          child: InkWell(
                            onTap: () {
                              context.read<CartProvider>().addProduct(product);
                            },
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: product.imageUrl != null
                                      ? ClipRRect(
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                          child: Image.network(
                                            product.imageUrl!,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.fastfood, size: 40, color: Colors.amber),
                                          ),
                                        )
                                      : const Center(child: Icon(Icons.fastfood, size: 40, color: Colors.amber)),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                                  child: Column(
                                    children: [
                                      Text(
                                        product.name,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text('₹${product.price}'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                          onPressed: () {
                            cart.clearCart();
                          },
                        )
                      ],
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: cart.items.length,
                        itemBuilder: (context, index) {
                          final item = cart.items[index];
                          return ListTile(
                            title: Text(item.productName),
                            subtitle: Text('${item.quantity} x ₹${item.price}'),
                            trailing: Text('₹${item.totalWithoutGst}'),
                            onLongPress: () => cart.removeProduct(item.productId),
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
                              const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                              Text('₹${cart.grandTotal.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: cart.items.isEmpty ? Colors.grey : Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: cart.items.isEmpty ? null : () {
                                _showPaymentModal(context, cart);
                              },
                              child: Text('Charge ₹${cart.grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18)),
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
    final String upiId = 'cafe@upi'; // Replace with actual UPI ID
    final String payeeName = 'iCafe';
    final String upiUrl = 'upi://pay?pa=$upiId&pn=$payeeName&am=${cart.grandTotal}&cu=INR';

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
                Text('Amount: ₹${cart.grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Scan Barcode'),
          content: SizedBox(
            width: 300,
            height: 300,
            child: MobileScanner(
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final String? code = barcodes.first.rawValue;
                  if (code != null) {
                    Navigator.pop(context);
                    // TODO: Lookup product by barcode (SKU) and add to cart
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Scanned: $code. Added to cart!')),
                    );
                  }
                }
              },
            ),
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
}
