import 'dart:io';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

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
  } catch (e) {
    print("Sync error: $e");
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pharmacy_master.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 11, onCreate: _createDB, onUpgrade: _onUpgrade);
  }

  Future _onUpgrade(Database db, int oldVer, int newVer) async {
    if (oldVer < 11) {
      try { await db.execute("ALTER TABLE Sales ADD COLUMN edited INTEGER DEFAULT 0"); } catch (_) {}
      try { await db.execute("CREATE TABLE IF NOT EXISTS Refunds (refund_id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER, refund_date TEXT, total_refund REAL, note TEXT)"); } catch (_) {}
      try { await db.execute("CREATE TABLE IF NOT EXISTS Refund_Items (id INTEGER PRIMARY KEY AUTOINCREMENT, refund_id INTEGER, product_id INTEGER, quantity INTEGER, price REAL, purchase_price REAL)"); } catch (_) {}
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''CREATE TABLE Products (product_id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, category TEXT NOT NULL, barcode TEXT UNIQUE, purchase_price REAL, purchase_currency TEXT, sale_price REAL, sale_currency TEXT, quantity INTEGER, expiry_date TEXT, image TEXT, created_at TEXT, uuid TEXT, synced INTEGER DEFAULT 0, updated_at TEXT, deleted INTEGER DEFAULT 0)''');
    await db.execute('''CREATE TABLE Sales (sale_id INTEGER PRIMARY KEY AUTOINCREMENT, sale_date TEXT, total_amount REAL, edited INTEGER DEFAULT 0)''');
    await db.execute('''CREATE TABLE Sale_Items (id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER, product_id INTEGER, quantity INTEGER, price REAL, purchase_price REAL, FOREIGN KEY (sale_id) REFERENCES Sales (sale_id) ON DELETE CASCADE, FOREIGN KEY (product_id) REFERENCES Products (product_id))''');
    await db.execute('''CREATE TABLE Refunds (refund_id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER, refund_date TEXT, total_refund REAL, note TEXT)''');
    await db.execute('''CREATE TABLE Refund_Items (id INTEGER PRIMARY KEY AUTOINCREMENT, refund_id INTEGER, product_id INTEGER, quantity INTEGER, price REAL, purchase_price REAL)''');
    await db.execute('''CREATE TABLE Notes (note_id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, content TEXT, created_at TEXT)''');
  }

  Future<int> addProduct(Map<String, dynamic> row) async {
    final db = await database;
    row['uuid'] = const Uuid().v4();
    return await db.insert('Products', row, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List<Map<String, dynamic>>> queryAllProducts() async => (await database).query('Products', where: 'deleted = 0');
  Future<int> updateProduct(Map<String, dynamic> row) async => (await database).update('Products', row, where: 'product_id = ?', whereArgs: [row['product_id']]);
  Future<int> deleteProduct(int id) async => (await database).update('Products', {'deleted': 1}, where: 'product_id = ?', whereArgs: [id]);

  Future<List<Map<String, dynamic>>> queryStockForExpiration() async => (await database).rawQuery("SELECT p.product_id, p.name AS product_name, p.expiry_date, p.quantity FROM Products p WHERE p.deleted = 0 AND p.quantity > 0 AND p.expiry_date != '' ORDER BY p.expiry_date ASC");
  
  Future<int> getExpirationAlertsCount() async {
    final db = await database;
    final threshold = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 30)));
    final res = await db.rawQuery("SELECT COUNT(*) as count FROM Products WHERE deleted = 0 AND quantity > 0 AND expiry_date != '' AND expiry_date <= ?", [threshold]);
    return Sqflite.firstIntValue(res) ?? 0;
  }

  Future<int> createSale(double total, List<Map<String, dynamic>> items) async {
    final db = await database;
    return await db.transaction((txn) async {
      int id = await txn.insert('Sales', {'sale_date': DateTime.now().toIso8601String(), 'total_amount': total});
      for (var item in items) {
        final p = await txn.query('Products', where: 'product_id = ?', whereArgs: [item['product_id']]);
        double cost = (p.first['purchase_price'] as num?)?.toDouble() ?? 0.0;
        await txn.insert('Sale_Items', {'sale_id': id, 'product_id': item['product_id'], 'quantity': item['quantity'], 'price': item['price'], 'purchase_price': cost});
        await txn.rawUpdate('UPDATE Products SET quantity = quantity - ? WHERE product_id = ?', [item['quantity'], item['product_id']]);
      }
      return id;
    });
  }

  Future<List<Map<String, dynamic>>> getTodayInvoices(DateTime d) async {
    final start = DateTime(d.year, d.month, d.day).toIso8601String();
    final end = DateTime(d.year, d.month, d.day).add(const Duration(days: 1)).toIso8601String();
    return await (await database).rawQuery("SELECT s.*, (SELECT COUNT(*) FROM Sale_Items WHERE sale_id = s.sale_id) as items_count FROM Sales s WHERE sale_date >= ? AND sale_date < ? ORDER BY sale_date DESC", [start, end]);
  }

  Future<List<Map<String, dynamic>>> getInvoiceDetails(int id) async => (await database).rawQuery("SELECT si.*, p.name, p.sale_currency FROM Sale_Items si JOIN Products p ON si.product_id = p.product_id WHERE si.sale_id = ?", [id]);

  Future<void> createRefund(int saleId, List<Map<String, dynamic>> items) async {
    final db = await database;
    await db.transaction((txn) async {
      double total = 0;
      int rId = await txn.insert('Refunds', {'sale_id': saleId, 'refund_date': DateTime.now().toIso8601String(), 'total_refund': 0});
      for (var item in items) {
        total += (item['price'] as num) * (item['quantity'] as num);
        await txn.insert('Refund_Items', {'refund_id': rId, 'product_id': item['product_id'], 'quantity': item['quantity'], 'price': item['price'], 'purchase_price': item['purchase_price']});
        await txn.rawUpdate('UPDATE Products SET quantity = quantity + ? WHERE product_id = ?', [item['quantity'], item['product_id']]);
      }
      await txn.update('Refunds', {'total_refund': total}, where: 'refund_id = ?', whereArgs: [rId]);
    });
  }

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
    return await db.rawQuery("SELECT p.sale_currency as currency, COALESCE(SUM(si.price*si.quantity), 0) as sales, COALESCE(SUM(si.purchase_price*si.quantity), 0) as cost FROM Sale_Items si JOIN Sales s ON si.sale_id = s.sale_id JOIN Products p ON si.product_id = p.product_id WHERE s.sale_date >= ? AND s.sale_date < ? GROUP BY p.sale_currency", [start, end]);
  }

  Future<int> getTotalProductCount() async {
    final db = await database;
    final res = await db.rawQuery('SELECT COUNT(*) FROM Products WHERE deleted = 0');
    return Sqflite.firstIntValue(res) ?? 0;
  }

  Future<int> addNote(Map<String, dynamic> row) async => (await database).insert('Notes', row);
  Future<List<Map<String, dynamic>>> queryAllNotes() async => (await database).query('Notes', orderBy: 'created_at DESC');
  Future<int> updateNote(Map<String, dynamic> row) async => (await database).update('Notes', row, where: 'note_id = ?', whereArgs: [row['note_id']]);
  Future<int> deleteNote(int id) async => (await database).delete('Notes', where: 'note_id = ?', whereArgs: [id]);
}
