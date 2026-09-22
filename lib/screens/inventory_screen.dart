import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/product.dart';
import '../models/raw_material.dart';
import '../models/recipe.dart';
import '../models/store_settings.dart';
import '../services/ai_inventory_service.dart';
import '../services/inventory_service.dart';
import '../services/invoice_matcher.dart';
import '../services/settings_service.dart';
import '../widgets/product_image_picker.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StoreSettings _store = StoreSettings.defaults;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadStore();
    InventoryService.ensureMigrated();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStore() async {
    try {
      final store = await SettingsService.load();
      if (mounted) setState(() => _store = store);
    } catch (_) {
      // Defaults are fine; the GST rate is only a form prefill.
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan Barcode → Inventory',
            onPressed: _scanBarcode,
          ),
          IconButton(
            icon: const Icon(Icons.document_scanner),
            tooltip: 'Scan Invoice',
            onPressed: _scanInvoice,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Products (Menu)'),
            Tab(text: 'Raw Materials & Stock'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildProductsTab(), _buildRawMaterialsTab()],
      ),
      floatingActionButton: ListenableBuilder(
        listenable: _tabController,
        builder: (context, _) {
          if (_tabController.index == 0) {
            return FloatingActionButton.extended(
              onPressed: () => _editProduct(),
              icon: const Icon(Icons.add),
              label: const Text('Add Product'),
            );
          }
          return FloatingActionButton.extended(
            onPressed: () => _editRawMaterial(),
            icon: const Icon(Icons.add),
            label: const Text('Add Material'),
          );
        },
      ),
    );
  }

  /// Opens a barcode scanner. On match → stock-adjust dialog.
  /// On no match → pre-fills Add Product dialog with scanned SKU.
  Future<void> _scanBarcode() async {
    bool handling = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Scan Barcode'),
        content: SizedBox(
          width: 320,
          height: 320,
          child: MobileScanner(
            onDetect: (capture) async {
              if (handling) return;
              final code = capture.barcodes
                  .map((b) => b.rawValue)
                  .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
              if (code == null) return;
              handling = true;
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (!mounted) return;

              _showMessage('Looking up SKU: $code…');
              final product = await InventoryService.findBySku(code);

              if (!mounted) return;
              if (product != null) {
                // Found → open stock adjust dialog
                final adjustment = await showDialog<_StockAdjustment>(
                  context: context,
                  builder: (_) => _StockAdjustmentDialog(
                    material: RawMaterial(
                      id: product.id,
                      name: product.name,
                      unit: product.unit,
                      currentStock: product.currentStock,
                      reorderLevel: product.reorderLevel,
                    ),
                  ),
                );
                if (adjustment == null || !mounted) return;
                try {
                  final updated = await InventoryService.adjustStock(
                    product.id,
                    adjustment.delta,
                    reason: adjustment.reason,
                  );
                  _showMessage(
                    '${product.name} now ${updated.toStringAsFixed(2)} ${product.unit}',
                  );
                } on InventoryException catch (e) {
                  _showMessage(e.message, isError: true);
                } catch (e) {
                  _showMessage('Could not adjust stock: $e', isError: true);
                }
              } else {
                // Not found → open add product dialog with SKU pre-filled
                _showMessage('SKU $code not found — create a new item?');
                _editProductWithSku(code);
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
      ),
    );
  }

  /// Opens the Add Product dialog with [sku] pre-filled.
  Future<void> _editProductWithSku(String sku) async {
    final stub = Product(
      id: '',
      name: '',
      type: ProductType.mrp,
      sku: sku,
    );
    await _editProduct(existing: stub, isSku: true);
  }

  Future<void> _scanInvoice() async {
    if (!AiInventoryService.isConfigured) {
      _showMessage(
        'Invoice scanning needs a Gemini key: rebuild with '
        '--dart-define=GEMINI_API_KEY=<key>.',
        isError: true,
      );
      return;
    }

    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('Upload PDF'),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    Uint8List? bytes;
    String? mimeType;

    if (source == 'pdf') {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (result == null || result.isEmpty) return;
      bytes = await result.first.readAsBytes();
      mimeType = 'application/pdf';
    } else {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
      );
      if (image == null) return;
      bytes = await image.readAsBytes();
      mimeType = image.mimeType ?? 'image/jpeg';
    }

    if (bytes == null || mimeType == null) return;

    _showMessage('Reading the invoice with AI...');
    List<ParsedInvoiceLine> lines;
    try {
      lines = await AiInventoryService.scanFile(bytes, mimeType);
    } on AiInvoiceException catch (e) {
      _showMessage(e.message, isError: true);
      return;
    } catch (e) {
      _showMessage('Could not read the invoice: $e', isError: true);
      return;
    }
    if (!mounted) return;

    final receipts = await showDialog<List<StockReceipt>>(
      context: context,
      builder: (_) => _InvoiceReviewDialog(lines: lines),
    );
    if (receipts == null || receipts.isEmpty) return;

    try {
      final created = await InventoryService.receiveStock(receipts);
      _showMessage(
        created == 0
            ? 'Stock updated for ${receipts.length} materials.'
            : 'Stock updated for ${receipts.length} materials, $created newly added.',
      );
    } on InventoryException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (e) {
      _showMessage('Could not update stock: $e', isError: true);
    }
  }

  Future<void> _editProduct({Product? existing, bool isSku = false}) async {
    final result = await showDialog<Product>(
      context: context,
      builder: (_) => _ProductDialog(
        product: existing,
        defaultGstRate: _store.defaultGstRate,
        // When called from barcode scan, treat as new even if product stub has a SKU
        forceNew: isSku,
      ),
    );
    if (result == null) return;
    try {
      if (existing == null || isSku) {
        await InventoryService.createProduct(result);
        _showMessage('${result.name} added');
      } else {
        await InventoryService.updateProduct(result);
        _showMessage('${result.name} updated');
      }
    } catch (e) {
      _showMessage('Could not save the product: $e', isError: true);
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await _confirm(
      title: 'Delete ${product.name}?',
      message: 'It disappears from the POS menu. Past orders keep their lines.',
    );
    if (!confirmed) return;
    try {
      await InventoryService.deleteProduct(product.id);
      _showMessage('${product.name} deleted');
    } catch (e) {
      _showMessage('Could not delete the product: $e', isError: true);
    }
  }

  Future<void> _editRecipe(Product product) async {
    final recipe = await InventoryService.loadRecipe(product.id);
    if (!mounted) return;
    final saved = await showDialog<Recipe>(
      context: context,
      builder: (_) => _RecipeDialog(product: product, recipe: recipe),
    );
    if (saved == null) return;
    try {
      await InventoryService.saveRecipe(saved);
      _showMessage('Recipe for ${product.name} saved');
    } catch (e) {
      _showMessage('Could not save the recipe: $e', isError: true);
    }
  }

  Future<void> _editRawMaterial([RawMaterial? existing]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RawMaterialDialog(
        material: existing,
        defaultGstRate: _store.defaultGstRate,
      ),
    );
    if (result == null) return;
    try {
      final name = result['name'] as String;
      final unit = result['unit'] as String;
      final stock = result['stock'] as double;
      final reorderLevel = result['reorderLevel'] as double;
      final sellOnPos = result['sellOnPos'] as bool? ?? false;
      final price = result['price'] as double? ?? 0.0;
      final gstRate = result['gstRate'] as double? ?? 0.0;

      if (existing == null) {
        if (sellOnPos) {
          final product = Product(
            id: '',
            name: name,
            type: ProductType.mrp,
            unit: unit,
            currentStock: stock,
            reorderLevel: reorderLevel,
            price: price,
            gstRate: gstRate,
            isSellable: true,
            isAvailable: true,
          );
          await InventoryService.createProduct(product);
          _showMessage('$name added & listed on POS menu!');
        } else {
          final material = RawMaterial(
            id: '',
            name: name,
            unit: unit,
            currentStock: stock,
            reorderLevel: reorderLevel,
          );
          await InventoryService.createRawMaterial(material);
          _showMessage('$name added to stock');
        }
      } else {
        if (sellOnPos) {
          final product = Product(
            id: existing.id,
            name: name,
            type: ProductType.mrp,
            unit: unit,
            currentStock: stock,
            reorderLevel: reorderLevel,
            price: price,
            gstRate: gstRate,
            isSellable: true,
            isAvailable: true,
          );
          await InventoryService.createProduct(product);
          _showMessage('$name updated & listed on POS');
        } else {
          final material = RawMaterial(
            id: existing.id,
            name: name,
            unit: unit,
            currentStock: stock,
            reorderLevel: reorderLevel,
          );
          await InventoryService.updateRawMaterial(material);
          _showMessage('$name updated');
        }
      }
    } catch (e) {
      _showMessage('Could not save the material: $e', isError: true);
    }
  }

  Future<void> _publishToPos(RawMaterial material) async {
    final result = await showDialog<Map<String, double>>(
      context: context,
      builder: (context) => _PublishToPosDialog(
        materialName: material.name,
        defaultGstRate: _store.defaultGstRate,
      ),
    );
    if (result == null) return;
    try {
      await InventoryService.publishToPos(
        material.id,
        price: result['price']!,
        gstRate: result['gstRate']!,
      );
      _showMessage('${material.name} is now listed on the POS menu!');
    } catch (e) {
      _showMessage('Could not publish to POS: $e', isError: true);
    }
  }

  Future<void> _adjustStock(RawMaterial material) async {
    final adjustment = await showDialog<_StockAdjustment>(
      context: context,
      builder: (_) => _StockAdjustmentDialog(material: material),
    );
    if (adjustment == null) return;
    try {
      final updated = await InventoryService.adjustRawMaterialStock(
        material.id,
        adjustment.delta,
        reason: adjustment.reason,
      );
      _showMessage(
        '${material.name} now ${updated.toStringAsFixed(2)} ${material.unit}',
      );
    } on InventoryException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (e) {
      _showMessage('Could not adjust stock: $e', isError: true);
    }
  }



  Future<void> _deleteRawMaterial(RawMaterial material) async {
    final confirmed = await _confirm(
      title: 'Delete ${material.name}?',
      message: 'Recipes that still use it must be updated first.',
    );
    if (!confirmed) return;
    try {
      await InventoryService.deleteRawMaterial(material.id);
      _showMessage('${material.name} deleted');
    } on InventoryException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (e) {
      _showMessage('Could not delete the material: $e', isError: true);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _buildProductsTab() {
    return StreamBuilder<List<Product>>(
      stream: InventoryService.watchProducts(sellableOnly: true),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading products: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final products = snapshot.data!;
        if (products.isEmpty) {
          return const Center(
            child: Text('No products available. Tap + Add Product.'),
          );
        }

        final alerts = products
            .where((product) => product.isSoldOut || product.isLowStock)
            .toList();

        return ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            if (alerts.isNotEmpty)
              _AlertBanner(
                title: '${alerts.length} product(s) need attention',
                lines: alerts
                    .map(
                      (product) => product.isSoldOut
                          ? '${product.name} — sold out'
                          : '${product.name} — ${product.currentStock.toStringAsFixed(0)} left',
                    )
                    .toList(),
              ),
            ...products.map(
              (product) => Card(
                child: ListTile(
                  leading: Icon(
                    Icons.fastfood,
                    color: product.isSoldOut
                        ? Colors.red.shade400
                        : product.isLowStock
                        ? Colors.orange.shade700
                        : null,
                  ),
                  title: Row(
                    children: [
                      Flexible(child: Text(product.name)),
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          product.displayCategory,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      if (!product.isAvailable)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Chip(
                            label: Text('Hidden'),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    '${product.type == ProductType.inHouse ? "In-house" : product.type == ProductType.rawMaterial ? "Raw Material" : "MRP"} '
                    '• ₹${product.price.toStringAsFixed(2)} '
                    '• GST ${product.gstRate.toStringAsFixed(0)}% '
                    '${product.tracksStock ? "• Stock: ${product.currentStock % 1 == 0 ? product.currentStock.toInt() : product.currentStock.toStringAsFixed(2)}${product.unit.isNotEmpty && product.unit != 'pcs' ? ' ${product.unit}' : ''}" : "• Made to order"}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (product.type == ProductType.inHouse)
                        IconButton(
                          icon: const Icon(Icons.menu_book),
                          tooltip: 'Recipe',
                          onPressed: () => _editRecipe(product),
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Edit',
                        onPressed: () => _editProduct(existing: product),
                      ),
                      IconButton(
                        icon: Icon(
                          product.isAvailable
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        tooltip: product.isAvailable
                            ? 'Hide from POS'
                            : 'Show on POS',
                        onPressed: () => InventoryService.setAvailability(
                          product.id,
                          !product.isAvailable,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete',
                        onPressed: () => _deleteProduct(product),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRawMaterialsTab() {
    return StreamBuilder<List<RawMaterial>>(
      stream: InventoryService.watchRawMaterials(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading materials: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final materials = snapshot.data!;
        if (materials.isEmpty) {
          return const Center(
            child: Text('No raw materials. Tap + Add Material.'),
          );
        }

        final alerts = materials.where((m) => m.isLowStock).toList();

        return ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            if (alerts.isNotEmpty)
              _AlertBanner(
                title: '${alerts.length} material(s) at or below reorder level',
                lines: alerts
                    .map(
                      (m) =>
                          '${m.name} — ${m.currentStock.toStringAsFixed(2)} ${m.unit} '
                          '(reorder at ${m.reorderLevel.toStringAsFixed(2)})',
                    )
                    .toList(),
              ),
            ...materials.map(
              (material) => Card(
                child: ListTile(
                  leading: Icon(
                    Icons.science,
                    color: material.isOutOfStock
                        ? Colors.red.shade400
                        : material.isLowStock
                        ? Colors.orange.shade700
                        : null,
                  ),
                  title: Text(material.name),
                  subtitle: Text(
                    'Stock: ${material.currentStock.toStringAsFixed(2)} ${material.unit} '
                    '• Reorder at ${material.reorderLevel.toStringAsFixed(2)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.point_of_sale, color: Colors.teal),
                        tooltip: 'List on POS menu',
                        onPressed: () => _publishToPos(material),
                      ),
                      IconButton(
                        icon: const Icon(Icons.tune),
                        tooltip: 'Adjust stock',
                        onPressed: () => _adjustStock(material),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Edit',
                        onPressed: () => _editRawMaterial(material),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete',
                        onPressed: () => _deleteRawMaterial(material),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...lines.take(6).map(Text.new),
            if (lines.length > 6) Text('and ${lines.length - 6} more…'),
          ],
        ),
      ),
    );
  }
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({
    this.product,
    required this.defaultGstRate,
    this.forceNew = false,
  });

  final Product? product;
  final double defaultGstRate;
  /// When true the dialog acts as "Add" even if [product] has some pre-filled values.
  final bool forceNew;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _price;
  late final TextEditingController _gstRate;
  late final TextEditingController _stock;
  late final TextEditingController _reorderLevel;
  late final TextEditingController _sku;
  late ProductType _type;
  late bool _isAvailable;
  late bool _isTaxInclusive;
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _category = TextEditingController(text: product?.category ?? '');
    _price = TextEditingController(
      text: product == null ? '' : product.price.toStringAsFixed(2),
    );
    _type = product?.type ?? ProductType.mrp;
    final initialGst = product?.gstRate ?? (_type == ProductType.mrp ? 5.0 : widget.defaultGstRate);
    _gstRate = TextEditingController(
      text: initialGst.toStringAsFixed(0),
    );
    _stock = TextEditingController(
      text: (product?.currentStock ?? 0).toStringAsFixed(0),
    );
    _reorderLevel = TextEditingController(
      text: (product?.reorderLevel ?? 0).toStringAsFixed(0),
    );
    _sku = TextEditingController(text: product?.sku ?? '');
    _isAvailable = product?.isAvailable ?? true;
    _isTaxInclusive = product?.isTaxInclusive ?? (_type == ProductType.mrp);
    _imageUrl = product?.imageUrl;
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _price.dispose();
    _gstRate.dispose();
    _stock.dispose();
    _reorderLevel.dispose();
    _sku.dispose();
    super.dispose();
  }

  String? _validateNumber(String? value, {double max = double.infinity}) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final parsed = double.tryParse(value.trim());
    if (parsed == null) return 'Invalid number';
    if (parsed < 0) return 'Cannot be negative';
    if (parsed > max) return 'Too large';
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final existing = widget.forceNew ? null : widget.product;
    final product = Product(
      id: existing?.id ?? '',
      name: _name.text.trim(),
      category: _category.text.trim().isEmpty ? null : _category.text.trim(),
      type: _type,
      price: double.parse(_price.text.trim()),
      gstRate: double.parse(_gstRate.text.trim()),
      sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
      imageUrl: _imageUrl,
      isAvailable: _isAvailable,
      isTaxInclusive: _isTaxInclusive,
      currentStock: _type == ProductType.mrp
          ? double.parse(_stock.text.trim())
          : 0,
      reorderLevel: _type == ProductType.mrp
          ? double.parse(_reorderLevel.text.trim())
          : 0,
    );
    Navigator.of(context).pop(product);
  }

  @override
  Widget build(BuildContext context) {
    final tracksStock = _type == ProductType.mrp;
    final isNew = widget.forceNew || widget.product == null;

    return AlertDialog(
      title: Text(isNew ? 'Add Product' : 'Edit Product'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Product Image ─────────────────────────────────────────
                ProductImagePicker(
                  initialUrl: _imageUrl,
                  onChanged: (url) => setState(() => _imageUrl = url),
                ),
                const Divider(height: 24),
                // ─────────────────────────────────────────────────────────
                TextFormField(
                  controller: _name,
                  autofocus: isNew,
                  decoration: const InputDecoration(labelText: 'Product Name'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
                DropdownButtonFormField<ProductType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    const DropdownMenuItem(
                      value: ProductType.mrp,
                      child: Text('MRP (Packaged / Resale)'),
                    ),
                    const DropdownMenuItem(
                      value: ProductType.inHouse,
                      child: Text('In-house (Made to order)'),
                    ),
                    if (_type == ProductType.rawMaterial)
                      const DropdownMenuItem(
                        value: ProductType.rawMaterial,
                        child: Text('Raw Material (Kitchen Stock)'),
                      ),
                  ],
                  onChanged: (value) {
                    final newType = value ?? ProductType.mrp;
                    setState(() {
                      _type = newType;
                      if (widget.forceNew || widget.product == null) {
                        if (newType == ProductType.mrp) {
                          _gstRate.text = '5';
                          _isTaxInclusive = true;
                        } else {
                          _gstRate.text = widget.defaultGstRate.toStringAsFixed(0);
                          _isTaxInclusive = false;
                        }
                      }
                    });
                  },
                ),
                TextFormField(
                  controller: _category,
                  decoration: InputDecoration(
                    labelText: 'Category (optional)',
                    hintText: 'e.g. Beverages, Coffee & Tea',
                    suffixIcon: PopupMenuButton<String>(
                      icon: const Icon(Icons.arrow_drop_down),
                      tooltip: 'Preset Categories',
                      onSelected: (val) => setState(() => _category.text = val),
                      itemBuilder: (context) => const [
                        'Beverages',
                        'Coffee & Tea',
                        'Snacks & Food',
                        'Bakery & Desserts',
                        'Fresh Fruits',
                        'General',
                      ]
                          .map((cat) =>
                              PopupMenuItem(value: cat, child: Text(cat)))
                          .toList(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        'Beverages',
                        'Coffee & Tea',
                        'Snacks & Food',
                        'Bakery & Desserts',
                      ]
                          .map(
                            (cat) => ActionChip(
                              label: Text(
                                cat,
                                style: const TextStyle(fontSize: 11),
                              ),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  setState(() => _category.text = cat),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                TextFormField(
                  controller: _price,
                  decoration: const InputDecoration(labelText: 'Price (₹)'),
                  keyboardType: TextInputType.number,
                  validator: (value) => _validateNumber(value),
                ),
                TextFormField(
                  controller: _gstRate,
                  decoration: const InputDecoration(labelText: 'GST Rate (%)'),
                  keyboardType: TextInputType.number,
                  validator: (value) => _validateNumber(value, max: 100),
                ),
                CheckboxListTile(
                  title: const Text('Tax inclusive in price'),
                  value: _isTaxInclusive,
                  onChanged: (val) => setState(() => _isTaxInclusive = val ?? true),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                if (tracksStock) ...[
                  TextFormField(
                    controller: _stock,
                    decoration: const InputDecoration(
                      labelText: 'Current Stock',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) => _validateNumber(value),
                  ),
                  TextFormField(
                    controller: _reorderLevel,
                    decoration: const InputDecoration(
                      labelText: 'Low-stock alert at (0 = off)',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) => _validateNumber(value),
                  ),
                ],
                TextFormField(
                  controller: _sku,
                  decoration: const InputDecoration(
                    labelText: 'SKU / barcode (optional)',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show on POS'),
                  value: _isAvailable,
                  onChanged: (value) => setState(() => _isAvailable = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _RawMaterialDialog extends StatefulWidget {
  const _RawMaterialDialog({this.material, required this.defaultGstRate});

  final RawMaterial? material;
  final double defaultGstRate;

  @override
  State<_RawMaterialDialog> createState() => _RawMaterialDialogState();
}

class _RawMaterialDialogState extends State<_RawMaterialDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _unit;
  late final TextEditingController _stock;
  late final TextEditingController _reorderLevel;
  late final TextEditingController _price;
  late final TextEditingController _gstRate;
  bool _sellOnPos = false;

  @override
  void initState() {
    super.initState();
    final material = widget.material;
    _name = TextEditingController(text: material?.name ?? '');
    _unit = TextEditingController(text: material?.unit ?? 'pcs');
    _stock = TextEditingController(
      text: (material?.currentStock ?? 0).toStringAsFixed(2),
    );
    _reorderLevel = TextEditingController(
      text: (material?.reorderLevel ?? 0).toStringAsFixed(2),
    );
    _price = TextEditingController();
    _gstRate = TextEditingController(
      text: widget.defaultGstRate.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _stock.dispose();
    _reorderLevel.dispose();
    _price.dispose();
    _gstRate.dispose();
    super.dispose();
  }

  String? _validateNumber(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final parsed = double.tryParse(value.trim());
    if (parsed == null) return 'Invalid number';
    if (parsed < 0) return 'Cannot be negative';
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop({
      'name': _name.text.trim(),
      'unit': _unit.text.trim(),
      'stock': double.parse(_stock.text.trim()),
      'reorderLevel': double.parse(_reorderLevel.text.trim()),
      'sellOnPos': _sellOnPos,
      'price': _sellOnPos ? (double.tryParse(_price.text.trim()) ?? 0.0) : 0.0,
      'gstRate': _sellOnPos ? (double.tryParse(_gstRate.text.trim()) ?? 0.0) : 0.0,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.material == null ? 'Add Stock Item / Material' : 'Edit Material',
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Item Name'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
                TextFormField(
                  controller: _unit,
                  decoration: const InputDecoration(
                    labelText: 'Unit (pcs, cans, bottles, kg, liters...)',
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
                TextFormField(
                  controller: _stock,
                  decoration: const InputDecoration(labelText: 'Current Stock'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: _validateNumber,
                ),
                TextFormField(
                  controller: _reorderLevel,
                  decoration: const InputDecoration(labelText: 'Reorder Level'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: _validateNumber,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sell directly on POS menu?'),
                  subtitle: const Text(
                    'Makes this item immediately orderable by customers at checkout',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _sellOnPos,
                  onChanged: (val) => setState(() => _sellOnPos = val),
                ),
                if (_sellOnPos) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _price,
                    decoration: const InputDecoration(
                      labelText: 'Selling Price (₹)',
                      prefixText: '₹ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (val) {
                      if (!_sellOnPos) return null;
                      if (val == null || val.trim().isEmpty) return 'Required';
                      final p = double.tryParse(val.trim());
                      if (p == null || p <= 0) return 'Must be greater than 0';
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _gstRate,
                    decoration: const InputDecoration(
                      labelText: 'GST Rate (%)',
                      suffixText: '%',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (val) {
                      if (!_sellOnPos) return null;
                      if (val == null || val.trim().isEmpty) return 'Required';
                      final p = double.tryParse(val.trim());
                      if (p == null || p < 0) return 'Invalid rate';
                      return null;
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _PublishToPosDialog extends StatefulWidget {
  const _PublishToPosDialog({
    required this.materialName,
    required this.defaultGstRate,
  });

  final String materialName;
  final double defaultGstRate;

  @override
  State<_PublishToPosDialog> createState() => _PublishToPosDialogState();
}

class _PublishToPosDialogState extends State<_PublishToPosDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _price;
  late final TextEditingController _gstRate;

  @override
  void initState() {
    super.initState();
    _price = TextEditingController();
    _gstRate = TextEditingController(
      text: widget.defaultGstRate.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _price.dispose();
    _gstRate.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop({
      'price': double.parse(_price.text.trim()),
      'gstRate': double.parse(_gstRate.text.trim()),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('List "${widget.materialName}" on POS'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This item will become directly orderable at checkout. Its stock will decrement automatically when ordered.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _price,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Selling Price (₹)',
                  prefixText: '₹ ',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Required';
                  final p = double.tryParse(val.trim());
                  if (p == null || p <= 0) return 'Must be greater than 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _gstRate,
                decoration: const InputDecoration(
                  labelText: 'GST Rate (%)',
                  suffixText: '%',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Required';
                  final p = double.tryParse(val.trim());
                  if (p == null || p < 0) return 'Enter a valid rate';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.point_of_sale),
          label: const Text('Publish to POS'),
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _StockAdjustment {
  const _StockAdjustment(this.delta, this.reason);

  final double delta;
  final String reason;
}

class _StockAdjustmentDialog extends StatefulWidget {
  const _StockAdjustmentDialog({required this.material});

  final RawMaterial material;

  @override
  State<_StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<_StockAdjustmentDialog> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _isAddition = true;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount above zero.');
      return;
    }
    Navigator.of(
      context,
    ).pop(_StockAdjustment(_isAddition ? amount : -amount, _reason.text));
  }

  @override
  Widget build(BuildContext context) {
    final material = widget.material;

    return AlertDialog(
      title: Text('Adjust ${material.name}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'In stock: ${material.currentStock.toStringAsFixed(2)} ${material.unit}',
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.add),
                  label: Text('Received'),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.remove),
                  label: Text('Wastage'),
                ),
              ],
              selected: {_isAddition},
              onSelectionChanged: (selection) =>
                  setState(() => _isAddition = selection.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Amount (${material.unit})',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Apply')),
      ],
    );
  }
}

class _RecipeDialog extends StatefulWidget {
  const _RecipeDialog({required this.product, this.recipe});

  final Product product;
  final Recipe? recipe;

  @override
  State<_RecipeDialog> createState() => _RecipeDialogState();
}

class _RecipeDialogState extends State<_RecipeDialog> {
  late List<RecipeIngredient> _ingredients;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ingredients = List<RecipeIngredient>.from(
      widget.recipe?.ingredients ?? const <RecipeIngredient>[],
    );
  }

  void _submit() {
    if (_ingredients.any((ingredient) => ingredient.quantity <= 0)) {
      setState(() => _error = 'Every ingredient needs a quantity above zero.');
      return;
    }
    Navigator.of(
      context,
    ).pop(Recipe(productId: widget.product.id, ingredients: _ingredients));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Recipe · ${widget.product.name}'),
      content: SizedBox(
        width: 520,
        child: StreamBuilder<List<RawMaterial>>(
          stream: InventoryService.watchRawMaterials(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final materials = snapshot.data!;
            if (materials.isEmpty) {
              return const Text(
                'Add raw materials first — a recipe is built from them.',
              );
            }

            final used = _ingredients.map((i) => i.rawMaterialId).toSet();
            final unused = materials
                .where((material) => !used.contains(material.id))
                .toList();

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Quantities are what one unit of this item uses.'),
                const SizedBox(height: 12),
                if (_ingredients.isEmpty)
                  const Text('No ingredients yet.')
                else
                  ..._ingredients.asMap().entries.map((entry) {
                    final index = entry.key;
                    final ingredient = entry.value;
                    final material = materials
                        .where((m) => m.id == ingredient.rawMaterialId)
                        .firstOrNull;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              material?.name ?? 'Missing material',
                              style: TextStyle(
                                color: material == null ? Colors.red : null,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: TextFormField(
                              initialValue: ingredient.quantity.toString(),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                isDense: true,
                                suffixText: material?.unit ?? '',
                              ),
                              onChanged: (value) {
                                final quantity = double.tryParse(value.trim());
                                if (quantity == null) return;
                                setState(() {
                                  _ingredients[index] = RecipeIngredient(
                                    rawMaterialId: ingredient.rawMaterialId,
                                    quantity: quantity,
                                  );
                                });
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () =>
                                setState(() => _ingredients.removeAt(index)),
                          ),
                        ],
                      ),
                    );
                  }),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                const SizedBox(height: 12),
                if (unused.isNotEmpty)
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Add ingredient',
                    ),
                    items: unused
                        .map(
                          (material) => DropdownMenuItem(
                            value: material.id,
                            child: Text('${material.name} (${material.unit})'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _error = null;
                        _ingredients.add(
                          RecipeIngredient(rawMaterialId: value, quantity: 1),
                        );
                      });
                    },
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save recipe')),
      ],
    );
  }
}

/// Lets the operator confirm what the AI read before any stock moves: each
/// line can be matched to an existing material, booked as a new one, or
/// dropped.
class _InvoiceReviewDialog extends StatefulWidget {
  const _InvoiceReviewDialog({required this.lines});

  final List<ParsedInvoiceLine> lines;

  @override
  State<_InvoiceReviewDialog> createState() => _InvoiceReviewDialogState();
}

class _InvoiceReviewDialogState extends State<_InvoiceReviewDialog> {
  final _quantities = <int, TextEditingController>{};
  final _matches = <int, String?>{};
  final _types = <int, String>{};
  final _include = <int, bool>{};
  List<RawMaterial> _materials = [];
  List<Product> _mrpProducts = [];
  bool _matched = false;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.lines.length; i++) {
      _quantities[i] = TextEditingController(
        text: widget.lines[i].quantity.toString(),
      );
      _include[i] = true;
      _types[i] = widget.lines[i].type;
    }
  }

  @override
  void dispose() {
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _applySuggestions(List<RawMaterial> materials, List<Product> products) {
    _materials = materials;
    _mrpProducts = products.where((p) => p.type == ProductType.mrp).toList();
    if (_matched) return;
    _matched = true;
    for (var i = 0; i < widget.lines.length; i++) {
      final line = widget.lines[i];
      if (_types[i] == 'mrp') {
        _matches[i] = matchProduct(line, _mrpProducts)?.id;
      } else {
        _matches[i] = matchMaterial(line, materials)?.id;
      }
    }
  }

  Product? matchProduct(ParsedInvoiceLine line, List<Product> products) {
    final search = line.name.toLowerCase();
    for (final p in products) {
      if (p.name.toLowerCase() == search) return p;
    }
    return null;
  }

  void _submit() {
    final receipts = <StockReceipt>[];
    for (var i = 0; i < widget.lines.length; i++) {
      if (_include[i] != true) continue;
      final quantity = double.tryParse(_quantities[i]!.text.trim()) ?? 0;
      if (quantity <= 0) continue;
      final line = widget.lines[i];
      final isMrpProduct = _types[i] == 'mrp';
      final targetId = _matches[i];
      
      receipts.add(
        StockReceipt(
          name: line.name,
          quantity: quantity,
          unit: line.unit.isEmpty ? 'pcs' : line.unit,
          targetId: targetId,
          reason: 'Invoice scan',
          isMrpProduct: isMrpProduct,
          price: line.unitPrice ?? 0.0,
        ),
      );
    }
    if (receipts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one line to receive.')),
      );
      return;
    }
    Navigator.of(context).pop(receipts);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Receive stock from invoice'),
      content: SizedBox(
        width: 640,
        child: StreamBuilder<List<RawMaterial>>(
          stream: InventoryService.watchRawMaterials(),
          builder: (context, materialSnapshot) {
            return StreamBuilder<List<Product>>(
              stream: InventoryService.watchProducts(),
              builder: (context, productSnapshot) {
                if (!materialSnapshot.hasData && _materials.isEmpty) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                
                _applySuggestions(
                  materialSnapshot.data ?? _materials,
                  productSnapshot.data ?? _mrpProducts,
                );

                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.lines.length,
                  separatorBuilder: (context, index) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final line = widget.lines[index];
                    final isMrp = _types[index] == 'mrp';
                    
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Checkbox(
                          value: _include[index] ?? true,
                          onChanged: (value) =>
                              setState(() => _include[index] = value ?? false),
                        ),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              if (line.unitPrice != null)
                                Text(
                                  '₹${line.unitPrice!.toStringAsFixed(2)} per ${line.unit.isEmpty ? "unit" : line.unit}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: _quantities[index],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Qty',
                              suffixText: line.unit.isEmpty ? null : line.unit,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: _types[index],
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'mrp',
                                child: Text('MRP Product'),
                              ),
                              DropdownMenuItem(
                                value: 'raw_material',
                                child: Text('Raw Material'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null || value == _types[index]) return;
                              setState(() {
                                _types[index] = value;
                                // Re-match based on new category
                                if (value == 'mrp') {
                                  _matches[index] = matchProduct(line, _mrpProducts)?.id;
                                } else {
                                  _matches[index] = matchMaterial(line, _materials)?.id;
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String?>(
                            key: ValueKey('$_matched-${_types[index]}'), // Force rebuild when type changes
                            value: _matches[index],
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: isMrp ? 'Add to product' : 'Add to material',
                            ),
                            items: [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Create new ${isMrp ? "product" : "material"}'),
                              ),
                              if (isMrp)
                                for (final product in _mrpProducts)
                                  DropdownMenuItem<String?>(
                                    value: product.id,
                                    child: Text(
                                      product.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                              else
                                for (final material in _materials)
                                  DropdownMenuItem<String?>(
                                    value: material.id,
                                    child: Text(
                                      '${material.name} (${material.unit})',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                            ],
                            onChanged: (value) =>
                                setState(() => _matches[index] = value),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Receive stock')),
      ],
    );
  }
}

