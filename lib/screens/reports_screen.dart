import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/order.dart';
import '../providers/printer_provider.dart';
import '../services/printer_service.dart';
import '../services/report_export.dart';
import '../services/sales_report.dart';
import '../services/settings_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  static final _dayFormat = DateFormat('MMM d, yyyy');
  static final _shortDayFormat = DateFormat('MMM d');
  static final _fileStamp = DateFormat('yyyyMMdd-HHmm');
  static final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  DateTimeRange? _selectedDateRange;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales & Analytics'),
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('orders').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Error loading orders data.'));
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('No orders found to generate analytics.'),
            );
          }

          final orders = docs
              .map(
                (doc) => CafeOrder.fromMap(
                  doc.data() as Map<String, dynamic>,
                  doc.id,
                ),
              )
              .toList();

          // The range picker must reach back to the first order ever taken,
          // however old the till is.
          final earliest = orders
              .map((order) => order.timestamp)
              .reduce((a, b) => a.isBefore(b) ? a : b);

          final range = _selectedDateRange;
          final inRange = range == null
              ? orders
              : orders.where((order) {
                  final start = DateTime(
                    range.start.year,
                    range.start.month,
                    range.start.day,
                  );
                  final end = DateTime(
                    range.end.year,
                    range.end.month,
                    range.end.day,
                  ).add(const Duration(days: 1));
                  return !order.timestamp.isBefore(start) &&
                      order.timestamp.isBefore(end);
                }).toList();

          final report = SalesReport.fromOrders(inRange);

          return Column(
            children: [
              _buildToolbar(context, report, earliest),
              const Divider(height: 1),
              Expanded(
                child: report.isEmpty
                    ? const Center(
                        child: Text('No completed sales in this period.'),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildSummaryCards(report),
                          const SizedBox(height: 24),
                          _sectionTitle('Sales by day'),
                          _buildDailyChart(report),
                          const SizedBox(height: 24),
                          _sectionTitle('Sales by hour'),
                          _buildHourlyChart(report),
                          const SizedBox(height: 24),
                          _sectionTitle('Payment methods'),
                          _buildPaymentBreakdown(report),
                          const SizedBox(height: 24),
                          _sectionTitle('GST summary'),
                          _buildGstReport(report),
                          const SizedBox(height: 24),
                          _sectionTitle('Top selling items'),
                          _buildTopItems(report),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  String get _rangeLabel {
    final range = _selectedDateRange;
    if (range == null) return 'All time';
    if (DateUtils.isSameDay(range.start, range.end)) {
      return _dayFormat.format(range.start);
    }
    return '${_shortDayFormat.format(range.start)} - ${_dayFormat.format(range.end)}';
  }

  Widget _buildToolbar(
    BuildContext context,
    SalesReport report,
    DateTime earliest,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range),
            label: Text(_rangeLabel),
            onPressed: () => _pickRange(earliest),
          ),
          if (_selectedDateRange != null)
            TextButton(
              onPressed: () => setState(() => _selectedDateRange = null),
              child: const Text('Clear'),
            ),
          TextButton.icon(
            icon: const Icon(Icons.today),
            label: const Text('Today'),
            onPressed: () {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              setState(() {
                _selectedDateRange = DateTimeRange(start: today, end: today);
              });
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.calendar_view_week),
            label: const Text('Last 7 days'),
            onPressed: () {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              setState(() {
                _selectedDateRange = DateTimeRange(
                  start: today.subtract(const Duration(days: 6)),
                  end: today,
                );
              });
            },
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Export CSV'),
            onPressed: report.isEmpty ? null : () => _exportCsv(report),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.print),
            label: const Text('Print summary'),
            onPressed: report.isEmpty ? null : () => _printSummary(report),
          ),
        ],
      ),
    );
  }

  Future<void> _pickRange(DateTime earliest) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(earliest.year, earliest.month, earliest.day),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _selectedDateRange,
    );
    if (range != null) {
      setState(() => _selectedDateRange = range);
    }
  }

  Future<void> _exportCsv(SalesReport report) async {
    final csv = report.toCsv();
    final fileName = 'icafe-sales-${_fileStamp.format(DateTime.now())}.csv';
    String? path;
    String? error;
    try {
      path = await saveCsvReport(fileName, csv);
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sales export'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                error != null
                    ? 'Could not write the file: $error\nCopy the CSV instead.'
                    : path != null
                    ? 'Saved to $path'
                    : 'This platform has no file storage, so copy the CSV instead.',
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(
                    csv,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: csv));
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Copy CSV'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _printSummary(SalesReport report) async {
    final printer = context.read<PrinterProvider>();
    if (!printer.isConnected) {
      _showMessage(
        'Connect a printer in Settings before printing the summary.',
        isError: true,
      );
      return;
    }
    try {
      final store = await SettingsService.load();
      final bytes = await PrinterService.generateSalesReportTicket(
        report,
        label: _rangeLabel,
        store: store,
      );
      final printed = await printer.printBytes(bytes);
      if (!mounted) return;
      _showMessage(
        printed
            ? 'Summary sent to the printer.'
            : 'The printer rejected the summary.',
        isError: !printed,
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not print the summary: $e', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      title,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
    ),
  );

  Widget _buildSummaryCards(SalesReport report) {
    final cards = <Widget>[
      _summaryCard(
        'Gross sales',
        _money.format(report.grossSales),
        Colors.green,
      ),
      _summaryCard('Net of GST', _money.format(report.netSales), Colors.teal),
      _summaryCard(
        'GST collected',
        _money.format(report.totalGst),
        Colors.indigo,
      ),
      _summaryCard('Orders', '${report.orderCount}', Colors.blueGrey),
      _summaryCard(
        'Average order',
        _money.format(report.averageOrderValue),
        Colors.deepPurple,
      ),
      if (report.cancelledCount > 0)
        _summaryCard(
          'Cancelled (${report.cancelledCount})',
          _money.format(report.cancelledValue),
          Colors.red,
        ),
    ];

    return Wrap(spacing: 12, runSpacing: 12, children: cards);
  }

  Widget _summaryCard(String label, String value, Color color) {
    return SizedBox(
      width: 200,
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDailyChart(SalesReport report) {
    final days = report.byDay;
    final spots = <FlSpot>[
      for (var i = 0; i < days.length; i++) FlSpot(i.toDouble(), days[i].total),
    ];

    return SizedBox(
      height: 260,
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 24, 24, 8),
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: true),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 52),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: (days.length / 6).ceilToDouble().clamp(1, 999),
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if (index < 0 || index >= days.length) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        _shortDayFormat.format(days[index].day),
                        style: const TextStyle(fontSize: 11),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: true),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: Colors.blue,
                  barWidth: 3,
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.blue.withValues(alpha: 0.25),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHourlyChart(SalesReport report) {
    final hours = report.byHour;
    return SizedBox(
      height: 240,
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 24, 24, 8),
          child: BarChart(
            BarChartData(
              gridData: const FlGridData(show: true),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 52),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: 2,
                    getTitlesWidget: (value, meta) => Text(
                      '${value.toInt()}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ),
              borderData: FlBorderData(show: true),
              barGroups: [
                for (var hour = 0; hour < hours.length; hour++)
                  BarChartGroupData(
                    x: hour,
                    barRods: [
                      BarChartRodData(
                        toY: hours[hour],
                        color: Colors.orange,
                        width: 10,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentBreakdown(SalesReport report) {
    return Card(
      elevation: 4,
      child: Column(
        children: [
          for (final payment in report.byPaymentMethod)
            ListTile(
              leading: Icon(_paymentIcon(payment.method)),
              title: Text(_paymentLabel(payment.method)),
              subtitle: Text('${payment.orderCount} orders'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _money.format(payment.total),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    report.grossSales == 0
                        ? '-'
                        : '${(payment.total / report.grossSales * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData _paymentIcon(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return Icons.payments;
      case PaymentMethod.upi:
        return Icons.qr_code;
      case PaymentMethod.card:
        return Icons.credit_card;
      case PaymentMethod.sodexo:
        return Icons.card_giftcard;
      case PaymentMethod.other:
        return Icons.more_horiz;
    }
  }

  String _paymentLabel(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.upi:
        return 'UPI';
      case PaymentMethod.card:
        return 'Card';
      case PaymentMethod.sodexo:
        return 'Sodexo';
      case PaymentMethod.other:
        return 'Other';
    }
  }

  Widget _buildGstReport(SalesReport report) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DataTable(
              columnSpacing: 24,
              columns: const [
                DataColumn(label: Text('Rate')),
                DataColumn(label: Text('Taxable value'), numeric: true),
                DataColumn(label: Text('CGST'), numeric: true),
                DataColumn(label: Text('SGST'), numeric: true),
                DataColumn(label: Text('Total GST'), numeric: true),
              ],
              rows: [
                for (final gst in report.byGstRate)
                  DataRow(
                    cells: [
                      DataCell(Text('${gst.rate.toStringAsFixed(0)}%')),
                      DataCell(Text(_money.format(gst.taxableValue))),
                      DataCell(Text(_money.format(gst.halfGst))),
                      DataCell(Text(_money.format(gst.halfGst))),
                      DataCell(Text(_money.format(gst.gstAmount))),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Total GST payable: ${_money.format(report.totalGst)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopItems(SalesReport report) {
    final items = report.topItems.take(10).toList();
    return Card(
      elevation: 4,
      child: Column(
        children: [
          for (final item in items)
            ListTile(
              leading: const Icon(Icons.star, color: Colors.amber),
              title: Text(item.name),
              subtitle: Text('${item.quantity} sold'),
              trailing: Text(
                _money.format(item.total),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
