import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import 'datdbase.dart';

class ExpirationScreen extends StatefulWidget {
  const ExpirationScreen({super.key});

  @override
  State<ExpirationScreen> createState() => _ExpirationScreenState();
}

class _ExpirationScreenState extends State<ExpirationScreen> {
  List<Map<String, dynamic>> _allProducts = [];
  bool _isLoading = true;
  String _filter = 'all';

  int _expiredCount = 0;
  int _nearCount = 0;
  int _safeCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  // -----------------------
  // تحويل التاريخ بأمان
  // -----------------------
  DateTime _safeParseDate(dynamic value) {
    if (value == null) return DateTime(1970);
    final s = value.toString().trim();
    if (s.isEmpty) return DateTime(1970);

    try {
      return DateTime.parse(s);
    } catch (_) {}

    List<String> formats = ['yyyy-MM-dd', 'dd/MM/yyyy', 'dd-MM-yyyy', 'yyyy/MM/dd'];
    for (var f in formats) {
      try {
        return DateFormat(f).parseStrict(s);
      } catch (_) {}
    }

    print('⚠️ Could not parse date: $s');
    return DateTime(1970);
  }

  // -----------------------
  // تحميل البيانات من قاعدة البيانات
  // -----------------------
  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);

    final data = await DatabaseHelper.instance.queryStockForExpiration();

    final today = DateTime.now();
    int expired = 0, near = 0, safe = 0;

    final productsWithDates = data.map((p) {
      final product = Map<String, dynamic>.from(p);
      final expiryDate = _safeParseDate(p['expiry_date']);

      product['parsed_expiry_date'] = expiryDate;

      if (expiryDate.isBefore(today)) expired++;
      else if (expiryDate.isBefore(today.add(const Duration(days: 30)))) near++;
      else safe++;

      return product;
    }).toList();

    // ترتيب حسب تاريخ الانتهاء
    productsWithDates.sort((a, b) =>
        (a['parsed_expiry_date'] as DateTime).compareTo(b['parsed_expiry_date'] as DateTime));

    if (mounted) {
      setState(() {
        _allProducts = productsWithDates;
        _expiredCount = expired;
        _nearCount = near;
        _safeCount = safe;
        _isLoading = false;
      });
    }
  }

  // -----------------------
  // تصفية المنتجات حسب الحالة
  // -----------------------
  List<Map<String, dynamic>> _getFilteredProducts() {
    final today = DateTime.now();
    return _allProducts.where((p) {
      final date = p['parsed_expiry_date'] as DateTime;
      final isExpired = date.isBefore(today);
      final isNear = !isExpired && date.isBefore(today.add(const Duration(days: 30)));
      final isSafe = !isExpired && !isNear;

      if (_filter == 'expired') return isExpired;
      if (_filter == 'near_expiration') return isNear;
      if (_filter == 'safe') return isSafe;
      return true;
    }).toList();
  }

  // -----------------------
  // لون الحالة
  // -----------------------
  Color _getStatusColor(DateTime date) {
    final today = DateTime.now();
    if (date.isBefore(today)) return Colors.red;
    if (date.isBefore(today.add(const Duration(days: 30)))) return Colors.orange;
    return Colors.green;
  }

  // -----------------------
  // واجهة الصفحة
  // -----------------------
  @override
  Widget build(BuildContext context) {
    final filteredProducts = _getFilteredProducts();

    return Scaffold(
      appBar: AppBar(
        title: Text('expiration_alerts'.tr()),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('all', '${'all'.tr()} (${_allProducts.length})'),
                  const SizedBox(width: 8),
                  _filterChip('expired', '${'expired'.tr()} ($_expiredCount)'),
                  const SizedBox(width: 8),
                  _filterChip('near_expiration', '${'near_expiration'.tr()} ($_nearCount)'),
                  const SizedBox(width: 8),
                  _filterChip('safe', '${'safe'.tr()} ($_safeCount)'),
                ],
              ),
            ),
          ),
          Expanded(
            child: filteredProducts.isEmpty
                ? Center(child: Text('no_products_in_this_category'.tr()))
                : ListView.builder(
              itemCount: filteredProducts.length,
              itemBuilder: (context, index) {
                final product = filteredProducts[index];
                final date = product['parsed_expiry_date'] as DateTime;
                final color = _getStatusColor(date);

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color,
                      child: const Icon(Icons.medication, color: Colors.white),
                    ),
                    title: Text(product['product_name'],
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      '${'batch'.tr()}: ${product['batch_number'] ?? '-'}\n'
                          '${'expiration_date'.tr()}: ${DateFormat('yyyy-MM-dd').format(date)}\n'
                          '${'quantity'.tr()}: ${product['quantity']}',
                    ),
                    trailing: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------
  // زر التصفية
  // -----------------------
  Widget _filterChip(String filter, String label) {
    final isSelected = _filter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _filter = filter);
      },
    );
  }
}
