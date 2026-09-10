import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTimeRange? _selectedDateRange;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales & Analytics'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.date_range),
            label: Text(
              _selectedDateRange == null
                  ? 'Select Date Range'
                  : '${DateFormat('MMM d').format(_selectedDateRange!.start)} - ${DateFormat('MMM d').format(_selectedDateRange!.end)}',
            ),
            onPressed: () async {
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2023),
                lastDate: DateTime.now(),
              );
              if (range != null) {
                setState(() {
                  _selectedDateRange = range;
                });
              }
            },
          ),
          const SizedBox(width: 16),
        ],
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
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No orders found to generate analytics.'));
          }

          final allOrders = snapshot.data!.docs;
          
          // Filter by date range if selected
          final filteredOrders = _selectedDateRange == null 
              ? allOrders 
              : allOrders.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final date = DateTime.parse(data['timestamp']);
                  // Adjust end date to include the entire day
                  final end = _selectedDateRange!.end.add(const Duration(days: 1));
                  return date.isAfter(_selectedDateRange!.start) && date.isBefore(end);
                }).toList();

          if (filteredOrders.isEmpty) {
            return const Center(child: Text('No orders found for the selected date range.'));
          }

          // Aggregate Data
          Map<int, double> dailyRevenue = {};
          Map<String, int> itemSalesCount = {};
          double totalRevenue = 0;

          for (var doc in filteredOrders) {
            final data = doc.data() as Map<String, dynamic>;
            final date = DateTime.parse(data['timestamp']);
            final amount = (data['grandTotal'] ?? 0.0).toDouble();
            totalRevenue += amount;

            // Group by weekday (1=Monday, 7=Sunday)
            dailyRevenue[date.weekday] = (dailyRevenue[date.weekday] ?? 0.0) + amount;

            // Group Items
            final itemsList = data['items'] as List<dynamic>? ?? [];
            for (var item in itemsList) {
              final name = item['productName'] as String;
              final qty = (item['quantity'] as num).toInt();
              itemSalesCount[name] = (itemSalesCount[name] ?? 0) + qty;
            }
          }

          // Build Chart Spots
          List<FlSpot> spots = [];
          for (int i = 1; i <= 7; i++) {
            spots.add(FlSpot(i.toDouble() - 1, dailyRevenue[i] ?? 0.0));
          }

          // Sort Top Items
          final sortedItems = itemSalesCount.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Revenue: ₹${totalRevenue.toStringAsFixed(2)}', 
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green)
                ),
                const SizedBox(height: 24),
                const Text('Sales Trend (by Day of Week)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 300,
                  child: Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: true),
                          titlesData: FlTitlesData(
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                                  if (value.toInt() >= 0 && value.toInt() < 7) {
                                    return Text(days[value.toInt()]);
                                  }
                                  return const Text('');
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
                              barWidth: 4,
                              belowBarData: BarAreaData(show: true, color: Colors.blue.withOpacity(0.3)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const Text('Top Selling Items', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Card(
                  elevation: 4,
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: sortedItems.length > 5 ? 5 : sortedItems.length,
                    itemBuilder: (context, index) {
                      final item = sortedItems[index];
                      return ListTile(
                        leading: const Icon(Icons.star, color: Colors.amber),
                        title: Text(item.key),
                        trailing: Text('${item.value} sold', style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
