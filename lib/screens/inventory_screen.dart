import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import '../models/raw_material.dart';
import '../services/ai_inventory_service.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        automaticallyImplyLeading: false,
        actions: [
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
          final tabIndex = _tabController.index;
          if (tabIndex == 0) {
            return FloatingActionButton.extended(
              onPressed: _showAddProductDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Product'),
            );
          }
          return FloatingActionButton.extended(
            onPressed: _showAddRawMaterialDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add Material'),
          );
        },
      ),
    );
  }

  Future<void> _scanInvoice() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Analyzing invoice with AI...')),
        );
      }
      await AiInventoryService.scanInvoice(image);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inventory updated from invoice!')),
        );
      }
    }
  }

  Future<void> _showAddProductDialog() async {
    final formKey = GlobalKey<FormState>();
    String name = '';
    ProductType type = ProductType.mrp;
    double price = 0.0;
    double gstRate = 0.0;
    String sku = '';
    double currentStock = 0.0;

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Product'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Product Name'),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Required' : null,
                  onSaved: (value) => name = value?.trim() ?? '',
                ),
                DropdownButtonFormField<ProductType>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: ProductType.values
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(
                            t == ProductType.mrp ? 'MRP' : 'In-house',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => type = value ?? ProductType.mrp,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Price (₹)'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Required';
                    if (double.tryParse(value) == null) return 'Invalid number';
                    return null;
                  },
                  onSaved: (value) =>
                      price = double.tryParse(value ?? '0') ?? 0.0,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'GST Rate (%)'),
                  keyboardType: TextInputType.number,
                  initialValue: '0',
                  onSaved: (value) =>
                      gstRate = double.tryParse(value ?? '0') ?? 0.0,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Current Stock'),
                  keyboardType: TextInputType.number,
                  initialValue: '0',
                  onSaved: (value) =>
                      currentStock = double.tryParse(value ?? '0') ?? 0.0,
                ),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'SKU (optional)',
                  ),
                  onSaved: (value) => sku = value?.trim() ?? '',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                formKey.currentState?.save();
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (shouldSave == true) {
      final docRef = FirebaseFirestore.instance.collection('products').doc();
      final product = Product(
        id: docRef.id,
        name: name,
        type: type,
        price: price,
        gstRate: gstRate,
        sku: sku.isEmpty ? null : sku,
        currentStock: currentStock,
      );
      final map = product.toMap()..['id'] = docRef.id;
      await docRef.set(map);
    }
  }

  Future<void> _showAddRawMaterialDialog() async {
    final formKey = GlobalKey<FormState>();
    String name = '';
    String unit = 'kg';
    double currentStock = 0.0;
    double reorderLevel = 0.0;

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Raw Material'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Material Name'),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Required' : null,
                  onSaved: (value) => name = value?.trim() ?? '',
                ),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Unit (kg, liters, pieces...)',
                  ),
                  initialValue: 'kg',
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Required' : null,
                  onSaved: (value) => unit = value?.trim() ?? 'kg',
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Current Stock'),
                  keyboardType: TextInputType.number,
                  initialValue: '0',
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Required';
                    if (double.tryParse(value) == null) return 'Invalid number';
                    return null;
                  },
                  onSaved: (value) =>
                      currentStock = double.tryParse(value ?? '0') ?? 0.0,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Reorder Level'),
                  keyboardType: TextInputType.number,
                  initialValue: '0',
                  onSaved: (value) =>
                      reorderLevel = double.tryParse(value ?? '0') ?? 0.0,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                formKey.currentState?.save();
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (shouldSave == true) {
      final docRef = FirebaseFirestore.instance
          .collection('raw_materials')
          .doc();
      final material = RawMaterial(
        id: docRef.id,
        name: name,
        unit: unit,
        currentStock: currentStock,
        reorderLevel: reorderLevel,
      );
      final map = material.toMap()..['id'] = docRef.id;
      await docRef.set(map);
    }
  }

  Widget _buildProductsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('products').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Error loading products'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text('No products available. Tap + Add Product.'),
          );
        }

        final products = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: products.length,
          itemBuilder: (context, index) {
            final doc = products[index];
            final product = Product.fromMap(
              doc.data() as Map<String, dynamic>,
              doc.id,
            );

            return Card(
              child: ListTile(
                leading: const Icon(Icons.fastfood),
                title: Text(product.name),
                subtitle: Text(
                  '${product.type == ProductType.inHouse ? "In-house" : "MRP"} • ₹${product.price} • Stock: ${product.currentStock}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    // TODO: Edit product
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRawMaterialsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('raw_materials')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Error loading materials'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text('No raw materials. Tap + Add Material.'),
          );
        }

        final materials = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: materials.length,
          itemBuilder: (context, index) {
            final doc = materials[index];
            final material = RawMaterial.fromMap(
              doc.data() as Map<String, dynamic>,
              doc.id,
            );

            return Card(
              child: ListTile(
                leading: const Icon(Icons.science),
                title: Text(material.name),
                subtitle: Text(
                  'Stock: ${material.currentStock} ${material.unit}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () {
                    // TODO: Update stock manually
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}
