import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pharmacy/currency_service.dart';
import 'datdbase.dart';

class MonthlyReportsScreen extends StatefulWidget {
  const MonthlyReportsScreen({super.key});

  @override
  State<MonthlyReportsScreen> createState() => _MonthlyReportsScreenState();
}

class _MonthlyReportsScreenState extends State<MonthlyReportsScreen> {
  // Define a single date to control which month is shown.
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('monthly_reports'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // This screen now correctly focuses only on the monthly report.
          _buildMonthlyProfitStats(),
          const SizedBox(height: 24),
          Text('sales_chart'.tr(), style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                barGroups: List.generate(12, (index) {
                  // Placeholder data, this can be hooked to real monthly data later.
                  return BarChartGroupData(
                    x: index,
                    barRods: [BarChartRodData(toY: (index % 4 + 1) * 5, width: 15)],
                  );
                }),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (double value, TitleMeta meta) {
                        final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                        if (value.toInt() >= 0 && value.toInt() < months.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(months[value.toInt()]),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyProfitStats() {
    return FutureBuilder<Map<String, double>>(
      // Correctly call getMonthlyProfitStats with year and month.
      future: DatabaseHelper.instance.getMonthlyProfitStats(_selectedDate.year, _selectedDate.month),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('${'error'.tr()}: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data == null) {
          return Center(child: Text('no_data_available'.tr()));
        }

        final data = snapshot.data!;
        // Use null-safe access with the ?? operator to prevent crashes.
        final sales = data['sales'] ?? 0.0;
        final cost = data['cost'] ?? 0.0;
        final profit = data['profit'] ?? 0.0;
        // DEFINITIVE FIX: Use the correct key 'profit_percent'
        final percentage = data['profit_percent'] ?? 0.0;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('monthly_report'.tr(), style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                _buildStatRow('total_sales'.tr(), sales, Colors.blue),
                const SizedBox(height: 8),
                _buildStatRow('total_cost'.tr(), cost, Colors.orange),
                const SizedBox(height: 8),
                _buildStatRow('net_profit'.tr(), profit, Colors.green, isBold: true),
                const SizedBox(height: 8),
                _buildStatRow('${'profit_percentage'.tr()} ', percentage, Colors.purple, isBold: true, isPercentage: true),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Helper widget for displaying a single statistic row.
Widget _buildStatRow(String label, double value, Color color, {bool isBold = false, bool isPercentage = false}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
            fontSize: 18,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color),
      ),
      Text(
        isPercentage ? '${value.toStringAsFixed(2)}%' : formatPrice(value),
        style: TextStyle(
            fontSize: 22,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color),
      ),
    ],
  );
}
