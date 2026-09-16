import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/order.dart';
import '../services/order_service.dart';

enum ActiveFilter { all, pending, preparing }

/// Live view of the takeaway order queue.
///
/// In standard mode ([isCompact] = false), displays a two-column kitchen view.
/// In compact mode ([isCompact] = true), displays a single-column panel suitable
/// for embedding alongside the POS checkout pane.
class ActiveOrdersScreen extends StatefulWidget {
  const ActiveOrdersScreen({super.key, this.isCompact = false});

  final bool isCompact;

  @override
  State<ActiveOrdersScreen> createState() => _ActiveOrdersScreenState();
}

class _ActiveOrdersScreenState extends State<ActiveOrdersScreen> {
  ActiveFilter _compactFilter = ActiveFilter.all;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CafeOrder>>(
      stream: OrderService.watchActiveOrders(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(
                    'Could not load active orders:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final allActive = snapshot.data ?? [];
        final pending = allActive.where((o) => o.isPending).toList();
        final preparing = allActive.where((o) => o.isPreparing).toList();

        if (widget.isCompact) {
          final filteredOrders = switch (_compactFilter) {
            ActiveFilter.all => allActive,
            ActiveFilter.pending => pending,
            ActiveFilter.preparing => preparing,
          };

          return Container(
            color: Colors.grey[50],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppBar(
                  title: Row(
                    children: [
                      const Icon(Icons.kitchen, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Active Orders',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      if (allActive.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${allActive.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  automaticallyImplyLeading: false,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: SegmentedButton<ActiveFilter>(
                    segments: [
                      ButtonSegment(
                        value: ActiveFilter.all,
                        label: Text('All (${allActive.length})'),
                      ),
                      ButtonSegment(
                        value: ActiveFilter.pending,
                        label: Text('New (${pending.length})'),
                      ),
                      ButtonSegment(
                        value: ActiveFilter.preparing,
                        label: Text('Kitchen (${preparing.length})'),
                      ),
                    ],
                    selected: {_compactFilter},
                    onSelectionChanged: (newSelection) {
                      setState(() => _compactFilter = newSelection.first);
                    },
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: !snapshot.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : filteredOrders.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      size: 44,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.25),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _compactFilter == ActiveFilter.pending
                                          ? 'No pending orders'
                                          : _compactFilter == ActiveFilter.preparing
                                              ? 'Nothing in the kitchen'
                                              : 'No active orders in queue',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.5),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              itemCount: filteredOrders.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final order = filteredOrders[index];
                                return _OrderCard(
                                  order: order,
                                  accentColor: order.isPending
                                      ? const Color(0xFFF59E0B)
                                      : const Color(0xFF10B981),
                                  actionLabel:
                                      order.isPending ? 'Alert Chef' : 'Mark Delivered',
                                  actionIcon: order.isPending
                                      ? Icons.notifications_active_outlined
                                      : Icons.check_circle_outline,
                                  onAction: () async {
                                    try {
                                      if (order.isPending) {
                                        await OrderService.alertChef(order);
                                      } else {
                                        await OrderService.closeOrder(order);
                                      }
                                    } on CheckoutException catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(e.message),
                                            backgroundColor: Colors.red.shade700,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                );
                              },
                            ),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pending column
              Expanded(
                child: _QueueColumn(
                  title: 'New Orders',
                  subtitle: 'Tap "Alert Chef" to send to kitchen',
                  icon: Icons.receipt_long,
                  accentColor: const Color(0xFFF59E0B),
                  orders: pending,
                  isLoading: !snapshot.hasData,
                  emptyMessage: 'No pending orders',
                  actionLabel: 'Alert Chef',
                  actionIcon: Icons.notifications_active_outlined,
                  onAction: (order) async {
                    try {
                      await OrderService.alertChef(order);
                    } on CheckoutException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(e.message),
                            backgroundColor: Colors.red.shade700,
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              // Preparing column
              Expanded(
                child: _QueueColumn(
                  title: 'In Kitchen',
                  subtitle: 'Tap "Mark Delivered" once handed to customer',
                  icon: Icons.restaurant,
                  accentColor: const Color(0xFF10B981),
                  orders: preparing,
                  isLoading: !snapshot.hasData,
                  emptyMessage: 'Nothing in the kitchen',
                  actionLabel: 'Mark Delivered',
                  actionIcon: Icons.check_circle_outline,
                  onAction: (order) async {
                    try {
                      await OrderService.closeOrder(order);
                    } on CheckoutException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(e.message),
                            backgroundColor: Colors.red.shade700,
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QueueColumn extends StatelessWidget {
  const _QueueColumn({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.orders,
    required this.isLoading,
    required this.emptyMessage,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final List<CafeOrder> orders;
  final bool isLoading;
  final String emptyMessage;
  final String actionLabel;
  final IconData actionIcon;
  final Future<void> Function(CafeOrder) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Column header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accentColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, color: accentColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (orders.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: accentColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${orders.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Order cards
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : orders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 48,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.25),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            emptyMessage,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: orders.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        return _OrderCard(
                          order: order,
                          accentColor: accentColor,
                          actionLabel: actionLabel,
                          actionIcon: actionIcon,
                          onAction: () => onAction(order),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

/// A card representing a single in-flight order.
class _OrderCard extends StatefulWidget {
  const _OrderCard({
    required this.order,
    required this.accentColor,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
  });

  final CafeOrder order;
  final Color accentColor;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _loading = false;
  late Timer _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateElapsed();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _updateElapsed();
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  void _updateElapsed() {
    setState(() => _elapsed = DateTime.now().difference(widget.order.timestamp));
  }

  String get _elapsedLabel {
    final mins = _elapsed.inMinutes;
    if (mins < 1) return 'just now';
    if (mins == 1) return '1 min ago';
    if (mins < 60) return '$mins mins ago';
    final hrs = _elapsed.inHours;
    return '$hrs hr${hrs > 1 ? "s" : ""} ago';
  }

  Color get _elapsedColor {
    final mins = _elapsed.inMinutes;
    if (mins < 10) return Colors.green.shade600;
    if (mins < 20) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  Future<void> _handleAction() async {
    setState(() => _loading = true);
    try {
      widget.onAction();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = widget.order;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.accentColor.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.accentColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    order.displayNumber,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (order.customerName != null) ...[
                  Icon(Icons.person_outline,
                      size: 16,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      order.customerName!,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
                if (order.tableLabel != null) ...[
                  const SizedBox(width: 6),
                  Chip(
                    label: Text('Table ${order.tableLabel}'),
                    labelStyle: const TextStyle(fontSize: 11),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: theme.colorScheme.secondaryContainer,
                  ),
                ],
                const Spacer(),
                Text(
                  DateFormat('HH:mm').format(order.timestamp),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Items list
            ...order.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: widget.accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${item.quantity}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: widget.accentColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (item.modifiers.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Wrap(
                                  spacing: 4,
                                  runSpacing: 2,
                                  children: item.modifiers.map((mod) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: widget.accentColor
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        mod,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: widget.accentColor,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            if (item.notes != null &&
                                item.notes!.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.notes,
                                      size: 11,
                                      color: Colors.amber.shade900,
                                    ),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        item.notes!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.amber.shade900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),

            if (order.notes != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notes,
                        size: 14,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        order.notes!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Footer: elapsed time + action button
            Row(
              children: [
                Icon(Icons.schedule, size: 14, color: _elapsedColor),
                const SizedBox(width: 4),
                Text(
                  _elapsedLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _elapsedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : FilledButton.icon(
                        onPressed: _handleAction,
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.accentColor,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                        icon: Icon(widget.actionIcon, size: 16),
                        label: Text(widget.actionLabel),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
