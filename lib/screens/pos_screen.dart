import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import '../models/order.dart';
import '../models/store_settings.dart';
import '../providers/cart_provider.dart';
import '../providers/printer_provider.dart';
import '../services/inventory_service.dart';
import '../services/order_service.dart';
import '../services/printer_service.dart';
import '../services/settings_service.dart';
import '../services/feedback_service.dart';
import 'active_orders_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  List<Product> _catalog = const [];
  StoreSettings? _store;

  @override
  void initState() {
    super.initState();
    InventoryService.ensureMigrated();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _selectedCategory = 'All';

  List<Product> _filtered(List<Product> products) {
    final query = _query.trim().toLowerCase();
    return products.where((product) {
      if (_selectedCategory != 'All' &&
          product.displayCategory != _selectedCategory) {
        return false;
      }
      if (query.isEmpty) return true;
      return product.name.toLowerCase().contains(query) ||
          (product.sku?.toLowerCase().contains(query) ?? false) ||
          product.displayCategory.toLowerCase().contains(query);
    }).toList();
  }

  void _addToCart(Product product) {
    final error = context.read<CartProvider>().addProduct(product);
    if (error != null) {
      _showMessage(error, isError: true);
    } else {
      FeedbackService.playAdd();
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (isError) {
      FeedbackService.playError();
    }
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

  int _narrowRightTab = 0; // 0: Cart, 1: Active

  Widget _buildProductsArea(BuildContext context) {
    return Column(
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
                icon: const Icon(
                  Icons.qr_code_scanner,
                  size: 32,
                  color: Colors.blue,
                ),
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
                return const Center(
                  child: Text('Error loading products'),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(
                  child: Text(
                    'No products available. Add them in Inventory.',
                  ),
                );
              }

              _catalog = snapshot.data!.docs
                  .map(
                    (doc) => Product.fromMap(
                      doc.data() as Map<String, dynamic>,
                      doc.id,
                    ),
                  )
                  .where((product) => product.isSellable)
                  .toList();

              final Map<String, int> categoryCounts = {};
              for (final p in _catalog) {
                categoryCounts[p.displayCategory] =
                    (categoryCounts[p.displayCategory] ?? 0) + 1;
              }

              final products = _filtered(_catalog);

              return Column(
                children: [
                  _buildCategoryFilterBar(
                    categoryCounts: categoryCounts,
                    totalCount: _catalog.length,
                  ),
                  Expanded(
                    child: products.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.search_off_rounded,
                                    size: 48,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _selectedCategory != 'All'
                                        ? 'No items in "$_selectedCategory"${_query.isNotEmpty ? ' matching "${_query.trim()}"' : ''}'
                                        : 'No products match "${_query.trim()}".',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  if (_selectedCategory != 'All') ...[
                                    const SizedBox(height: 12),
                                    FilledButton.tonalIcon(
                                      onPressed: () => setState(
                                          () => _selectedCategory = 'All'),
                                      icon: const Icon(Icons.clear_all,
                                          size: 18),
                                      label:
                                          const Text('Show All Categories'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : GridView.builder(
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
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryFilterBar({
    required Map<String, int> categoryCounts,
    required int totalCount,
  }) {
    final theme = Theme.of(context);
    final sortedCategories = categoryCounts.keys.toList()..sort();
    final allCategories = ['All', ...sortedCategories];

    return Container(
      width: double.infinity,
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: allCategories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = allCategories[index];
          final isSelected = _selectedCategory == category;
          final count =
              category == 'All' ? totalCount : (categoryCounts[category] ?? 0);
          final icon = _getCategoryIcon(category);

          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() {
                  _selectedCategory = category;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.4),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.25),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 15,
                      color: isSelected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      category,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                                .withValues(alpha: 0.25)
                            : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCartPane(BuildContext context, {required bool isWide}) {
    return Consumer<CartProvider>(
      builder: (context, cart, child) {
        return Container(
          color: Colors.white, // Apple clean white for side panels
          child: Column(
            children: [
              AppBar(
                title: const Text('Current Order'),
                automaticallyImplyLeading: false,
                actions: [
                  if (!isWide)
                    StreamBuilder<List<CafeOrder>>(
                      stream: OrderService.watchActiveOrders(),
                      builder: (context, snap) {
                        final count = snap.data?.length ?? 0;
                        return IconButton(
                          tooltip: 'View Active Orders',
                          icon: Badge(
                            isLabelVisible: count > 0,
                            label: Text('$count'),
                            child: const Icon(Icons.kitchen_outlined),
                          ),
                          onPressed: () => setState(() => _narrowRightTab = 1),
                        );
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Clear cart',
                    onPressed: cart.isEmpty
                        ? null
                        : () => _confirmClearCart(cart),
                  ),
                ],
              ),
              Expanded(
                child: cart.isEmpty
                    ? const Center(
                        child: Text(
                          'Cart is empty. Tap a product to add it.',
                        ),
                      )
                    : ListView.builder(
                        itemCount: cart.items.length,
                        itemBuilder: (context, index) {
                          final item = cart.items[index];
                          return _CartLine(
                            item: item,
                            onIncrement: () => _incrementLine(cart, index),
                            onDecrement: () => _decrementLine(cart, index),
                            onDelete: () => _removeLine(cart, index),
                            onCustomize: () =>
                                _showItemModifierDialog(cart, index, item),
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
                        const Text(
                          'Total:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        Text(
                          '₹${cart.grandTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cart.isEmpty
                              ? Colors.grey.shade300
                              : const Color(0xFF34C759), // Apple Green
                          foregroundColor: cart.isEmpty ? Colors.grey.shade500 : Colors.white,
                        ),
                        onPressed: cart.isEmpty
                            ? null
                            : () => _startCheckout(cart),
                        child: Text(
                          'Charge ₹${cart.grandTotal.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1050;

        return Row(
          children: [
            // Column 1: Product Grid Area
            Expanded(
              flex: 5,
              child: _buildProductsArea(context),
            ),
            const VerticalDivider(width: 1, thickness: 1),

            if (isWide) ...[
              // Column 2: Current Order
              SizedBox(
                width: 350,
                child: _buildCartPane(context, isWide: true),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              // Column 3: Active Orders
              const SizedBox(
                width: 360,
                child: ActiveOrdersScreen(isCompact: true),
              ),
            ] else ...[
              // On narrower displays, switch between Cart and Active Orders
              SizedBox(
                width: 380,
                child: _narrowRightTab == 0
                    ? _buildCartPane(context, isWide: false)
                    : Column(
                        children: [
                          Container(
                            color: Colors.grey[100],
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Row(
                              children: [
                                TextButton.icon(
                                  icon: const Icon(Icons.arrow_back, size: 18),
                                  label: const Text('Back to Current Order'),
                                  onPressed: () =>
                                      setState(() => _narrowRightTab = 0),
                                ),
                              ],
                            ),
                          ),
                          const Expanded(
                            child: ActiveOrdersScreen(isCompact: true),
                          ),
                        ],
                      ),
              ),
            ],
          ],
        );
      },
    );
  }

  void _incrementLine(CartProvider cart, int index) {
    final item = cart.items[index];
    final product = _catalog.where((p) => p.id == item.productId).firstOrNull;
    if (product != null && product.tracksStock) {
      if (cart.quantityOf(product.id) + 1 > product.currentStock) {
        _showMessage(
          'Only ${product.currentStock.toInt()} of ${product.name} left in stock.',
          isError: true,
        );
        return;
      }
    }
    cart.incrementQuantityAt(index);
  }

  void _decrementLine(CartProvider cart, int index) {
    cart.decrementQuantityAt(index);
  }

  void _removeLine(CartProvider cart, int index) {
    final removed = cart.removeItemAt(index);
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

  void _showItemModifierDialog(CartProvider cart, int index, OrderItem item) {
    showDialog(
      context: context,
      builder: (context) => _ItemModifierDialog(
        item: item,
        onSave: (modifiers, notes) {
          cart.updateItemModifiers(
            index: index,
            modifiers: modifiers,
            notes: notes,
          );
        },
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

    final store = await _storeSettings();
    if (!mounted) return;

    final order = await showDialog<CafeOrder>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PaymentDialog(cart: cart, store: store),
    );
    if (order == null || !mounted) return;

    FeedbackService.playSuccess();
    _showMessage('Order ${order.displayNumber} completed');
    await _printReceipt(order, store);
  }

  Future<StoreSettings> _storeSettings() async {
    final cached = _store;
    if (cached != null) return cached;
    try {
      final loaded = await SettingsService.load();
      _store = loaded;
      return loaded;
    } catch (e) {
      // A missing or unreadable settings doc must not block taking money.
      debugPrint('Could not load store settings: $e');
      return StoreSettings.defaults;
    }
  }

  Future<void> _printReceipt(CafeOrder order, StoreSettings store) async {
    final printer = context.read<PrinterProvider>();
    if (!printer.isConnected) return;
    final bytes = await PrinterService.generateBillTicket(order, store: store);
    final printed = await printer.printBytes(bytes);
    if (!printed && mounted) {
      _showMessage(
        'Order saved, but the receipt did not print.',
        isError: true,
      );
    }
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
                    .firstWhere(
                      (value) => value != null && value.isNotEmpty,
                      orElse: () => null,
                    );
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
                    FeedbackService.playAdd();
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

/// Takes payment for the current cart: method, optional order details, cash
/// tendered/change, and the UPI QR built from the configured store UPI ID.
/// Pops the created [CafeOrder], or nothing if the checkout was abandoned.
class _PaymentDialog extends StatefulWidget {
  final CartProvider cart;
  final StoreSettings store;

  const _PaymentDialog({required this.cart, required this.store});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final TextEditingController _cashController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _tableController = TextEditingController();
  final TextEditingController _customerController = TextEditingController();

  PaymentMethod _method = PaymentMethod.cash;
  bool _submitting = false;
  String? _error;
  bool _showDetails = false;

  double get _total => widget.cart.grandTotal;
  double? get _tendered => double.tryParse(_cashController.text.trim());

  bool get _cashShort =>
      _method == PaymentMethod.cash && _tendered != null && _tendered! < _total;

  @override
  void dispose() {
    _cashController.dispose();
    _notesController.dispose();
    _tableController.dispose();
    _customerController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_cashShort) {
      setState(() => _error = 'Cash tendered is less than the total due.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final order = await widget.cart.checkout(
        method: _method,
        cashTendered: _method == PaymentMethod.cash ? _tendered : null,
        notes: _notesController.text,
        tableLabel: _tableController.text,
        customerName: _customerController.text,
      );
      if (mounted) Navigator.of(context).pop(order);
    } on CheckoutException catch (e) {
      // The cart is untouched, so the cashier can fix the line and retry.
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not save the order: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final change = (_tendered ?? 0) - _total;

    return AlertDialog(
      title: Text('Charge ₹${_total.toStringAsFixed(2)}'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<PaymentMethod>(
                segments: const [
                  ButtonSegment(
                    value: PaymentMethod.cash,
                    label: Text('Cash'),
                    icon: Icon(Icons.money),
                  ),
                  ButtonSegment(
                    value: PaymentMethod.upi,
                    label: Text('UPI'),
                    icon: Icon(Icons.qr_code),
                  ),
                  ButtonSegment(
                    value: PaymentMethod.card,
                    label: Text('Card'),
                    icon: Icon(Icons.credit_card),
                  ),
                  ButtonSegment(
                    value: PaymentMethod.sodexo,
                    label: Text('Sodexo'),
                    icon: Icon(Icons.card_giftcard),
                  ),
                ],
                selected: {_method},
                showSelectedIcon: false,
                onSelectionChanged: _submitting
                    ? null
                    : (selection) => setState(() {
                        _method = selection.first;
                        _error = null;
                      }),
              ),
              const SizedBox(height: 16),
              if (_method == PaymentMethod.cash) ...[
                TextField(
                  controller: _cashController,
                  autofocus: true,
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Cash tendered (optional)',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _cashPresets().map((amount) {
                    return ActionChip(
                      label: Text('₹${amount.toStringAsFixed(0)}'),
                      onPressed: _submitting
                          ? null
                          : () => setState(
                              () => _cashController.text = amount
                                  .toStringAsFixed(0),
                            ),
                    );
                  }).toList(),
                ),
                if (_tendered != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      change >= 0
                          ? 'Change due: ₹${change.toStringAsFixed(2)}'
                          : 'Short by ₹${(-change).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: change >= 0 ? Colors.green[800] : Colors.red,
                      ),
                    ),
                  ),
              ],
              if (_method == PaymentMethod.upi)
                Center(
                  child: widget.store.hasUpi
                      ? Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              color: Colors.white,
                              child: QrImageView(
                                data: widget.store.upiUri(_total),
                                version: QrVersions.auto,
                                size: 200,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(widget.store.upiId),
                            const Text(
                              'Confirm only after the payment app shows success.',
                              style: TextStyle(fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        )
                      : const Text(
                          'No UPI ID configured. Add one under Settings → Store profile.',
                          style: TextStyle(color: Colors.red),
                        ),
                ),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: Icon(
                  _showDetails ? Icons.expand_less : Icons.expand_more,
                ),
                label: const Text('Order details (optional)'),
                onPressed: () => setState(() => _showDetails = !_showDetails),
              ),
              if (_showDetails) ...[
                TextField(
                  controller: _tableController,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'Table',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _customerController,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'Customer name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesController,
                  enabled: !_submitting,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submitting || _cashShort ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(_submitting ? 'Saving...' : 'Confirm payment'),
        ),
      ],
    );
  }

  /// Note-sized amounts a cashier is likely to be handed.
  List<double> _cashPresets() {
    final presets = <double>{_total.ceilToDouble()};
    for (final note in [50, 100, 200, 500, 2000]) {
      if (note >= _total) presets.add(note.toDouble());
    }
    return presets.toList()..sort();
  }
}

IconData _getCategoryIcon(String category) {
  switch (category) {
    case 'All':
      return Icons.apps_rounded;
    case 'Coffee & Tea':
      return Icons.coffee_rounded;
    case 'Beverages':
      return Icons.local_drink_rounded;
    case 'Snacks & Food':
      return Icons.lunch_dining_rounded;
    case 'Bakery & Desserts':
      return Icons.cake_rounded;
    case 'Fresh Fruits':
      return Icons.eco_rounded;
    default:
      return Icons.restaurant_rounded;
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _ProductTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final soldOut = product.isSoldOut;

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          InkWell(
            onTap: soldOut ? null : onTap,
            child: Opacity(
              opacity: soldOut ? 0.35 : 1.0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        product.imageUrl != null
                            ? Image.network(
                                product.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildPlaceholder(context),
                              )
                            : _buildPlaceholder(context),
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getCategoryIcon(product.displayCategory),
                                  size: 11,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  product.displayCategory,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6.0,
                      horizontal: 8.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '₹${product.price.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            if (product.tracksStock)
                              Text(
                                '${product.currentStock % 1 == 0 ? product.currentStock.toInt() : product.currentStock.toStringAsFixed(1)}${product.unit.isNotEmpty && product.unit != 'pcs' ? ' ${product.unit}' : ''}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: product.currentStock <= 0
                                      ? Colors.red
                                      : Colors.grey[600],
                                ),
                              ),
                          ],
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    product.isAvailable ? 'OUT OF STOCK' : 'UNAVAILABLE',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
      child: Center(
        child: Icon(
          _getCategoryIcon(product.displayCategory),
          size: 38,
          color: theme.colorScheme.primary.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _CartLine extends StatelessWidget {
  final OrderItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onDelete;
  final VoidCallback onCustomize;

  const _CartLine({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
    required this.onCustomize,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasModifiers = item.modifiers.isNotEmpty;
    final hasNotes = item.notes != null && item.notes!.trim().isNotEmpty;
    final isCustomized = hasModifiers || hasNotes;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: InkWell(
        onTap: onCustomize,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '₹${item.price.toStringAsFixed(2)} each • ₹${item.totalWithoutGst.toStringAsFixed(2)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
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
                ],
              ),
              if (hasModifiers) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: item.modifiers.map((mod) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.3),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        mod,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              if (hasNotes) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.amber.shade700.withValues(alpha: 0.4),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notes, size: 12, color: Colors.amber.shade900),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          item.notes!,
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.9),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 4),
              InkWell(
                onTap: onCustomize,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isCustomized
                            ? Icons.edit_note
                            : Icons.add_circle_outline,
                        size: 13,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isCustomized
                            ? 'Edit modifiers / note'
                            : '+ Add Note / Modifiers',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemModifierDialog extends StatefulWidget {
  final OrderItem item;
  final void Function(List<String> modifiers, String? notes) onSave;

  const _ItemModifierDialog({
    required this.item,
    required this.onSave,
  });

  @override
  State<_ItemModifierDialog> createState() => _ItemModifierDialogState();
}

class _ItemModifierDialogState extends State<_ItemModifierDialog> {
  late final Set<String> _selectedModifiers;
  late final TextEditingController _noteController;

  static const Map<String, List<String>> _modifierCategories = {
    'Milk & Dairy': [
      'Oat Milk',
      'Almond Milk',
      'Soy Milk',
      'Skim Milk',
      'Extra Milk',
    ],
    'Sweetness': [
      'No Sugar',
      'Less Sugar (50%)',
      'Sugar Free',
      'Honey',
      'Extra Sweet',
    ],
    'Temperature & Ice': [
      'Extra Hot',
      'Warm',
      'Less Ice',
      'No Ice',
      'Normal Ice',
    ],
    'Coffee & Strength': [
      'Extra Shot',
      'Double Shot',
      'Decaf',
      'Strong',
      'Light',
    ],
    'Food & Kitchen Prep': [
      'Spicy',
      'Less Spicy',
      'No Onion/Garlic',
      'Extra Cheese',
      'Crispy',
      'Pack Separately',
      'Takeaway Cup',
    ],
  };

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Milk & Dairy':
        return Icons.water_drop_outlined;
      case 'Sweetness':
        return Icons.cookie_outlined;
      case 'Temperature & Ice':
        return Icons.ac_unit_outlined;
      case 'Coffee & Strength':
        return Icons.coffee_outlined;
      case 'Food & Kitchen Prep':
        return Icons.restaurant_outlined;
      default:
        return Icons.tune;
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedModifiers = Set<String>.from(widget.item.modifiers);
    _noteController = TextEditingController(text: widget.item.notes ?? '');
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.tune,
              size: 20,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Customize ${widget.item.productName}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '₹${widget.item.price.toStringAsFixed(2)} • Qty: ${widget.item.quantity}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 520),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ..._modifierCategories.entries.map((category) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getCategoryIcon(category.key),
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            category.key,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: category.value.map((mod) {
                          final isSelected = _selectedModifiers.contains(mod);
                          return FilterChip(
                            label: Text(mod),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedModifiers.add(mod);
                                } else {
                                  _selectedModifiers.remove(mod);
                                }
                              });
                            },
                            selectedColor: theme.colorScheme.primaryContainer,
                            checkmarkColor:
                                theme.colorScheme.onPrimaryContainer,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onSurface,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              }),
              const Divider(height: 24),
              Row(
                children: [
                  Icon(
                    Icons.edit_note,
                    size: 18,
                    color: Colors.amber.shade800,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Special Kitchen Instructions / Note',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _noteController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText:
                      'e.g. Warm well, pack separately, allergen warning...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _selectedModifiers.clear();
              _noteController.clear();
            });
          },
          child: const Text('Clear All'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Apply'),
          onPressed: () {
            final trimmedNote = _noteController.text.trim();
            widget.onSave(
              _selectedModifiers.toList(),
              trimmedNote.isEmpty ? null : trimmedNote,
            );
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}
