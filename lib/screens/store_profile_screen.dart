import 'package:flutter/material.dart';
import '../models/store_settings.dart';
import '../services/settings_service.dart';

/// Admin editor for the receipt header, UPI collection details and the GST
/// rate new products default to.
class StoreProfileScreen extends StatefulWidget {
  const StoreProfileScreen({super.key});

  @override
  State<StoreProfileScreen> createState() => _StoreProfileScreenState();
}

class _StoreProfileScreenState extends State<StoreProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{
    'storeName': TextEditingController(),
    'addressLine1': TextEditingController(),
    'addressLine2': TextEditingController(),
    'phone': TextEditingController(),
    'gstin': TextEditingController(),
    'upiId': TextEditingController(),
    'upiPayeeName': TextEditingController(),
    'defaultGstRate': TextEditingController(),
    'receiptFooter': TextEditingController(),
  };

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await SettingsService.load();
      _controllers['storeName']!.text = settings.storeName;
      _controllers['addressLine1']!.text = settings.addressLine1;
      _controllers['addressLine2']!.text = settings.addressLine2;
      _controllers['phone']!.text = settings.phone;
      _controllers['gstin']!.text = settings.gstin;
      _controllers['upiId']!.text = settings.upiId;
      _controllers['upiPayeeName']!.text = settings.upiPayeeName;
      _controllers['defaultGstRate']!.text = settings.defaultGstRate.toString();
      _controllers['receiptFooter']!.text = settings.receiptFooter;
    } catch (e) {
      _error = 'Could not load store settings: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final settings = StoreSettings(
      storeName: _controllers['storeName']!.text.trim(),
      addressLine1: _controllers['addressLine1']!.text.trim(),
      addressLine2: _controllers['addressLine2']!.text.trim(),
      phone: _controllers['phone']!.text.trim(),
      gstin: _controllers['gstin']!.text.trim().toUpperCase(),
      upiId: _controllers['upiId']!.text.trim(),
      upiPayeeName: _controllers['upiPayeeName']!.text.trim(),
      defaultGstRate:
          double.tryParse(_controllers['defaultGstRate']!.text.trim()) ?? 0,
      receiptFooter: _controllers['receiptFooter']!.text.trim(),
    );

    try {
      await SettingsService.save(settings);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Store profile saved')));
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Store profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  _field('storeName', 'Store name', required: true),
                  _field('addressLine1', 'Address line 1'),
                  _field('addressLine2', 'Address line 2'),
                  _field('phone', 'Phone'),
                  _field('gstin', 'GSTIN'),
                  const Divider(height: 32),
                  _field(
                    'upiId',
                    'UPI ID (e.g. cafe@okhdfcbank)',
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return null;
                      return RegExp(
                            r'^[\w.\-]{2,}@[A-Za-z]{2,}$',
                          ).hasMatch(text)
                          ? null
                          : 'Enter a UPI ID like name@bank';
                    },
                  ),
                  _field('upiPayeeName', 'UPI payee name (defaults to store)'),
                  const Divider(height: 32),
                  _field(
                    'defaultGstRate',
                    'Default GST rate (%)',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) {
                      final rate = double.tryParse(value?.trim() ?? '');
                      if (rate == null) return 'Enter a number';
                      if (rate < 0 || rate > 100) return 'Must be 0-100';
                      return null;
                    },
                  ),
                  _field('receiptFooter', 'Receipt footer'),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save),
                    label: Text(_saving ? 'Saving...' : 'Save'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _field(
    String key,
    String label, {
    bool required = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _controllers[key],
        enabled: !_saving,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator:
            validator ??
            (required
                ? (value) => (value?.trim().isEmpty ?? true)
                      ? '$label is required'
                      : null
                : null),
      ),
    );
  }
}
