import 'dart:io';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

// --- دالة عالمية للمزامنة السريعة ---
Future<void> addMedicine({
  required String name,
  required String saleprice,
  required String quantity,
  required String expiryDate,
  required String barcode,
  required String currency,
  required String category,
  required String purchasePrice,
  required String purchaseCurrency,
}) async {
  var body = {
    "name": name, "sale_price": saleprice, "purchase_price": purchasePrice,
    "quantity": quantity, "barcode": barcode, "expiry_date": expiryDate,
    "currency": currency, "category": category, "purchase_currency": purchaseCurrency.toUpperCase(),
  };
  try {
    var url = Uri.parse("http://10.0.2.2/pharmacy_api/add_medicine.php");
    await http.post(url, body: body);
    DatabaseHelper.instance.notifyListeners();
  } catch (e) {
    debugPrint("Sync error: $e");
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  final _dbChangesController = StreamController<void>.broadcast();
  Stream<void> get onDatabaseChanged => _dbChangesController.stream;

  void notifyListeners() {
    _dbChangesController.add(null);
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pharmacy_master.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 16, onCreate: _createDB, onUpgrade: _onUpgrade);
  }

  Future _onUpgrade(Database db, int oldVer, int newVer) async {
    if (oldVer < 12) {
      try { await db.execute("ALTER TABLE Sales ADD COLUMN synced INTEGER DEFAULT 0"); } catch (_) {}
      try { await db.execute("ALTER TABLE Refunds ADD COLUMN synced INTEGER DEFAULT 0"); } catch (_) {}
    }
    if (oldVer < 15) {
      try { await db.execute("ALTER TABLE Sales ADD COLUMN invoice_daily TEXT"); } catch (_) {}
      await db.execute('''
        CREATE TABLE IF NOT EXISTS DailyInvoiceCounter (
          date TEXT PRIMARY KEY,
          last_number INTEGER
        )
      ''');
    }
    if (oldVer < 16) {
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_products_barcode ON Products(barcode)');
      } catch (_) {}
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''CREATE TABLE Products (product_id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, category TEXT NOT NULL, barcode TEXT UNIQUE, purchase_price REAL, purchase_currency TEXT, sale_price REAL, sale_currency TEXT, quantity INTEGER, expiry_date TEXT, image TEXT, created_at TEXT, uuid TEXT, synced INTEGER DEFAULT 0, updated_at TEXT, deleted INTEGER DEFAULT 0)''');
    
    // إضافة Index للباركود للبحث الفوري
    await db.execute('CREATE INDEX idx_products_barcode ON Products(barcode)');

    await db.execute('''CREATE TABLE Sales (sale_id INTEGER PRIMARY KEY AUTOINCREMENT, sale_date TEXT, total_amount REAL, edited INTEGER DEFAULT 0, synced INTEGER DEFAULT 0, invoice_daily TEXT)''');
    await db.execute('''CREATE TABLE Sale_Items (id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER, product_id INTEGER, quantity INTEGER, price REAL, purchase_price REAL, FOREIGN KEY (sale_id) REFERENCES Sales (sale_id) ON DELETE CASCADE, FOREIGN KEY (product_id) REFERENCES Products (product_id))''');
    await db.execute('''CREATE TABLE Refunds (refund_id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER, refund_date TEXT, total_refund REAL, note TEXT, synced INTEGER DEFAULT 0)''');
    await db.execute('''CREATE TABLE Refund_Items (id INTEGER PRIMARY KEY AUTOINCREMENT, refund_id INTEGER, product_id INTEGER, quantity INTEGER, price REAL, purchase_price REAL)''');
    await db.execute('''CREATE TABLE Notes (note_id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, content TEXT, created_at TEXT)''');
    await db.execute('''CREATE TABLE DailyInvoiceCounter (date TEXT PRIMARY KEY, last_number INTEGER)''');
  }

  // --- المزامنة التلقائية ---
  Future<void> syncAllData() async {
    try {
      await pushProducts();
      await fetchProducts();
      await pushSales();
      notifyListeners();
    } catch (e) {
      debugPrint("Global Sync Error: $e");
    }
  }

  Future<void> pushProducts() async {
    final db = await database;
    final unsynced = await db.query('Products', where: 'synced = 0');
    for (var p in unsynced) {
      try {
        var res = await http.post(Uri.parse("http://10.0.2.2/pharmacy_api/sync_product.php"), body: {
          "uuid": p['uuid']?.toString() ?? "",
          "name": p['name'].toString(),
          "category": p['category'].toString(),
          "barcode": p['barcode']?.toString() ?? "",
          "purchase_price": p['purchase_price'].toString(),
          "sale_price": p['sale_price'].toString(),
          "quantity": p['quantity'].toString(),
          "expiry_date": p['expiry_date']?.toString() ?? "",
          "deleted": p['deleted'].toString(),
        });
        if (res.statusCode == 200) await db.update('Products', {'synced': 1}, where: 'product_id = ?', whereArgs: [p['product_id']]);
      } catch (_) {}
    }
  }

  Future<void> fetchProducts() async {
    final db = await database;
    try {
      var res = await http.get(Uri.parse("http://10.0.2.2/pharmacy_api/get_products.php"));
      if (res.statusCode == 200) {
        List<dynamic> data = json.decode(res.body);
        for (var p in data) {
          final uuid = p['uuid'];
          if (uuid == null) continue;
          final existing = await db.query('Products', where: 'uuid = ?', whereArgs: [uuid]);
          Map<String, dynamic> row = {
            'name': p['name'], 'category': p['category'], 'barcode': p['barcode'],
            'purchase_price': double.tryParse(p['purchase_price'].toString()) ?? 0.0,
            'sale_price': double.tryParse(p['sale_price'].toString()) ?? 0.0,
            'quantity': int.tryParse(p['quantity'].toString()) ?? 0,
            'expiry_date': p['expiry_date'], 'deleted': int.tryParse(p['deleted'].toString()) ?? 0,
            'synced': 1, 'updated_at': DateTime.now().toIso8601String(),
          };
          if (existing.isNotEmpty) await db.update('Products', row, where: 'uuid = ?', whereArgs: [uuid]);
          else { row['uuid'] = uuid; await db.insert('Products', row); }
        }
      }
    } catch (_) {}
  }

  Future<void> pushSales() async {
    final db = await database;
    final unsyncedSales = await db.query('Sales', where: 'synced = 0');
    
    if (unsyncedSales.isNotEmpty) {
      debugPrint("Found ${unsyncedSales.length} unsynced sales. Starting sync...");
    }

    for (var sale in unsyncedSales) {
      int saleId = sale['sale_id'] as int;
      final items = await db.rawQuery("""
        SELECT si.*, p.name 
        FROM Sale_Items si 
        JOIN Products p ON si.product_id = p.product_id
        WHERE si.sale_id = ?
      """, [saleId]);

      Map<String, dynamic> invoiceData = {
        "sale_id": saleId,
        "invoice_number": sale['invoice_daily'] ?? "INV-$saleId",
        "total_amount": sale['total_amount'],
        "items_count": items.length,
        "sale_date": sale['sale_date'],
        "is_refunded": 0,
        "items": items.map((item) => {
          "product_name": item['name'],
          "quantity": item['quantity'],
          "price": item['price']
        }).toList()
      };

      try {
        var res = await http.post(
          Uri.parse("http://10.0.2.2/pharmacy_api/save_invoice.php"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(invoiceData),
        );

        if (res.statusCode == 200) {
          final serverData = jsonDecode(res.body);
          final newInvoiceNumber = serverData['invoice_number'];
          
          await db.update('Sales', {
            'synced': 1, 
            'invoice_daily': newInvoiceNumber
          }, where: 'sale_id = ?', whereArgs: [saleId]);
          
          debugPrint("Sale $saleId synced successfully with server invoice: $newInvoiceNumber");
          notifyListeners();
        } else {
          debugPrint("Failed to sync sale $saleId: ${res.body}");
        }
      } catch (e) {
        debugPrint("Sales sync error for ID $saleId: $e");
      }
    }
  }

  // --- العمليات الأساسية ---
  Future<bool> isBarcodeExists(String barcode, {int? excludeId}) async {
    if (barcode.isEmpty) return false;
    final db = await database;
    List<Map<String, dynamic>> res;
    if (excludeId != null) {
      res = await db.query('Products', where: 'barcode = ? AND product_id != ? AND deleted = 0', whereArgs: [barcode, excludeId]);
    } else {
      res = await db.query('Products', where: 'barcode = ? AND deleted = 0', whereArgs: [barcode]);
    }
    return res.isNotEmpty;
  }

  Future<int> addProduct(Map<String, dynamic> row) async {
    final db = await database;
    row['uuid'] = row['uuid'] ?? const Uuid().v4();
    row['synced'] = 0;
    int id = await db.insert('Products', row);
    notifyListeners();
    syncAllData();
    return id;
  }
  Future<int> updateProduct(Map<String, dynamic> row) async {
    row['synced'] = 0;
    int res = await (await database).update('Products', row, where: 'product_id = ?', whereArgs: [row['product_id']]);
    notifyListeners();
    syncAllData();
    return res;
  }
  Future<int> deleteProduct(int id) async {
    int res = await (await database).update('Products', {'deleted': 1, 'synced': 0}, where: 'product_id = ?', whereArgs: [id]);
    notifyListeners();
    syncAllData();
    return res;
  }

  Future<List<Map<String, dynamic>>> queryAllProducts() async => 
      (await database).query('Products', where: 'deleted = 0', orderBy: 'name ASC');
  
  Future<int> getTotalProductCount() async {
    final res = await (await database).rawQuery('SELECT COUNT(*) FROM Products WHERE deleted = 0');
    return Sqflite.firstIntValue(res) ?? 0;
  }
  
  Future<int> getExpirationAlertsCount() async {
    final threshold = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 30)));
    final res = await (await database).rawQuery("SELECT COUNT(*) FROM Products WHERE deleted = 0 AND quantity > 0 AND expiry_date <= ?", [threshold]);
    return Sqflite.firstIntValue(res) ?? 0;
  }

  Future<List<Map<String, dynamic>>> queryStockForExpiration() async => (await database).rawQuery("SELECT p.product_id, p.name AS product_name, p.expiry_date, p.quantity FROM Products p WHERE p.deleted = 0 AND p.quantity > 0 AND p.expiry_date != '' ORDER BY p.expiry_date ASC");

  // --- المبيعات ---
  Future<String> generateDailyInvoiceNumber(DatabaseExecutor txn) async {
    final now = DateTime.now();
    final dateKey = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    final existing = await txn.query('DailyInvoiceCounter', where: 'date = ?', whereArgs: [dateKey]);

    int newNumber;
    if (existing.isEmpty) {
      newNumber = 1;
      await txn.insert('DailyInvoiceCounter', {'date': dateKey, 'last_number': newNumber});
    } else {
      int last = existing.first['last_number'] as int;
      newNumber = last + 1;
      await txn.update('DailyInvoiceCounter', {'last_number': newNumber}, where: 'date = ?', whereArgs: [dateKey]);
    }
    return "$dateKey-${newNumber.toString().padLeft(4, '0')}";
  }

  Future<int> createSale(double total, List<Map<String, dynamic>> items) async {
    final db = await database;
    int saleId = await db.transaction((txn) async {
      String dailyNumber = await generateDailyInvoiceNumber(txn);
      int id = await txn.insert('Sales', {
        'sale_date': DateTime.now().toIso8601String(), 
        'total_amount': total, 
        'synced': 0, 
        'invoice_daily': dailyNumber,
      });
      for (var item in items) {
        final p = await txn.query('Products', where: 'product_id = ?', whereArgs: [item['product_id']]);
        double cost = (p.first['purchase_price'] as num?)?.toDouble() ?? 0.0;
        await txn.insert('Sale_Items', {'sale_id': id, 'product_id': item['product_id'], 'quantity': item['quantity'], 'price': item['price'], 'purchase_price': cost});
        await txn.rawUpdate('UPDATE Products SET quantity = quantity - ?, synced = 0 WHERE product_id = ?', [item['quantity'], item['product_id']]);
      }
      return id;
    });
    notifyListeners();
    syncAllData();
    return saleId;
  }

  Future<void> updateInvoiceNumber(int saleId, String invoiceNumber) async {
    final db = await database;
    await db.update('Sales', {'invoice_daily': invoiceNumber, 'synced': 1}, where: 'sale_id = ?', whereArgs: [saleId]);
    notifyListeners();
  }

  Future<void> deleteSale(int saleId) async {
    final db = await database;
    await db.transaction((txn) async {
      final refund = await txn.query('Refunds', where: 'sale_id = ?', whereArgs: [saleId]);
      if (refund.isEmpty) {
        final items = await txn.query('Sale_Items', where: 'sale_id = ?', whereArgs: [saleId]);
        for (var item in items) {
          await txn.rawUpdate('UPDATE Products SET quantity = quantity + ?, synced = 0 WHERE product_id = ?', [item['quantity'], item['product_id']]);
        }
      }
      await txn.delete('Refund_Items', where: 'refund_id IN (SELECT refund_id FROM Refunds WHERE sale_id = ?)', whereArgs: [saleId]);
      await txn.delete('Refunds', where: 'sale_id = ?', whereArgs: [saleId]);
      await txn.delete('Sale_Items', where: 'sale_id = ?', whereArgs: [saleId]);
      await txn.delete('Sales', where: 'sale_id = ?', whereArgs: [saleId]);
    });
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getTodayInvoices(DateTime d) async {
    final start = DateTime(d.year, d.month, d.day).toIso8601String();
    final end = DateTime(d.year, d.month, d.day).add(const Duration(days: 1)).toIso8601String();
    return await (await database).rawQuery("SELECT s.*, (SELECT COUNT(*) FROM Sale_Items WHERE sale_id = s.sale_id) as items_count, (SELECT COUNT(*) FROM Refunds WHERE sale_id = s.sale_id) as is_refunded FROM Sales s WHERE sale_date >= ? AND sale_date < ? ORDER BY sale_date DESC", [start, end]);
  }
  
  Future<List<Map<String, dynamic>>> getInvoiceDetails(int id) async => (await database).rawQuery("SELECT si.*, p.name, p.sale_currency FROM Sale_Items si JOIN Products p ON si.product_id = p.product_id WHERE si.sale_id = ?", [id]);

  // --- المرتجعات ---
  Future<void> createRefund(int saleId, List<Map<String, dynamic>> items) async {
    final db = await database;
    await db.transaction((txn) async {
      int rId = await txn.insert('Refunds', {'sale_id': saleId, 'refund_date': DateTime.now().toIso8601String(), 'total_refund': 0, 'synced': 0});
      double total = 0;
      for (var item in items) {
        total += (item['price'] as num) * (item['quantity'] as num);
        await txn.insert('Refund_Items', {'refund_id': rId, 'product_id': item['product_id'], 'quantity': item['quantity'], 'price': item['price'], 'purchase_price': item['purchase_price']});
        await txn.rawUpdate('UPDATE Products SET quantity = quantity + ?, synced = 0 WHERE product_id = ?', [item['quantity'], item['product_id']]);
      }
      await txn.update('Refunds', {'total_refund': total}, where: 'refund_id = ?', whereArgs: [rId]);
    });
    notifyListeners();
    syncAllData();
  }

  // --- التقارير ---
  Future<Map<String, double>> getDailyProfitStats(DateTime d) async {
    final start = DateTime(d.year, d.month, d.day).toIso8601String();
    final end = DateTime(d.year, d.month, d.day).add(const Duration(days: 1)).toIso8601String();
    final db = await database;
    final s = await db.rawQuery("SELECT COALESCE(SUM(si.price * si.quantity), 0) AS total_sales, COALESCE(SUM(si.purchase_price * si.quantity), 0) AS total_cost FROM Sale_Items si JOIN Sales sa ON si.sale_id = sa.sale_id WHERE sa.sale_date >= ? AND sa.sale_date < ?", [start, end]);
    final r = await db.rawQuery("SELECT COALESCE(SUM(ri.price * ri.quantity), 0) AS total_refund, COALESCE(SUM(ri.purchase_price * ri.quantity), 0) AS refund_cost FROM Refund_Items ri JOIN Refunds re ON ri.refund_id = re.refund_id WHERE re.refund_date >= ? AND re.refund_date < ?", [start, end]);
    double rev = (s.first['total_sales'] as num).toDouble() - (r.first['total_refund'] as num).toDouble();
    double cost = (s.first['total_cost'] as num).toDouble() - (r.first['refund_cost'] as num).toDouble();
    return {'sales': rev, 'cost': cost, 'profit': rev - cost, 'profit_percent': rev > 0 ? ((rev - cost) / rev) * 100 : 0};
  }
  
  Future<Map<String, double>> getMonthlyProfitStats(int y, int m) async {
    final prefix = "$y-${m.toString().padLeft(2, '0')}";
    final db = await database;
    final s = await db.rawQuery("SELECT COALESCE(SUM(si.price*si.quantity), 0) as s, COALESCE(SUM(si.purchase_price*si.quantity), 0) as c FROM Sale_Items si JOIN Sales sa ON si.sale_id = sa.sale_id WHERE sa.sale_date LIKE ?", ["$prefix%"]);
    final r = await db.rawQuery("SELECT COALESCE(SUM(ri.price*ri.quantity), 0) as s, COALESCE(SUM(ri.purchase_price*ri.quantity), 0) as c FROM Refund_Items ri JOIN Refunds re ON ri.refund_id = re.refund_id WHERE re.refund_date LIKE ?", ["$prefix%"]);
    double rev = (s.first['s'] as num).toDouble() - (r.first['s'] as num).toDouble();
    double cost = (s.first['c'] as num).toDouble() - (r.first['c'] as num).toDouble();
    return {'sales': rev, 'cost': cost, 'profit': rev - cost, 'profit_percent': rev > 0 ? ((rev - cost) / rev) * 100 : 0};
  }

  Future<List<Map<String, dynamic>>> getDailyReportsByCurrency(DateTime d) async {
    final start = DateTime(d.year, d.month, d.day).toIso8601String();
    final end = DateTime(d.year, d.month, d.day).add(const Duration(days: 1)).toIso8601String();
    final db = await database;
    return await db.rawQuery("""
      SELECT currency, SUM(sales) as sales, SUM(cost) as cost, (SUM(sales) - SUM(cost)) as profit
      FROM (
        SELECT p.sale_currency as currency, SUM(si.price * si.quantity) as sales, SUM(si.purchase_price * si.quantity) as cost
        FROM Sale_Items si JOIN Sales s ON si.sale_id = s.sale_id JOIN Products p ON si.product_id = p.product_id 
        WHERE s.sale_date >= ? AND s.sale_date < ? GROUP BY p.sale_currency
        UNION ALL
        SELECT p.sale_currency as currency, -SUM(ri.price * ri.quantity) as sales, -SUM(ri.purchase_price * ri.quantity) as cost
        FROM Refund_Items ri JOIN Refunds r ON ri.refund_id = r.refund_id JOIN Products p ON ri.product_id = p.product_id 
        WHERE r.refund_date >= ? AND r.refund_date < ? GROUP BY p.sale_currency
      ) GROUP BY currency
    """, [start, end, start, end]);
  }

  // --- الملاحظات ---
  Future<int> addNote(Map<String, dynamic> row) async {
    int id = await (await database).insert('Notes', row);
    notifyListeners();
    return id;
  }
  Future<List<Map<String, dynamic>>> queryAllNotes() async => (await database).query('Notes', orderBy: 'created_at DESC');
  Future<int> updateNote(Map<String, dynamic> row) async {
    int res = await (await database).update('Notes', row, where: 'note_id = ?', whereArgs: [row['note_id']]);
    notifyListeners();
    return res;
  }
  Future<int> deleteNote(int id) async {
    int res = await (await database).delete('Notes', where: 'note_id = ?', whereArgs: [id]);
    notifyListeners();
    return res;
  }
}
