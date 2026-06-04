import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'datdbase.dart';
import 'add-edd-product.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

class SmartInventoryScreen extends StatefulWidget {
  const SmartInventoryScreen({super.key});

  @override
  State<SmartInventoryScreen> createState() => _SmartInventoryScreenState();
}

class _SmartInventoryScreenState extends State<SmartInventoryScreen> {
  bool _isLoading = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ─── إذن الكاميرا ───────────────────────────────────────────────────────────
  Future<void> _handleCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isPermanentlyDenied) {
      _showPermissionDialog();
      return;
    }
    if (!status.isGranted) {
      status = await Permission.camera.request();
      if (!status.isGranted) {
        _showSnack("إذن الكاميرا مطلوب لمسح الباركود");
        return;
      }
    }
    _openScanner();
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("إذن الكاميرا"),
        content: const Text(
            "لقد تم رفض إذن الكاميرا بشكل دائم.\nيرجى تفعيله من إعدادات التطبيق."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("إلغاء")),
          ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              child: const Text("فتح الإعدادات")),
        ],
      ),
    );
  }

  Future<void> _openScanner() async {
    if (!mounted) return;
    final String? scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (scannedCode != null && scannedCode.trim().isNotEmpty) {
      _searchController.text = scannedCode.trim();
      await _searchProducts(scannedCode.trim());
    }
  }

  // ─── البحث في قاعدة البيانات ─────────────────────────────────────────────
  Future<void> _searchProducts(String queryText) async {
    final clean = queryText.trim();
    if (clean.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final db = await DatabaseHelper.instance.database;

      // بحث بالباركود (تطابق تام) أو الاسم (تطابق جزئي)
      final results = await db.query(
        'Products',
        where: 'deleted = 0 AND (barcode = ? OR LOWER(name) LIKE ?)',
        whereArgs: [clean, '%${clean.toLowerCase()}%'],
        orderBy: 'name ASC',
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (results.isEmpty) {
        _showNotFoundSheet(clean);
      } else {
        _showProductSheet(results, clean);
      }
    } catch (e) {
      debugPrint("Search Error: $e");
      if (mounted) setState(() => _isLoading = false);
      _showSnack("خطأ أثناء البحث");
    }
  }

  // ─── شاشة "المنتج غير موجود" ─────────────────────────────────────────────
  void _showNotFoundSheet(String barcode) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotFoundSheet(
        barcode: barcode,
        onAddProduct: () async {
          Navigator.pop(context);
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddProductScreen(
                initialBarcode: barcode,
              ),
            ),
          );
          if (result == true) {
            _showSnack("تمت إضافة المنتج بنجاح ✅");
            await _searchProducts(barcode);
          }
        },
      ),
    );
  }

  // ─── شاشة عرض المنتجات الموجودة ──────────────────────────────────────────
  void _showProductSheet(List<Map<String, dynamic>> products, String lastQuery) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductResultSheet(
        products: products,
        onSale: (product) async {
          await _showSaleDialog(product);
          await _searchProducts(lastQuery);
        },
        onAddStock: (product) async {
          await _showAddStockDialog(product);
          await _searchProducts(lastQuery);
        },
        onEdit: (product) async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddProductScreen(product: product),
            ),
          );
          if (result == true) {
            _showSnack("تم تعديل المنتج ✅");
            await _searchProducts(lastQuery);
          }
        },
      ),
    );
  }

  // ─── بيع المنتج ──────────────────────────────────────────────────────────
  Future<void> _showSaleDialog(Map<String, dynamic> product) async {
    int qty = 1;
    final maxQty = (product['quantity'] as int? ?? 0);
    if (maxQty == 0) {
      _showSnack("لا يوجد مخزون كافٍ لهذا المنتج");
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true, // ✅ الحل الجذري لمشكلة overflow في الصناديق
          title: Row(
            children: [
              const Icon(Icons.shopping_cart, color: Colors.green),
              const SizedBox(width: 8),
              const Text("بيع المنتج"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(product['name'] ?? '',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                  "السعر: ${product['sale_price']} ${product['sale_currency'] ?? 'SYP'}"),
              Text("المتاح: $maxQty وحدة",
                  style: const TextStyle(color: Colors.blue)),
              const Divider(height: 24),
              const Text("الكمية المراد بيعها:"),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon:
                    const Icon(Icons.remove_circle, color: Colors.red, size: 32),
                    onPressed: qty > 1
                        ? () => setDialogState(() => qty--)
                        : null,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue),
                    ),
                    child: Text("$qty",
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle,
                        color: Colors.green, size: 32),
                    onPressed: qty < maxQty
                        ? () => setDialogState(() => qty++)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "الإجمالي: ${((product['sale_price'] as num) * qty).toStringAsFixed(2)} ${product['sale_currency'] ?? 'SYP'}",
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("إلغاء")),
            ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text("تأكيد البيع"),
              style:
              ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () async {
                Navigator.pop(ctx);
                await _processSale(product, qty);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processSale(Map<String, dynamic> product, int qty) async {
    try {
      final salePrice = (product['sale_price'] as num?)?.toDouble() ?? 0.0;
      await DatabaseHelper.instance.createSale(
        salePrice * qty,
        [
          {
            'product_id': product['product_id'],
            'quantity': qty,
            'price': salePrice,
          }
        ],
      );
      _showSnack("تم بيع $qty وحدة من ${product['name']} ✅");
    } catch (e) {
      debugPrint("Sale error: $e");
      _showSnack("حدث خطأ أثناء البيع");
    }
  }

  // ─── إضافة مخزون ─────────────────────────────────────────────────────────
  Future<void> _showAddStockDialog(Map<String, dynamic> product) async {
    final controller = TextEditingController(text: "1");

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true, // ✅ الحل الجذري لمشكلة overflow في الصناديق
        title: Row(
          children: [
            const Icon(Icons.add_box, color: Colors.blue),
            const SizedBox(width: 8),
            const Text("إضافة مخزون"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(product['name'] ?? '',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            Text("المخزون الحالي: ${product['quantity']} وحدة",
                style: const TextStyle(color: Colors.blue)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: "الكمية المضافة",
                prefixIcon: const Icon(Icons.add),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("إلغاء")),
          ElevatedButton.icon(
            icon: const Icon(Icons.check),
            label: const Text("إضافة"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () async {
              final addQty = int.tryParse(controller.text) ?? 0;
              if (addQty <= 0) {
                _showSnack("أدخل كمية صحيحة");
                return;
              }
              Navigator.pop(ctx);
              final currentQty = (product['quantity'] as int? ?? 0);
              await DatabaseHelper.instance.updateProduct({
                ...product,
                'quantity': currentQty + addQty,
              });
              _showSnack("تمت إضافة $addQty وحدة إلى المخزون ✅");
            },
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  // ─── واجهة المستخدم الرئيسية ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('الماسح الذكي'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView( // ✅ إضافة التمرير للواجهة بالكامل لمنع overflow عند ظهور الكيبورد
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // ─ حقل البحث اليدوي ─
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: "اسم المنتج أو الباركود",
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                  )
                      : null,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                  filled: true,
                  fillColor: Colors.white,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: _searchProducts,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _searchController.text.trim().isEmpty
                      ? null
                      : () => _searchProducts(_searchController.text),
                  icon: const Icon(Icons.search),
                  label: const Text("بحث"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // ─ زر المسح ─
              if (_isLoading)
                const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text("جاري البحث..."),
                  ],
                )
              else ...[
                GestureDetector(
                  onTap: _handleCameraPermission,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue.shade200, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.15),
                          blurRadius: 20,
                          spreadRadius: 4,
                        )
                      ],
                    ),
                    child: const Icon(Icons.qr_code_scanner,
                        size: 80, color: Colors.blue),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "اضغط لمسح الباركود",
                  style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _handleCameraPermission,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text("فتح الكاميرا"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Bottom Sheet: المنتج غير موجود
// ═══════════════════════════════════════════════════════════════════════════════
class _NotFoundSheet extends StatelessWidget {
  final String barcode;
  final VoidCallback onAddProduct;

  const _NotFoundSheet({required this.barcode, required this.onAddProduct});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Icon(Icons.search_off, size: 56, color: Colors.orange),
          const SizedBox(height: 12),
          const Text("المنتج غير موجود",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.qr_code, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text(barcode,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 15)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "هذا المنتج غير مسجل في المخزون.\nهل تريد إضافته الآن؟",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onAddProduct,
              icon: const Icon(Icons.add),
              label: const Text("إضافة المنتج للمخزون",
                  style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("إغلاق"),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Bottom Sheet: عرض نتائج البحث
// ═══════════════════════════════════════════════════════════════════════════════
class _ProductResultSheet extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  final void Function(Map<String, dynamic>) onSale;
  final void Function(Map<String, dynamic>) onAddStock;
  final void Function(Map<String, dynamic>) onEdit;

  const _ProductResultSheet({
    required this.products,
    required this.onSale,
    required this.onAddStock,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.inventory_2, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        "نتائج البحث (${products.length})",
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: products.length,
                itemBuilder: (_, i) {
                  final p = products[i];
                  final qty = (p['quantity'] as int? ?? 0);
                  final price = (p['sale_price'] as num?)?.toDouble() ?? 0.0;
                  final currency = p['sale_currency'] as String? ?? 'SYP';
                  final expiry = p['expiry_date'] as String?;
                  final outOfStock = qty == 0;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: outOfStock
                            ? Colors.red.shade100
                            : Colors.transparent,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Color(0xFFE3F2FD),
                                child: Icon(Icons.medication,
                                    color: Colors.blue, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p['name'] as String? ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                    ),
                                    if (p['category'] != null)
                                      Text(
                                        p['category'] as String,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[500]),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: outOfStock
                                      ? Colors.red.shade50
                                      : qty < 5
                                      ? Colors.orange.shade50
                                      : Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: outOfStock
                                        ? Colors.red.shade200
                                        : qty < 5
                                        ? Colors.orange.shade200
                                        : Colors.green.shade200,
                                  ),
                                ),
                                child: Text(
                                  outOfStock ? "نفد المخزون" : "$qty وحدة",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: outOfStock
                                        ? Colors.red
                                        : qty < 5
                                        ? Colors.orange
                                        : Colors.green,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _InfoChip(
                                icon: Icons.attach_money,
                                label:
                                "${price.toStringAsFixed(2)} $currency",
                                color: Colors.green,
                              ),
                              if (expiry != null && expiry.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                _InfoChip(
                                  icon: Icons.event,
                                  label: expiry,
                                  color: Colors.purple,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _ActionButton(
                                  icon: Icons.shopping_cart_checkout,
                                  label: "بيع",
                                  color: Colors.green,
                                  enabled: !outOfStock,
                                  onPressed: () {
                                    Navigator.pop(context);
                                    onSale(p);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _ActionButton(
                                  icon: Icons.add_box_outlined,
                                  label: "إضافة",
                                  color: Colors.blue,
                                  onPressed: () {
                                    Navigator.pop(context);
                                    onAddStock(p);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _ActionButton(
                                  icon: Icons.edit_outlined,
                                  label: "تعديل",
                                  color: Colors.orange,
                                  onPressed: () {
                                    Navigator.pop(context);
                                    onEdit(p);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip({required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final bool enabled;
  const _ActionButton({required this.icon, required this.label, required this.color, required this.onPressed, this.enabled = true});
  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled ? color : Colors.grey[300],
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
    );
  }
}

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});
  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  late MobileScannerController controller;
  bool _isDetected = false;
  @override
  void initState() {
    super.initState();
    controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
      returnImage: false,
    );
  }
  void _processBarcode(String value) {
    if (_isDetected) return;
    setState(() => _isDetected = true);
    HapticFeedback.mediumImpact();
    controller.stop();
    if (mounted) Navigator.pop(context, value);
  }
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("مسح الباركود"),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (_, state, __) => IconButton(
              icon: Icon(
                state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
                color: state.torchState == TorchState.on ? Colors.yellow : Colors.white,
              ),
              onPressed: controller.toggleTorch,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            fit: BoxFit.cover,
            errorBuilder: (_, error, __) => Center(
              child: Text("خطأ: ${error.errorCode}\n${error.errorDetails?.message ?? ''}", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 14)),
            ),
            onDetect: (capture) {
              if (_isDetected || capture.barcodes.isEmpty) return;
              for (final b in capture.barcodes) {
                final raw = b.rawValue;
                if (raw != null && raw.trim().isNotEmpty) {
                  _processBarcode(raw.trim());
                  return;
                }
              }
            },
          ),
          Center(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(border: Border.all(color: Colors.blue, width: 3), borderRadius: BorderRadius.circular(14)),
              child: Center(child: Container(width: double.infinity, height: 2, color: Colors.red.withValues(alpha: 0.8))),
            ),
          ),
          if (_isDetected) const Center(child: CircularProgressIndicator(color: Colors.green)),
          const Positioned(bottom: 50, left: 0, right: 0, child: Text("وجّه الكاميرا نحو الباركود", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16, backgroundColor: Colors.black54))),
        ],
      ),
    );
  }
}
