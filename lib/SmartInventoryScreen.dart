import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'datdbase.dart';

class SmartInventoryScreen extends StatefulWidget {
  const SmartInventoryScreen({super.key});

  @override
  State<SmartInventoryScreen> createState() => _SmartInventoryScreenState();
}

class _SmartInventoryScreenState extends State<SmartInventoryScreen> {
  bool _isLoading = false;
  File? _image;
  final ImagePicker _picker = ImagePicker();
  final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final barcodeScanner = BarcodeScanner();

  List<Map<String, dynamic>> _suggestedProducts = [];

  /// --- التقاط صورة للمنتج
  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.camera);
    if (pickedFile == null) return;

    setState(() {
      _image = File(pickedFile.path);
      _isLoading = true;
      _suggestedProducts.clear();
    });

    await _processImage(_image!);
  }

  /// --- معالجة الصورة: نصوص + باركود
  Future<void> _processImage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);

    // التعرف على النصوص
    final recognizedText = await textRecognizer.processImage(inputImage);

    // التعرف على الباركود
    final barcodes = await barcodeScanner.processImage(inputImage);
    String queryText = recognizedText.text.toLowerCase();
    if (barcodes.isNotEmpty) {
      queryText += ' ' + barcodes.map((b) => b.displayValue ?? '').join(' ');
    }

    await _searchProducts(queryText);
  }

  /// --- البحث عن المنتجات في قاعدة البيانات
  Future<void> _searchProducts(String queryText) async {
    final db = await DatabaseHelper.instance.database;

    final res = await db.query(
      'Products',
      where: 'LOWER(name) LIKE ? OR barcode LIKE ?',
      whereArgs: ['%$queryText%', '%$queryText%'],
    );

    setState(() {
      _suggestedProducts = res;
      _isLoading = false;
    });

    if (_suggestedProducts.isEmpty) {
      _showAddProductDialog();
    } else {
      _showProductOptionsDialog();
    }
  }

  /// --- إضافة منتج جديد
  void _showAddProductDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Product not found'),
        content: const Text('Do you want to add this product to inventory?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                // فتح صفحة إضافة منتج جديد
              },
              child: const Text('Add Product')),
        ],
      ),
    );
  }

  /// --- عرض المنتجات المقترحة مع خيارات البيع والشراء
  void _showProductOptionsDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Found ${_suggestedProducts.length} product(s)'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _suggestedProducts.length,
            itemBuilder: (context, index) {
              final p = _suggestedProducts[index];
              return Card(
                child: ListTile(
                  title: Text(p['name']),
                  subtitle: Text(
                      'Qty: ${p['quantity']} | Sale: ${p['sale_price']} ${p['sale_currency']} | Expiry: ${p['expiry_date']}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.shopping_cart),
                        tooltip: 'Sell',
                        onPressed: () {
                          Navigator.pop(context);
                          _sellProduct(p);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_box),
                        tooltip: 'Buy / Add Stock',
                        onPressed: () {
                          Navigator.pop(context);
                          _buyProduct(p);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// --- بيع المنتج
  Future<void> _sellProduct(Map<String, dynamic> product) async {
    if ((product['quantity'] as int) <= 0) {
      _showMessage('Product out of stock!');
      return;
    }
    final newQty = (product['quantity'] as int) - 1;
    await DatabaseHelper.instance.updateProduct({
      'product_id': product['product_id'],
      'quantity': newQty,
    });
    _showMessage('Sold 1 item. Remaining: $newQty');
  }

  /// --- شراء / إضافة للمخزون
  Future<void> _buyProduct(Map<String, dynamic> product) async {
    final quantityToAdd = 1;
    final newQty = (product['quantity'] as int) + quantityToAdd;
    await DatabaseHelper.instance.updateProduct({
      'product_id': product['product_id'],
      'quantity': newQty,
    });
    _showMessage('Added $quantityToAdd item(s). Total: $newQty');
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// --- عرض واجهة انتهاء الصلاحية
  Future<List<Map<String, dynamic>>> loadExpirationProducts() async {
    final db = await DatabaseHelper.instance.database;
    final rawProducts = await db.rawQuery('''
      SELECT name, expiry_date, quantity
      FROM Products
      WHERE expiry_date IS NOT NULL AND expiry_date != ''
    ''');

    final products = rawProducts.map((p) {
      final date = _parseDateSafe(p['expiry_date']);
      if (date == null) return null;
      return {
        'name': p['name'],
        'expiry_date': date,
        'quantity': p['quantity'],
      };
    }).where((p) => p != null).cast<Map<String, dynamic>>().toList();

    products.sort((a, b) => (a['expiry_date'] as DateTime).compareTo(a['expiry_date'] as DateTime));
    return products;
  }

  DateTime? _parseDateSafe(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s); // صيغة ISO
    } catch (_) {
      try {
        return DateFormat('yyyy-MM-dd').parseStrict(s);
      } catch (_) {
        return null;
      }
    }
  }

  @override
  void dispose() {
    textRecognizer.close();
    barcodeScanner.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Inventory / Expiration')),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
                onPressed: _pickImage,
                child: const Text('Capture Product Image / Scan Barcode')),
            const SizedBox(height: 20),
            ElevatedButton(
                onPressed: () async {
                  final products = await loadExpirationProducts();
                  if (products.isEmpty) {
                    _showMessage('No products with expiry found!');
                  } else {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ExpirationListScreen(products: products)));
                  }
                },
                child: const Text('View Expiration List')),
          ],
        ),
      ),
    );
  }
}

/// --- شاشة قائمة المنتجات حسب الصلاحية
class ExpirationListScreen extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  const ExpirationListScreen({super.key, required this.products});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final expired = products.where((p) => (p['expiry_date'] as DateTime).isBefore(today)).toList();
    final near = products
        .where((p) => (p['expiry_date'] as DateTime).isAfter(today) && (p['expiry_date'] as DateTime).isBefore(today.add(const Duration(days: 30))))
        .toList();
    final safe = products
        .where((p) => (p['expiry_date'] as DateTime).isAfter(today.add(const Duration(days: 30))))
        .toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Expiration List'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Expired'),
            Tab(text: 'Near Expiration'),
            Tab(text: 'Safe'),
          ]),
        ),
        body: TabBarView(
          children: [
            _buildList(expired),
            _buildList(near),
            _buildList(safe),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> list) {
    if (list.isEmpty) return const Center(child: Text('No products in this category'));
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        final p = list[index];
        final color = (p['expiry_date'] as DateTime).isBefore(DateTime.now())
            ? Colors.red
            : (p['expiry_date'] as DateTime).isBefore(DateTime.now().add(const Duration(days: 30)))
            ? Colors.orange
            : Colors.green;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: color, child: const Icon(Icons.medication, color: Colors.white)),
            title: Text(p['name']),
            subtitle: Text(
                'Expiry: ${DateFormat('yyyy-MM-dd').format(p['expiry_date'])}\nQuantity: ${p['quantity']}'),
            trailing: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        );
      },
    );
  }
}
