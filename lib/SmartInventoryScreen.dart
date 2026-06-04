import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'datdbase.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

class SmartInventoryScreen extends StatefulWidget {
  const SmartInventoryScreen({super.key});

  @override
  State<SmartInventoryScreen> createState() => _SmartInventoryScreenState();
}

class _SmartInventoryScreenState extends State<SmartInventoryScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _suggestedProducts = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // طلب إذن الكاميرا بشكل متقدم
  Future<void> _handleCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isPermanentlyDenied) {
      _showPermissionDialog();
      return;
    }
    
    if (!status.isGranted) {
      status = await Permission.camera.request();
      if (!status.isGranted) {
        _showMessage("إذن الكاميرا مطلوب لمسح الباركود");
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
        content: const Text("لقد تم رفض إذن الكاميرا بشكل دائم. يرجى تفعيله من إعدادات التطبيق لتتمكن من مسح الباركود."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          TextButton(onPressed: () => openAppSettings(), child: const Text("الإعدادات")),
        ],
      ),
    );
  }

  // فتح الماسح
  Future<void> _openScanner() async {
    if (!mounted) return;

    final String? scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );

    if (scannedCode != null && scannedCode.trim().isNotEmpty) {
      _onCodeScanned(scannedCode.trim());
    }
  }

  void _onCodeScanned(String code) {
    setState(() {
      _searchController.text = code;
    });
    _searchProducts(code);
  }

  /// --- البحث الشامل في قاعدة البيانات
  Future<void> _searchProducts(String queryText) async {
    if (queryText.trim().isEmpty) return;
    
    setState(() => _isLoading = true);
    final db = await DatabaseHelper.instance.database;
    final String cleanQuery = queryText.trim();

    try {
      // البحث بالباركود (تطابق تام) أو الاسم (تطابق جزئي)
      final res = await db.query(
        'Products',
        where: 'barcode = ? OR LOWER(name) LIKE ?',
        whereArgs: [
          cleanQuery,
          '%${cleanQuery.toLowerCase()}%',
        ],
      );

      if (mounted) {
        setState(() {
          _suggestedProducts = res;
          _isLoading = false;
        });

        if (_suggestedProducts.isEmpty) {
          _showAddProductDialog(cleanQuery);
        } else {
          _showProductOptionsDialog(cleanQuery);
        }
      }
    } catch (e) {
      debugPrint("Database Search Error: $e");
      if (mounted) setState(() => _isLoading = false);
      _showMessage("خطأ أثناء البحث في البيانات");
    }
  }

  void _showAddProductDialog(String barcode) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('المنتج غير موجود'),
        content: Text('الرمز: $barcode\n\nهذا المنتج غير مسجل. هل تريد إضافته الآن؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showMessage("خاصية الإضافة ستتوفر قريباً");
              },
              child: const Text('إضافة منتج')),
        ],
      ),
    );
  }

  void _showProductOptionsDialog(String lastSearch) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('نتائج البحث (${_suggestedProducts.length})'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _suggestedProducts.length,
            itemBuilder: (context, index) {
              final p = _suggestedProducts[index];
              return Card(
                elevation: 2,
                child: ExpansionTile(
                  leading: const Icon(Icons.medication, color: Colors.blue),
                  title: Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('الكمية: ${p['quantity']} | السعر: ${p['sale_price']}'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // معلومات المنتج
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'تفاصيل المنتج',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(height: 8),
                                Text('الفئة: ${p['category'] ?? 'غير محدد'}', style: const TextStyle(fontSize: 12)),
                                Text('السعر: ${p['sale_price']} (${p['sale_currency'] ?? 'SYP'})', style: const TextStyle(fontSize: 12)),
                                Text('المخزون: ${p['quantity']} وحدة', style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // الخيارات
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(Icons.shopping_cart),
                                  label: const Text('بيع'),
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    _showSaleDialog(p);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(Icons.add),
                                  label: const Text('إضافة'),
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    await _updateQuantity(p, 1);
                                    _searchProducts(lastSearch);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(Icons.remove),
                                  label: const Text('خصم'),
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    await _updateQuantity(p, -1);
                                    _searchProducts(lastSearch);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  void _showSaleDialog(Map<String, dynamic> product) {
    int quantity = 1;
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('بيع المنتج'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('المنتج: ${product['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('السعر: ${product['sale_price']} ${product['sale_currency'] ?? "SYP"}'),
              const SizedBox(height: 12),
              Text('المخزون المتاح: ${product['quantity']}'),
              const SizedBox(height: 20),
              const Text('أدخل الكمية:'),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle, color: Colors.red),
                    onPressed: () {
                      if (quantity > 1) {
                        setState(() => quantity--);
                      }
                    },
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blue),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$quantity',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.green),
                    onPressed: () {
                      if (quantity < product['quantity']) {
                        setState(() => quantity++);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'الإجمالي: ${(product['sale_price'] as num) * quantity} ${product['sale_currency'] ?? "SYP"}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _processSale(product, quantity);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('تأكيد البيع'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processSale(Map<String, dynamic> product, int quantity) async {
    try {
      final int currentQty = (product['quantity'] as int? ?? 0);
      
      if (quantity <= 0 || quantity > currentQty) {
        _showMessage("الكمية غير صحيحة");
        return;
      }

      // تحديث المخزون
      await DatabaseHelper.instance.updateProduct({
        'product_id': product['product_id'],
        'quantity': currentQty - quantity,
        'name': product['name'],
        'category': product['category'],
      });
      
      _showMessage("تم بيع $quantity وحدة بنجاح");
    } catch (e) {
      debugPrint("Sale Error: $e");
      _showMessage("حدث خطأ أثناء البيع");
    }
  }

  Future<void> _updateQuantity(Map<String, dynamic> product, int change) async {
    final int currentQty = (product['quantity'] as int? ?? 0);
    final int newQty = currentQty + change;
    
    if (newQty < 0) {
      _showMessage("الكمية غير كافية");
      return;
    }

    await DatabaseHelper.instance.updateProduct({
      'product_id': product['product_id'],
      'quantity': newQty,
      'name': product['name'],
      'category': product['category'],
    });
    
    _showMessage(change > 0 ? "تمت إضافة قطعة" : "تم خصم قطعة");
  }

  void _showMessage(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('نظام الصيدلية الذكي')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "أدخل الباركود أو اسم المنتج يدوياً",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _searchController.clear(),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              onSubmitted: _searchProducts,
            ),
            const SizedBox(height: 40),
            if (_isLoading)
              const CircularProgressIndicator()
            else ...[
              const Text("اضغط للمسح الضوئي", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              InkWell(
                onTap: _handleCameraPermission,
                borderRadius: BorderRadius.circular(100),
                child: Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue.withOpacity(0.3), width: 2),
                  ),
                  child: const Icon(Icons.qr_code_scanner, size: 100, color: Colors.blue),
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _handleCameraPermission,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text("ابدأ المسح بالكاميرا"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}

// --- صفحة الماسح المستقلة والمحسنة ---
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
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
      returnImage: false,
      formats: [BarcodeFormat.ean8,
        BarcodeFormat.ean13,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.code93,
        BarcodeFormat.itf,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,

      ],
    );
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
          // لتجنب خطأ torchState غير المعرف، نستخدم controller نفسه كمستمع للقيمة
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, state, child) {
              final torchState = state.torchState;
              return IconButton(
                icon: Icon(
                  torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
                  color: torchState == TorchState.on ? Colors.yellow : Colors.white,
                ),
                onPressed: () => controller.toggleTorch(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            fit: BoxFit.cover,

            errorBuilder: (context, error, child) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 60),
                    const SizedBox(height: 10),
                    Text("خطأ في الكاميرا: ${error.errorCode}", 
                        style: const TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 10),
                    const Text("تأكد من إعطاء الصلاحيات أو جرب البحث اليدوي", 
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              );
            },
            onDetect: (capture) async {
              if (_isDetected) return;

              final barcode = capture.barcodes.first;

              if (barcode.rawValue != null &&
                  barcode.rawValue!.isNotEmpty) {

                _isDetected = true;

                await controller.stop();

                HapticFeedback.mediumImpact();

                if (mounted) {
                  Navigator.pop(context, barcode.rawValue);
                }
              }
            },
          ),
          // إطار المسح المرئي للمساعدة في التركيز
          Center(
            child: Container(
              width: 260,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue, width: 3),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Stack(
                children: [
                  Center(child: Container(width: double.infinity, height: 1, color: Colors.red.withOpacity(0.5))),
                ],
              ),
            ),
          ),
          const Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              "وجه الكاميرا نحو باركود المنتج",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16, backgroundColor: Colors.black45),
            ),
          ),
        ],
      ),
    );
  }
}
