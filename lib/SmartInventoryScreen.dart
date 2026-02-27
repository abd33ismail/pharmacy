import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'datdbase.dart';

class SmartProductScanScreen extends StatefulWidget {
  const SmartProductScanScreen({super.key});

  @override
  State<SmartProductScanScreen> createState() => _SmartProductScanScreenState();
}

class _SmartProductScanScreenState extends State<SmartProductScanScreen> {
  bool _isLoading = false;
  File? _image;
  List<Map<String, dynamic>> _suggestedProducts = [];

  final ImagePicker _picker = ImagePicker();
  final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// 🔹 التقاط صورة من الكاميرا
  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.camera);
    if (pickedFile == null) return;

    setState(() {
      _image = File(pickedFile.path);
      _isLoading = true;
    });

    await _processImage(_image!);
  }

  /// 🔹 التعرف على النصوص من الصورة
  Future<void> _processImage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognizedText = await textRecognizer.processImage(inputImage);

    // دمج كل النصوص المستخرجة
    final text = recognizedText.blocks.map((b) => b.text).join(' ').toLowerCase();

    await _searchProducts(text);
  }

  /// 🔹 البحث عن المنتجات في قاعدة البيانات
  Future<void> _searchProducts(String queryText) async {
    final db = await DatabaseHelper.instance.database;

    final res = await db.query(
      'Products',
      where: 'LOWER(name) LIKE ?',
      whereArgs: ['%$queryText%'],
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

  /// 🔹 عرض الخيارات لكل منتج
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
                      'Qty: ${p['quantity']} | Sale: ${p['sale_price']} ${p['sale_currency']}'),
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

  /// 🔹 بيع المنتج
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

  /// 🔹 شراء / إضافة المخزون
  Future<void> _buyProduct(Map<String, dynamic> product) async {
    final quantityToAdd = 1; // وحدة واحدة كمثال
    final newQty = (product['quantity'] as int) + quantityToAdd;

    await DatabaseHelper.instance.updateProduct({
      'product_id': product['product_id'],
      'quantity': newQty,
    });

    _showMessage('Added $quantityToAdd item(s). Total: $newQty');
  }

  /// 🔹 إضافة منتج جديد
  void _showAddProductDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Product not found'),
        content: const Text('Do you want to add this product to inventory?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // يمكن فتح صفحة إضافة منتج جديدة هنا
            },
            child: const Text('Add Product'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Product Scan')),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : ElevatedButton(
          onPressed: _pickImage,
          child: const Text('Capture Product Image'),
        ),
      ),
    );
  }
}
