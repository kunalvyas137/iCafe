import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/order.dart';
import '../models/store_settings.dart';
import '../providers/printer_provider.dart';
import '../services/order_service.dart';
import '../services/printer_service.dart';
import '../services/settings_service.dart';

enum _StatusFilter { all, completed, cancelled }

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, this.canCancel = false});

  /// Voiding an order rewrites stock, so it is limited to admins.
  final bool canCancel;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _searchController = TextEditingController();
  DateTime _day = DateTime.now();
  _StatusFilter _statusFilter = _StatusFilter.all;
  String _query = '';
  String? _selectedOrderId;
  StoreSettings? _store;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<StoreSettings> _storeSettings() async {
    final cached = _store;
    if (cached != null) return cached;
    try {
      final loaded = await SettingsService.load();
      _store = loaded;
      return loaded;
    } catch (_) {
      return StoreSettings.defaults;
    }
  }

  bool _matchesQuery(CafeOrder order) {
    if (_query.isEmpty) return true;
    final needle = _query.toLowerCase();
    return order.displayNumber.toLowerCase().contains(needle) ||
        order.id.toLowerCase().contains(needle) ||
        (order.customerName ?? '').toLowerCase().contains(needle) ||
        (order.tableLabel ?? '').toLowerCase().contains(needle) ||
        order.items.any(
          (item) => item.productName.toLowerCase().contains(needle),
        );
  }

  bool _matchesStatus(CafeOrder order) {
    switch (_statusFilter) {
      case _StatusFilter.all:
        return true;
      case _StatusFilter.completed:
        return !order.isCancelled;
      case _StatusFilter.cancelled:
        return order.isCancelled;
    }
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _day = picked;
        _selectedOrderId = null;
      });
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

  Future<void> _reprint(CafeOrder order) async {
    final printer = context.read<PrinterProvider>();
    if (!printer.isConnected) {
      _showMessage('Connect a printer in Settings first.', isError: true);
      return;
    }
    final store = await _storeSettings();
    final bytes = await PrinterService.generateBillTicket(
      order,
      store: store,
      reprint: true,
    );
    final printed = await printer.printBytes(bytes);
    _showMessage(
      printed
          ? 'Reprinted ${order.displayNumber}'
          : 'The receipt did not print.',
      isError: !printed,
    );
  }

  Future<void> _cancel(CafeOrder order) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _CancelDialog(order: order),
    );
    if (reason == null) return;
    try {
      await OrderService.cancelOrder(order, reason: reason);
      _showMessage('${order.displayNumber} cancelled, stock returned.');
    } on CheckoutException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (e) {
      _showMessage('Could not cancel the order: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickDay,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(DateFormat('EEE, d MMM y').format(_day)),
                ),
                const SizedBox(width: 12),
                SegmentedButton<_StatusFilter>(
                  segments: const [
                    ButtonSegment(value: _StatusFilter.all, label: Text('All')),
                    ButtonSegment(
                      value: _StatusFilter.completed,
                      label: Text('Completed'),
                    ),
                    ButtonSegment(
                      value: _StatusFilter.cancelled,
                      label: Text('Cancelled'),
                    ),
                  ],
                  selected: {_statusFilter},
                  onSelectionChanged: (selection) =>
                      setState(() => _statusFilter = selection.first),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Order number, customer, table or item',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _query = value.trim()),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<CafeOrder>>(
              stream: OrderService.watchDay(_day),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Could not load orders: ${snapshot.error}'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final orders = snapshot.data!
                    .where(_matchesStatus)
                    .where(_matchesQuery)
                    .toList();
                if (orders.isEmpty) {
                  return const Center(
                    child: Text('No orders match this filter.'),
                  );
                }

                final selected = orders.firstWhere(
                  (order) => order.id == _selectedOrderId,
                  orElse: () => orders.first,
                );

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _OrderList(
                        orders: orders,
                        selectedId: selected.id,
                        onSelect: (order) =>
                            setState(() => _selectedOrderId = order.id),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      flex: 3,
                      child: _OrderDetail(
                        order: selected,
                        canCancel: widget.canCancel,
                        onReprint: () => _reprint(selected),
                        onCancel: () => _cancel(selected),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({
    required this.orders,
    required this.selectedId,
    required this.onSelect,
  });

  final List<CafeOrder> orders;
  final String selectedId;
  final ValueChanged<CafeOrder> onSelect;

  @override
  Widget build(BuildContext context) {
    final total = orders
        .where((order) => order.countsTowardsSales)
        .fold<double>(0, (sum, order) => sum + order.grandTotal);

    return Column(
      children: [
        ListTile(
          dense: true,
          title: Text('${orders.length} orders'),
          trailing: Text(
            '₹${total.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return ListTile(
                selected: order.id == selectedId,
                selectedTileColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.08),
                leading: CircleAvatar(
                  backgroundColor: order.isCancelled
                      ? Colors.red.shade100
                      : Colors.green.shade100,
                  child: Icon(
                    order.isCancelled ? Icons.block : Icons.check,
                    size: 18,
                    color: order.isCancelled
                        ? Colors.red.shade700
                        : Colors.green.shade700,
                  ),
                ),
                title: Text(
                  order.displayNumber,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    decoration: order.isCancelled
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                subtitle: Text(
                  '${DateFormat('HH:mm').format(order.timestamp)} · '
                  '${order.items.length} items · ${order.paymentMethod.name}',
                ),
                trailing: Text('₹${order.grandTotal.toStringAsFixed(2)}'),
                onTap: () => onSelect(order),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OrderDetail extends StatelessWidget {
  const _OrderDetail({
    required this.order,
    required this.canCancel,
    required this.onReprint,
    required this.onCancel,
  });

  final CafeOrder order;
  final bool canCancel;
  final VoidCallback onReprint;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final change = order.changeDue;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                order.displayNumber,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              if (order.isCancelled)
                const Chip(
                  label: Text('Cancelled'),
                  backgroundColor: Color(0xFFFFCDD2),
                ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: onReprint,
                icon: const Icon(Icons.print),
                label: const Text('Reprint'),
              ),
              if (canCancel && !order.isCancelled) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                  ),
                  onPressed: onCancel,
                  icon: const Icon(Icons.block),
                  label: const Text('Cancel order'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('EEE, d MMM y · HH:mm').format(order.timestamp),
            style: const TextStyle(color: Colors.grey),
          ),
          if (order.tableLabel != null || order.customerName != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [
                  if (order.tableLabel != null) 'Table ${order.tableLabel}',
                  if (order.customerName != null) order.customerName!,
                ].join(' · '),
              ),
            ),
          if (order.cancelReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Cancelled: ${order.cancelReason}',
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
          const SizedBox(height: 16),
          const Divider(),
          ...order.items.map(
            (item) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(item.productName),
              subtitle: Text(
                '${item.quantity} × ₹${item.price.toStringAsFixed(2)} '
                '· GST ${item.gstRate.toStringAsFixed(0)}%',
              ),
              trailing: Text('₹${item.totalWithGst.toStringAsFixed(2)}'),
            ),
          ),
          const Divider(),
          _AmountRow(label: 'Subtotal', amount: order.subtotal),
          ...order.gstByRate.entries.map(
            (entry) => _AmountRow(
              label: 'GST ${entry.key.toStringAsFixed(0)}%',
              amount: entry.value,
            ),
          ),
          _AmountRow(label: 'Total', amount: order.grandTotal, bold: true),
          if (order.cashTendered != null)
            _AmountRow(label: 'Cash tendered', amount: order.cashTendered!),
          if (change != null) _AmountRow(label: 'Change', amount: change),
          const SizedBox(height: 8),
          Text('Paid by ${order.paymentMethod.name}'),
          if (order.notes != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Note: ${order.notes}'),
            ),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.amount,
    this.bold = false,
  });

  final String label;
  final double amount;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: bold ? 18 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('₹${amount.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }
}

class _CancelDialog extends StatefulWidget {
  const _CancelDialog({required this.order});

  final CafeOrder order;

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _controller.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Give a reason so the void can be audited.');
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Cancel ${widget.order.displayNumber}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('The stock this order consumed goes back to inventory.'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Reason',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Keep order'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Cancel order')),
      ],
    );
  }
}
