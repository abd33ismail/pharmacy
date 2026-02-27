import 'dart:io';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

// Helper function for the Add Medicine Page
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
  print("--- Sending Data to Server ---");
  print("Name: $name, Price: $saleprice, Quantity: $quantity, Barcode: $barcode, Expiry Date: $expiryDate");
  if (name.isEmpty || saleprice.isEmpty || quantity.isEmpty || barcode.isEmpty || expiryDate.isEmpty) {
    print("Error: One of the fields is empty. Request not sent.");
    return;
  }
  var url = Uri.parse("http://10.0.2.2/pharmacy_api/add_medicine.php");
  var response = await http.post(url, body: {
    "name": name,
    "sale_price": saleprice.toString(),
    "purchase_price": purchasePrice.toString(),
    "quantity": quantity.toString(),
    "barcode": barcode,
    "expiry_date": expiryDate,
    "currency": currency,
    "category": category,
    "purchase_currency": purchaseCurrency.toUpperCase(),

  });
  print("Server Response: ${response.body}");
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
    return await openDatabase(path, version: 6, onCreate: _createDB, onUpgrade: _onUpgrade);
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 5) {
      try {
        var tableInfo = await db.rawQuery('PRAGMA table_info(Sale_Items)');
        if (!tableInfo.any((c) => c['name'] == 'purchase_price')) {
          await db.execute("ALTER TABLE Sale_Items ADD COLUMN purchase_price REAL");
        }
      } catch (e) {
        print("Error upgrading database to v5: $e");
      }
    }
    if (oldVersion < 6) {
      try {
        await db.execute("ALTER TABLE Products ADD COLUMN uuid TEXT");
        await db.execute("ALTER TABLE Products ADD COLUMN synced INTEGER DEFAULT 0");
        await db.execute("ALTER TABLE Products ADD COLUMN updated_at TEXT");
        await db.execute("ALTER TABLE Products ADD COLUMN deleted INTEGER DEFAULT 0");
      } catch (e) {
        print("Error upgrading database to v6: $e");
      }
    }
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const integerType = 'INTEGER NOT NULL';
    const realType = 'REAL';

    await db.execute('''
      CREATE TABLE Products (
        product_id $idType, name $textType, category $textType, barcode TEXT,
        purchase_price $realType, purchase_currency TEXT, sale_price $realType, sale_currency TEXT,
        quantity $integerType, expiry_date TEXT, image TEXT, created_at $textType,
        uuid TEXT, synced INTEGER DEFAULT 0, updated_at TEXT, deleted INTEGER DEFAULT 0
      )
    ''');
    await db.execute("CREATE INDEX idx_product_name ON Products(name)");
    await db.execute("CREATE INDEX idx_barcode ON Products(barcode)");
    await db.execute("CREATE INDEX idx_expiry ON Products(expiry_date)");

    await db.execute('''
      CREATE TABLE Sales (sale_id $idType, sale_date $textType, total_amount $realType)
    ''');

    await db.execute('''
      CREATE TABLE Sale_Items (
        id $idType, sale_id $integerType, product_id $integerType, quantity $integerType,
        price $realType, purchase_price $realType,
        FOREIGN KEY (sale_id) REFERENCES Sales (sale_id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES Products (product_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE Stock_In (
        stock_in_id $idType, product_id $integerType, quantity $integerType, unit_cost $realType,
        supplier TEXT, batch_number TEXT, expiry_date TEXT, in_date $textType, note TEXT,
        FOREIGN KEY (product_id) REFERENCES Products (product_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE Stock_Out (
        stock_out_id $idType, product_id $integerType, quantity $integerType, out_type $textType,
        sale_id INTEGER, out_date $textType, note TEXT,
        FOREIGN KEY (product_id) REFERENCES Products (product_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE Suppliers (supplier_id $idType, name $textType, phone TEXT, note TEXT)
    ''');

    await db.execute('''
      CREATE TABLE Notes (note_id $idType, title TEXT, content TEXT, created_at $textType)
    ''');
  }

  // === CRUD Products (with Sync Logic) ===
  Future<int> addProduct(Map<String, dynamic> row) async {
    final db = await instance.database;
    row['uuid'] = Uuid().v4();
    row['synced'] = 0;
    row['updated_at'] = DateTime.now().toIso8601String();
    row['deleted'] = 0;
    return db.insert('Products', row);
  }

  Future<List<Map<String, dynamic>>> queryAllProducts() async {
    final db = await instance.database;
    return db.query('Products', where: 'deleted = 0');
  }

  Future<int> updateProduct(Map<String, dynamic> row) async {
    final db = await instance.database;
    row['synced'] = 0;
    row['updated_at'] = DateTime.now().toIso8601String();
    return db.update('Products', row, where: 'product_id = ?', whereArgs: [row['product_id']]);
  }

  Future<int> deleteProduct(int id) async {
    final db = await instance.database;
    return db.update('Products', {'deleted': 1, 'synced': 0, 'updated_at': DateTime.now().toIso8601String()}, where: 'product_id = ?', whereArgs: [id]);
  }

  // === Sync ===
  Future<void> syncProducts() async {
    final db = await instance.database;
    final unsynced = await db.query('Products', where: 'synced = 0');
    for (var product in unsynced) {
      try {
        final response = await http.post(
          Uri.parse("http://YOUR_SERVER_IP/pharmacy_api/sync_product.php"),
          body: product.map((key, value) => MapEntry(key, value.toString())),
        );
        if (response.statusCode == 200) {
          await db.update('Products', {'synced': 1}, where: 'product_id = ?', whereArgs: [product['product_id']]);
        }
      } catch (e) {
        print("Sync failed for product ${product['product_id']}: $e");
      }
    }
  }

  // === Expiration & Stock ===
  Future<List<Map<String, dynamic>>> queryStockForExpiration() async {
    final db = await database;
    return await db.rawQuery('''
    SELECT 
      p.product_id,
      p.name AS product_name,
      s.batch_number,
      COALESCE(s.expiry_date, p.expiry_date) AS expiry_date,
      COALESCE(s.quantity, p.quantity) AS quantity
    FROM Products p
    LEFT JOIN Stock_In s ON p.product_id = s.product_id
    WHERE p.deleted = 0
      AND COALESCE(s.quantity, p.quantity) > 0
      AND COALESCE(s.expiry_date, p.expiry_date) IS NOT NULL
      AND COALESCE(s.expiry_date, p.expiry_date) != ''
    ORDER BY COALESCE(s.expiry_date, p.expiry_date) ASC
  ''');
  }

  Future<int> getExpirationAlertsCount() async {
    final db = await database;
    final threshold = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 30)));
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM Products
      WHERE deleted = 0 AND quantity > 0 AND expiry_date IS NOT NULL AND expiry_date != '' AND date(expiry_date) <= date(?)
    ''', [threshold]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // === Sales & Reports ===
  Future<int> createSale(double total, List<Map<String, dynamic>> items) async {
    final db = await instance.database;
    return await db.transaction((txn) async {
      int id = await txn.insert('Sales', {'sale_date': DateTime.now().toIso8601String(), 'total_amount': total});
      for (var item in items) {
        final productDetails = await txn.query('Products', where: 'product_id = ? AND deleted = 0', whereArgs: [item['product_id']]);
        final purchasePrice = (productDetails.first['purchase_price'] as num?)?.toDouble() ?? 0.0;
        await txn.insert('Sale_Items', {'sale_id': id, 'product_id': item['product_id'], 'quantity': item['quantity'], 'price': item['price'], 'purchase_price': purchasePrice});
        await txn.rawUpdate('UPDATE Products SET quantity = quantity - ? WHERE product_id = ?', [item['quantity'], item['product_id']]);
      }
      return id;
    });
  }

  Future<Map<String, double>> getDailyProfitStats(DateTime date) async {
    final db = await database;
    final day = DateFormat('yyyy-MM-dd').format(date);
    final result = await db.rawQuery('''
      SELECT SUM(si.price * si.quantity) AS total_sales, SUM(si.purchase_price * si.quantity) AS total_cost
      FROM Sale_Items si JOIN Sales s ON si.sale_id = s.sale_id
      WHERE DATE(s.sale_date) = ?
    ''', [day]);
    final sales = (result.first['total_sales'] as num?)?.toDouble() ?? 0.0;
    final cost = (result.first['total_cost'] as num?)?.toDouble() ?? 0.0;
    return {'sales': sales, 'cost': cost, 'profit': sales - cost, 'profit_percent': sales > 0 ? ((sales - cost) / sales) * 100 : 0.0};
  }

  Future<Map<String, double>> getMonthlyProfitStats(int year, int month) async {
    final db = await database;
    final datePrefix = '$year-${month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery('''
      SELECT SUM(si.price * si.quantity) AS total_sales, SUM(si.purchase_price * si.quantity) AS total_cost
      FROM Sale_Items si JOIN Sales s ON si.sale_id = s.sale_id
      WHERE strftime('%Y-%m', s.sale_date) = ?
    ''', [datePrefix]);
    final sales = (result.first['total_sales'] as num?)?.toDouble() ?? 0.0;
    final cost = (result.first['total_cost'] as num?)?.toDouble() ?? 0.0;
    return {'sales': sales, 'cost': cost, 'profit': sales - cost, 'profit_percent': sales > 0 ? ((sales - cost) / sales) * 100 : 0.0};
  }

  Future<List<Map<String, dynamic>>> getDailyReportsByCurrency(DateTime date) async {
    final db = await database;
    final day = DateFormat('yyyy-MM-dd').format(date);
    final result = await db.rawQuery('''
      SELECT p.sale_currency, SUM(si.price * si.quantity) AS total_sales, SUM(si.purchase_price * si.quantity) AS total_cost
      FROM Sale_Items si JOIN Sales s ON si.sale_id = s.sale_id JOIN Products p ON si.product_id = p.product_id
      WHERE DATE(s.sale_date) = ? AND p.deleted = 0
      GROUP BY p.sale_currency
    ''', [day]);
    return result.map((row) {
      final sales = (row['total_sales'] as num?)?.toDouble() ?? 0.0;
      final cost = (row['total_cost'] as num?)?.toDouble() ?? 0.0;
      return {'currency': row['sale_currency'] ?? 'N/A', 'sales': sales, 'cost': cost, 'profit': sales - cost};
    }).toList();
  }

  // === Stats ===
  Future<int> getTotalProductCount() async {
    final db = await database;
    final res = await db.rawQuery('SELECT COUNT(*) as count FROM Products WHERE deleted = 0');
    return Sqflite.firstIntValue(res) ?? 0;
  }

  // === Notes ===
  Future<int> addNote(Map<String, dynamic> row) async => (await database).insert('Notes', row);
  Future<List<Map<String, dynamic>>> queryAllNotes() async => (await database).query('Notes', orderBy: 'created_at DESC');
  Future<int> updateNote(Map<String, dynamic> row) async => (await database).update('Notes', row, where: 'note_id = ?', whereArgs: [row['note_id']]);
  Future<int> deleteNote(int id) async => (await database).delete('Notes', where: 'note_id = ?', whereArgs: [id]);

  // === Backup ===
  Future<String> backupDatabase() async {
    final dbPath = await getDatabasesPath();
    final dbFile = File(join(dbPath, 'pharmacy_master.db'));
    final directory = await getExternalStorageDirectory();
    if (directory == null) return "Error: Storage not found";
    final backupFile = File(join(directory.path, 'pharmacy_backup.db'));
    await dbFile.copy(backupFile.path);
    return "Backup saved to: ${backupFile.path}";
  }
}
