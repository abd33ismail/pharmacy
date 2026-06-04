import 'dart:async';
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
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _monthlyCurrencyReports = [];
  List<double> _yearlyChartData = List.filled(12, 0.0);
  bool _isLoading = true;
  StreamSubscription? _dbSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();
    // ✅ الاستماع للتغييرات في قاعدة البيانات لتحديث التقرير فورياً عند الحذف أو البيع
    _dbSubscription = DatabaseHelper.instance.onDatabaseChanged.listen((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _dbSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // جلب تقارير العملات للشهر المحدد
      final reports = await DatabaseHelper.instance.getMonthlyReportsByCurrency(
        _selectedDate.year,
        _selectedDate.month,
      );

      // جلب بيانات الرسم البياني للسنة كاملة
      final chartData = await DatabaseHelper.instance.getYearlySalesData(_selectedDate.year);

      if (mounted) {
        setState(() {
          _monthlyCurrencyReports = reports;
          _yearlyChartData = chartData;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Monthly Report Load Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectMonth(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      // تخصيص لاختيار الشهر فقط (متاح في بعض إصدارات فلاتر أو عبر حزمة خارجية، 
      // هنا سنستخدم المدمج للاختيار العادي ونأخذ الشهر منه)
    );
    if (picked != null) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month);
      });
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.locale.languageCode;
    final monthName = DateFormat.yMMMM(locale).format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: Text('monthly_reports'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () => _selectMonth(context),
            tooltip: 'select_month'.tr(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  Text(
                    '${'report_for'.tr()} $monthName',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  
                  // كروت التقارير حسب العملة
                  if (_monthlyCurrencyReports.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Text('no_data_available'.tr()),
                      ),
                    )
                  else
                    ..._monthlyCurrencyReports.map((report) => _buildCurrencyCard(report)).toList(),

                  const SizedBox(height: 30),
                  Text(
                    '${'sales_chart_for_year'.tr()} ${_selectedDate.year}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  
                  // ✅ الرسم البياني الحقيقي
                  _buildRealBarChart(),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildCurrencyCard(Map<String, dynamic> report) {
    final currencyStr = report['currency'] ?? 'syp';
    final symbol = currencyLabel(currencyStr == 'usd' ? Currency.usd : Currency.syp);
    
    final sales = (report['sales'] as num?)?.toDouble() ?? 0.0;
    final cost = (report['cost'] as num?)?.toDouble() ?? 0.0;
    final profit = (report['profit'] as num?)?.toDouble() ?? 0.0;
    final percentage = sales > 0 ? (profit / sales) * 100 : 0.0;

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  currencyStr.toUpperCase(),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
                const Icon(Icons.account_balance_wallet, color: Colors.blue),
              ],
            ),
            const Divider(),
            _buildStatRow('total_sales'.tr(), sales, symbol, Colors.blue),
            const SizedBox(height: 8),
            _buildStatRow('total_cost'.tr(), cost, symbol, Colors.orange),
            const SizedBox(height: 8),
            _buildStatRow('net_profit'.tr(), profit, symbol, Colors.green, isBold: true),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('profit_percentage'.tr(), style: const TextStyle(fontSize: 14, color: Colors.grey)),
                Text(
                  '${percentage.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 16, 
                    fontWeight: FontWeight.bold, 
                    color: percentage >= 0 ? Colors.green : Colors.red
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, double value, String symbol, Color color, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 16, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        Text(
          '$symbol${formatPrice(value)}',
          style: TextStyle(fontSize: 18, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color),
        ),
      ],
    );
  }

  Widget _buildRealBarChart() {
    double maxVal = 0;
    for (var v in _yearlyChartData) { if (v > maxVal) maxVal = v; }
    if (maxVal == 0) maxVal = 1000;

    return Container(
      height: 250,
      padding: const EdgeInsets.only(top: 20, right: 10, left: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxVal * 1.2,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${DateFormat.MMM().format(DateTime(_selectedDate.year, group.x.toInt() + 1))}\n',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  children: [
                    TextSpan(
                      text: formatPrice(rod.toY),
                      style: const TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold),
                    ),
                  ],
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  const months = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12'];
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(months[value.toInt()], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(12, (i) => BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: _yearlyChartData[i],
                color: i == _selectedDate.month - 1 ? Colors.blue : Colors.blue.withValues(alpha: 0.3),
                width: 16,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          )),
        ),
      ),
    );
  }
}
