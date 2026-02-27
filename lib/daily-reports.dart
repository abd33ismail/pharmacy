import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pharmacy/currency_service.dart';
import 'datdbase.dart';

class DailyReportsScreen extends StatefulWidget {
  const DailyReportsScreen({super.key});

  @override
  State<DailyReportsScreen> createState() => _DailyReportsScreenState();
}

class _DailyReportsScreenState extends State<DailyReportsScreen> {
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _groupedSales = [];
  List<Map<String, dynamic>> _currencyReports = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReportData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadReportData();
  }

  Future<void> _loadReportData() async {
    setState(() => _isLoading = true);
    final reports = await DatabaseHelper.instance.getDailyReportsByCurrency(_selectedDate);
    final db = await DatabaseHelper.instance.database;
    String dateStr = DateFormat('yyyy-MM-dd', 'en_US').format(_selectedDate);

    final salesResults = await db.rawQuery('''
      SELECT 
        p.name as productName, 
        p.sale_currency,
        SUM(si.quantity) as totalQuantity,
        SUM(si.price * si.quantity) as totalPrice
      FROM Sale_Items si
      JOIN Sales s ON si.sale_id = s.sale_id
      JOIN Products p ON si.product_id = p.product_id
      WHERE DATE(s.sale_date) = ?
      GROUP BY p.name, p.sale_currency
      ORDER BY p.name
    ''', [dateStr]);

    if (mounted) {
      setState(() {
        _currencyReports = reports;
        _groupedSales = salesResults;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteRecordsForSelectedDate() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('delete_records_for_date'.tr()),
        // DEFINITIVE FIX: Use namedArgs for easy_localization
        content: Text('confirm_delete_for_date'.tr(namedArgs: {'date': DateFormat.yMMMd().format(_selectedDate)})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('cancel'.tr())),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('delete'.tr()),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = await DatabaseHelper.instance.database;
      String dateStr = DateFormat('yyyy-MM-dd', 'en_US').format(_selectedDate);
      final salesToDelete = await db.query('Sales', where: 'DATE(sale_date) = ?', whereArgs: [dateStr], columns: ['sale_id']);
      final ids = salesToDelete.map((row) => row['sale_id']).toList();

      if (ids.isNotEmpty) {
        await db.transaction((txn) async {
          await txn.delete('Sale_Items', where: 'sale_id IN (${ids.map((_) => '?').join(',')})', whereArgs: ids);
          await txn.delete('Sales', where: 'sale_id IN (${ids.map((_) => '?').join(',')})', whereArgs: ids);
        });
      }
      _loadReportData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('records_deleted_successfully'.tr())));
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadReportData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.locale.languageCode;
    final localizedDate = DateFormat.yMMMMd(locale).format(_selectedDate);

    return Scaffold(
      appBar: AppBar(title: Text('daily_report'.tr()), centerTitle: true, actions: [
        IconButton(icon: const Icon(Icons.delete_sweep), onPressed: _groupedSales.isEmpty ? null : _deleteRecordsForSelectedDate, tooltip: 'delete_records_for_date'.tr()),
      ]),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('${'date'.tr()}: $localizedDate', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ElevatedButton.icon(onPressed: () => _selectDate(context), icon: const Icon(Icons.calendar_today), label: Text('select_date'.tr())),
                  ]),
                ),
                Expanded(
                  child: _groupedSales.isEmpty
                      ? Center(child: Text('no_sales_for_date'.tr()))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          itemCount: _groupedSales.length,
                          itemBuilder: (context, index) {
                            final sale = _groupedSales[index];
                            final price = (sale['totalPrice'] as num?)?.toDouble() ?? 0.0;
                            final currency = sale['sale_currency'] as String?;
                            final symbol = currencyLabel(currency == 'usd' ? Currency.usd : Currency.syp);

                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(child: Text((index + 1).toString())),
                                title: Text(sale['productName'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('${'total_quantity'.tr()}: ${sale['totalQuantity']}'),
                                trailing: Text(
                                  '$symbol${formatPrice(price)}',
                                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                if (_currencyReports.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _currencyReports.map((report) {
                        final currencyStr = report['currency'] as String;
                        final symbol = currencyLabel(currencyStr == 'usd' ? Currency.usd : Currency.syp);
                        return Expanded(
                          child: Card(
                            margin: const EdgeInsets.symmetric(horizontal: 4.0),
                            color: Colors.lightBlue[50],
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${'report_for'.tr()} ${currencyStr.toUpperCase()}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                const Divider(height: 15),
                                _buildStatRow('total_sales'.tr(), (report['sales'] as num).toDouble(), symbol, Colors.blue),
                                const SizedBox(height: 8),
                                _buildStatRow('total_cost'.tr(), (report['cost'] as num).toDouble(), symbol, Colors.orange),
                                const SizedBox(height: 8),
                                _buildStatRow('net_profit'.tr(), (report['profit'] as num).toDouble(), symbol, Colors.green, isBold: true),
                              ]),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
    );
  }

  Widget _buildStatRow(String label, double value, String currencySymbol, Color color, {bool isBold = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color),
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$currencySymbol${formatPrice(value)}',
          style: TextStyle(fontSize: 16, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color),
        ),
      ],
    );
  }
}
