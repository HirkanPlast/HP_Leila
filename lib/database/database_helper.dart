import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/product.dart';
import '../models/transaction.dart';
import '../models/expense.dart';
import '../utils/invoice_return_calculator.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('hps.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);
    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        category TEXT,
        unit TEXT NOT NULL,
        initial_stock REAL DEFAULT 0,
        min_stock REAL DEFAULT 0,
        buy_price REAL DEFAULT 0,
        sell_price REAL DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        product_code TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        notes TEXT,
        created_by TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (product_code) REFERENCES products (code)
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        category TEXT NOT NULL,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_trans_date ON transactions(date)');
    await db.execute('CREATE INDEX idx_trans_code ON transactions(product_code)');
    await db.execute('CREATE INDEX idx_trans_type ON transactions(type)');
    await db.execute('CREATE INDEX idx_exp_date ON expenses(date)');
    await _createInvoiceTables(db);
    await _createInvoiceReturnTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _createInvoiceTables(db);
    if (oldVersion < 3) await _createInvoiceReturnTables(db);
  }

  Future<void> _createInvoiceTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT NOT NULL UNIQUE,
        date TEXT NOT NULL,
        customer_name TEXT,
        customer_phone TEXT,
        notes TEXT,
        subtotal REAL NOT NULL,
        discount REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        product_code TEXT NOT NULL,
        product_name TEXT NOT NULL,
        unit TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        line_total REAL NOT NULL,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoice_date ON invoices(date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice ON invoice_items(invoice_id)');
  }


  Future<void> _createInvoiceReturnTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_return_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        invoice_item_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        transaction_id INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE,
        FOREIGN KEY (invoice_item_id) REFERENCES invoice_items (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoice_return_invoice ON invoice_return_items(invoice_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoice_return_item ON invoice_return_items(invoice_item_id)');
  }

  // ========== PRODUCTS ==========

  Future<int> insertProduct(Product product) async {
    final db = await database;
    return await db.insert('products', product.toMap());
  }

  Future<List<Product>> getAllProducts({bool activeOnly = true}) async {
    final db = await database;
    final maps = await db.query(
      'products',
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'code ASC',
    );
    return maps.map((m) => Product.fromMap(m)).toList();
  }

  Future<Product?> getProductByCode(String code) async {
    final db = await database;
    final maps = await db.query(
      'products',
      where: 'code = ?',
      whereArgs: [code],
    );
    if (maps.isEmpty) return null;
    return Product.fromMap(maps.first);
  }

  Future<int> updateProduct(Product product) async {
    final db = await database;
    return await db.update(
      'products',
      product.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<bool> deleteOrArchiveProduct(int id) async {
    final db = await database;
    return db.transaction<bool>((txn) async {
      final rows = await txn.query('products', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return false;
      final code = rows.first['code'] as String;
      final ledger = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM transactions WHERE product_code = ?', [code],
      )) ?? 0;
      final invoiceItems = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM invoice_items WHERE product_code = ?', [code],
      )) ?? 0;
      final initialStock = (rows.first['initial_stock'] as num?)?.toDouble() ?? 0;
      if (ledger > 0 || invoiceItems > 0 || initialStock != 0) {
        await txn.update('products', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
        return true;
      }
      await txn.delete('products', where: 'id = ?', whereArgs: [id]);
      return false;
    });
  }

  // ========== TRANSACTIONS ==========

  Future<int> insertTransaction(InventoryTransaction t) async {
    final db = await database;
    return await db.insert('transactions', t.toMap());
  }

  Future<List<InventoryTransaction>> getTransactions({
    String? fromDate,
    String? toDate,
    String? type,
    String? productCode,
    int limit = 500,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <dynamic>[];

    if (fromDate != null) {
      where.add('date >= ?');
      args.add(fromDate);
    }
    if (toDate != null) {
      where.add('date <= ?');
      args.add(toDate);
    }
    if (type != null) {
      where.add('type = ?');
      args.add(type);
    }
    if (productCode != null) {
      where.add('product_code = ?');
      args.add(productCode);
    }

    final maps = await db.rawQuery('''
      SELECT t.*, p.name as product_name, p.unit
      FROM transactions t
      LEFT JOIN products p ON t.product_code = p.code
      ${where.isNotEmpty ? 'WHERE ${where.join(' AND ')}' : ''}
      ORDER BY t.date DESC, t.id DESC
      LIMIT $limit
    ''', args);

    return maps.map((m) => InventoryTransaction.fromMap(m)).toList();
  }

  Future<int> deleteTransaction(int id) async {
    final db = await database;
    final rows = await db.query('transactions', columns: ['created_by'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isNotEmpty && ['invoice', 'invoice_return'].contains(rows.first['created_by'])) {
      throw StateError('این ردیف متعلق به فاکتور است؛ حذف مستقیم آن مجاز نیست.');
    }
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  // ========== SALES INVOICES ==========

  Future<List<Map<String, dynamic>>> getInvoices({int limit = 500}) async {
    final db = await database;
    return db.query('invoices', orderBy: 'id DESC', limit: limit);
  }

  Future<Map<String, dynamic>?> getInvoice(int id) async {
    final db = await database;
    final rows = await db.query('invoices', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> getInvoiceItems(int invoiceId) async {
    final db = await database;
    return db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId], orderBy: 'id ASC');
  }

  /// Saves an invoice, its items, and matching stock-sale transactions atomically.
  /// Existing sales reports receive net line values after invoice discount allocation.
  Future<int> insertInvoice({
    required String date,
    String? customerName,
    String? customerPhone,
    String? notes,
    required double discount,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) throw ArgumentError('فاکتور باید حداقل یک کالا داشته باشد.');
    final normalized = items.map((item) {
      final quantity = (item['quantity'] as num).toDouble();
      final unitPrice = (item['unit_price'] as num).toDouble();
      if (quantity <= 0 || unitPrice < 0) throw ArgumentError('تعداد و قیمت کالا معتبر نیست.');
      return <String, dynamic>{
        'product_code': item['product_code'] as String,
        'product_name': item['product_name'] as String,
        'unit': item['unit'] as String,
        'quantity': quantity,
        'unit_price': unitPrice,
        'line_total': quantity * unitPrice,
      };
    }).toList();
    final subtotal = normalized.fold<double>(0, (sum, item) => sum + (item['line_total'] as double));
    if (discount < 0 || discount > subtotal) throw ArgumentError('تخفیف باید بین صفر و جمع فاکتور باشد.');

    final db = await database;
    return db.transaction<int>((txn) async {
      final now = DateTime.now().toIso8601String();
      final nextId = Sqflite.firstIntValue(await txn.rawQuery('SELECT COALESCE(MAX(id), 0) + 1 FROM invoices')) ?? 1;
      final invoiceNumber = 'HP-${date.replaceAll('/', '')}-${nextId.toString().padLeft(4, '0')}';
      final invoiceId = await txn.insert('invoices', {
        'invoice_number': invoiceNumber,
        'date': date,
        'customer_name': (customerName ?? '').trim().isEmpty ? null : customerName!.trim(),
        'customer_phone': (customerPhone ?? '').trim().isEmpty ? null : customerPhone!.trim(),
        'notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
        'subtotal': subtotal,
        'discount': discount,
        'total': subtotal - discount,
        'created_at': now,
      });
      for (final item in normalized) {
        final gross = item['line_total'] as double;
        final allocatedDiscount = subtotal == 0 ? 0.0 : discount * gross / subtotal;
        final netLine = gross - allocatedDiscount;
        final quantity = item['quantity'] as double;
        await txn.insert('invoice_items', {'invoice_id': invoiceId, ...item});
        await txn.insert('transactions', {
          'date': date,
          'type': 'فروش',
          'product_code': item['product_code'],
          'quantity': quantity,
          'unit_price': quantity == 0 ? 0.0 : netLine / quantity,
          'notes': 'فاکتور $invoiceNumber',
          'created_by': 'invoice',
          'created_at': now,
        });
      }
      return invoiceId;
    });
  }

  /// Remaining quantity by invoice-item id. Legacy full-return records are
  /// recognized so upgrading an existing installation never re-opens a returned invoice.
  Future<Map<int, double>> getInvoiceReturnStatus(int invoiceId) async {
    final db = await database;
    final invoiceRows = await db.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    if (invoiceRows.isEmpty) return {};
    final invoiceNumber = invoiceRows.first['invoice_number'] as String;
    final legacy = await db.query(
      'transactions', columns: ['id'],
      where: "created_by = ? AND notes = ?",
      whereArgs: ['invoice_return', 'برگشت کامل فاکتور $invoiceNumber'], limit: 1,
    );
    final items = await db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
    final result = <int, double>{};
    for (final item in items) {
      final itemId = item['id'] as int;
      final quantity = (item['quantity'] as num).toDouble();
      if (legacy.isNotEmpty) {
        result[itemId] = 0;
        continue;
      }
      final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(quantity), 0) AS returned FROM invoice_return_items WHERE invoice_item_id = ?',
        [itemId],
      );
      final returned = (rows.first['returned'] as num).toDouble();
      result[itemId] = (quantity - returned).clamp(0.0, quantity).toDouble();
    }
    return result;
  }

  Future<bool> hasInvoiceReturn(int invoiceId) async {
    final remaining = await getInvoiceReturnStatus(invoiceId);
    return remaining.isNotEmpty && remaining.values.every((value) => value <= 0.0000001);
  }

  /// Atomically records full or partial quantities. Keys are invoice_item ids.
  /// Omitted itemQuantities means return every remaining item quantity.
  Future<void> returnInvoice(
    int invoiceId, {
    required String date,
    Map<int, double>? itemQuantities,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final invoiceRows = await txn.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
      if (invoiceRows.isEmpty) throw StateError('فاکتور پیدا نشد.');
      final invoiceNumber = invoiceRows.first['invoice_number'] as String;
      final legacyNote = 'برگشت کامل فاکتور $invoiceNumber';
      final legacy = await txn.query(
        'transactions', columns: ['id'],
        where: "created_by = ? AND notes = ?",
        whereArgs: ['invoice_return', legacyNote], limit: 1,
      );
      if (legacy.isNotEmpty) throw StateError('تمام اقلام این فاکتور قبلاً برگشت شده‌اند.');
      final items = await txn.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId], orderBy: 'id ASC');
      if (items.isEmpty) throw StateError('اقلام فاکتور پیدا نشدند.');
      final now = DateTime.now().toIso8601String();
      var inserted = 0;
      for (final item in items) {
        final itemId = item['id'] as int;
        final originalQuantity = (item['quantity'] as num).toDouble();
        final returnedRows = await txn.rawQuery(
          'SELECT COALESCE(SUM(quantity), 0) AS returned FROM invoice_return_items WHERE invoice_item_id = ?',
          [itemId],
        );
        final alreadyReturned = (returnedRows.first['returned'] as num).toDouble();
        final remaining = InvoiceReturnCalculator.remaining(
          sold: originalQuantity,
          returned: alreadyReturned,
        );
        final requested = itemQuantities == null
            ? remaining
            : (itemQuantities[itemId] ?? 0.0);
        if (requested == 0) continue;
        final validatedQuantity = InvoiceReturnCalculator.validateRequest(
          sold: originalQuantity,
          returned: alreadyReturned,
          requested: requested,
        );
        final lineTotal = (item['line_total'] as num).toDouble();
        final netUnitPrice = originalQuantity == 0 ? 0.0 : lineTotal / originalQuantity;
        final returnNote = 'برگشت فاکتور $invoiceNumber - قلم $itemId';
        final transactionId = await txn.insert('transactions', {
          'date': date,
          'type': 'برگشت',
          'product_code': item['product_code'],
          'quantity': validatedQuantity,
          'unit_price': netUnitPrice,
          'notes': returnNote,
          'created_by': 'invoice_return',
          'created_at': now,
        });
        await txn.insert('invoice_return_items', {
          'invoice_id': invoiceId,
          'invoice_item_id': itemId,
          'date': date,
          'quantity': requested,
          'unit_price': netUnitPrice,
          'transaction_id': transactionId,
          'created_at': now,
        });
        inserted++;
      }
      if (inserted == 0) throw StateError('مقدار برگشت را برای حداقل یک قلم وارد کنید.');
    });
  }

  // ========== STOCK CALCULATION ==========

  /// Current stock for a product = initial + sum of stock deltas
  Future<double> getCurrentStock(String productCode) async {
    final db = await database;
    final product = await getProductByCode(productCode);
    if (product == null) return 0;

    final result = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(
          CASE 
            WHEN type = 'ورود' THEN quantity
            WHEN type = 'برگشت' THEN quantity
            WHEN type = 'فروش' THEN -quantity
            WHEN type = 'تعدیل' THEN quantity
            ELSE 0
          END
        ), 0) as delta
      FROM transactions
      WHERE product_code = ?
    ''', [productCode]);

    final delta = (result.first['delta'] as num?)?.toDouble() ?? 0;
    return product.initialStock + delta;
  }

  /// Full inventory list with current stock and status
  Future<List<Map<String, dynamic>>> getInventory() async {
    final products = await getAllProducts(activeOnly: true);
    final list = <Map<String, dynamic>>[];

    for (final p in products) {
      final current = await getCurrentStock(p.code);
      String status;
      if (current <= 0) {
        status = 'بدون موجودی';
      } else if (current < p.minStock) {
        status = 'کمبود';
      } else {
        status = 'تأمین';
      }

      list.add({
        'product': p,
        'current_stock': current,
        'status': status,
        'stock_value_buy': current * p.buyPrice,
        'stock_value_sell': current * p.sellPrice,
      });
    }
    return list;
  }

  // ========== EXPENSES ==========

  Future<int> insertExpense(Expense e) async {
    final db = await database;
    return await db.insert('expenses', e.toMap());
  }

  Future<List<Expense>> getExpenses({
    String? fromDate,
    String? toDate,
    String? category,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <dynamic>[];

    if (fromDate != null) {
      where.add('date >= ?');
      args.add(fromDate);
    }
    if (toDate != null) {
      where.add('date <= ?');
      args.add(toDate);
    }
    if (category != null) {
      where.add('category = ?');
      args.add(category);
    }

    final maps = await db.query(
      'expenses',
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'date DESC, id DESC',
    );
    return maps.map((m) => Expense.fromMap(m)).toList();
  }

  Future<int> deleteExpense(int id) async {
    final db = await database;
    return await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  // ========== DASHBOARD STATS ==========

  Future<Map<String, dynamic>> getDashboardStats({
    required String today,
    required String monthStart,
  }) async {
    final db = await database;

    // Sales today
    final salesToday = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN type = 'فروش' THEN quantity * unit_price WHEN type = 'برگشت' THEN -quantity * unit_price ELSE 0 END), 0) as total,
             COALESCE(SUM(CASE WHEN type = 'فروش' THEN quantity WHEN type = 'برگشت' THEN -quantity ELSE 0 END), 0) as qty
      FROM transactions
      WHERE type IN ('فروش', 'برگشت') AND date = ?
    ''', [today]);

    // Sales this month
    final salesMonth = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN type = 'فروش' THEN quantity * unit_price WHEN type = 'برگشت' THEN -quantity * unit_price ELSE 0 END), 0) as total,
             COALESCE(SUM(CASE WHEN type = 'فروش' THEN quantity WHEN type = 'برگشت' THEN -quantity ELSE 0 END), 0) as qty
      FROM transactions
      WHERE type IN ('فروش', 'برگشت') AND date >= ? AND date <= ?
    ''', [monthStart, today]);

    // Expenses this month
    final expMonth = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as total
      FROM expenses
      WHERE date >= ? AND date <= ?
    ''', [monthStart, today]);

    // Inventory summary
    final inventory = await getInventory();
    double stockValueBuy = 0;
    double stockValueSell = 0;
    int lowStock = 0;
    int outOfStock = 0;
    int okStock = 0;

    for (final item in inventory) {
      stockValueBuy += item['stock_value_buy'] as double;
      stockValueSell += item['stock_value_sell'] as double;
      final status = item['status'] as String;
      if (status == 'بدون موجودی') outOfStock++;
      else if (status == 'کمبود') lowStock++;
      else okStock++;
    }

    // COGS approximation this month (using current buy price)
    // Better would be FIFO, but for v1 we use average
    final cogsMonth = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN t.type = 'فروش' THEN t.quantity * p.buy_price WHEN t.type = 'برگشت' THEN -t.quantity * p.buy_price ELSE 0 END), 0) as total
      FROM transactions t
      JOIN products p ON t.product_code = p.code
      WHERE t.type IN ('فروش', 'برگشت') AND t.date >= ? AND t.date <= ?
    ''', [monthStart, today]);

    final salesTotal = (salesMonth.first['total'] as num).toDouble();
    final cogs = (cogsMonth.first['total'] as num).toDouble();
    final expenses = (expMonth.first['total'] as num).toDouble();
    final grossProfit = salesTotal - cogs;
    final netProfit = grossProfit - expenses;

    return {
      'sales_today': (salesToday.first['total'] as num).toDouble(),
      'sales_today_qty': (salesToday.first['qty'] as num).toDouble(),
      'sales_month': salesTotal,
      'sales_month_qty': (salesMonth.first['qty'] as num).toDouble(),
      'expenses_month': expenses,
      'gross_profit_month': grossProfit,
      'net_profit_month': netProfit,
      'stock_value_buy': stockValueBuy,
      'stock_value_sell': stockValueSell,
      'products_ok': okStock,
      'products_low': lowStock,
      'products_out': outOfStock,
      'total_products': inventory.length,
    };
  }


  /// Replace ledger records while preserving the existing product catalogue.
  Future<void> importOperationalData({
    required List<Map<String, dynamic>> transactions,
    required List<Map<String, dynamic>> expenses,
    bool resetInitialStock = false,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final products = await txn.query('products', columns: ['code']);
      final codes = products.map((p) => p['code'] as String).toSet();
      for (final t in transactions) {
        final code = t['product_code'] as String;
        if (!codes.contains(code)) {
          throw Exception('کد کالای ناموجود: $code');
        }
      }
      await txn.delete('invoice_return_items');
      await txn.delete('invoice_items');
      await txn.delete('invoices');
      await txn.delete('transactions');
      await txn.delete('expenses');
      if (resetInitialStock) {
        // A full ledger import already contains stock movements; do not add seeded opening stock again.
        await txn.update('products', {'initial_stock': 0});
      }
      for (final t in transactions) {
        await txn.insert('transactions', t);
      }
      for (final e in expenses) {
        await txn.insert('expenses', e);
      }
    });
  }

  // ========== BACKUP / RESTORE ==========

  Future<Map<String, dynamic>> exportAllData() async {
    final products = await getAllProducts(activeOnly: false);
    final transactions = await getTransactions(limit: 100000);
    final expenses = await getExpenses();
    final invoiceRows = await getInvoices(limit: 100000);
    final db = await database;
    final returnItems = await db.query('invoice_return_items');
    final invoices = <Map<String, dynamic>>[];
    for (final invoice in invoiceRows) {
      final record = Map<String, dynamic>.from(invoice);
      record['items'] = await getInvoiceItems(invoice['id'] as int);
      invoices.add(record);
    }

    return {
      'version': '1.1.0',
      'exported_at': DateTime.now().toIso8601String(),
      'products': products.map((p) => p.toMap()).toList(),
      'transactions': transactions.map((t) => t.toMap()).toList(),
      'expenses': expenses.map((e) => e.toMap()).toList(),
      'invoices': invoices,
      'invoice_return_items': returnItems,
    };
  }

  /// Restores old backups too; invoice data is optional for backward compatibility.
  Future<void> importAllData(Map<String, dynamic> data, {bool clearFirst = true}) async {
    final db = await database;
    await db.transaction((txn) async {
      if (clearFirst) {
        await txn.delete('invoice_return_items');
        await txn.delete('invoice_items');
        await txn.delete('invoices');
        await txn.delete('transactions');
        await txn.delete('expenses');
        await txn.delete('products');
      }

      final products = data['products'] as List? ?? [];
      for (final p in products) {
        final map = Map<String, dynamic>.from(p)..remove('id');
        map['is_active'] = map['is_active'] ?? 1;
        await txn.insert('products', map, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final transactions = data['transactions'] as List? ?? [];
      for (final t in transactions) {
        final map = Map<String, dynamic>.from(t)..remove('id');
        await txn.insert('transactions', map);
      }

      final expenses = data['expenses'] as List? ?? [];
      for (final e in expenses) {
        final map = Map<String, dynamic>.from(e)..remove('id');
        await txn.insert('expenses', map);
      }

      final invoiceIdMap = <int, int>{};
      final invoiceItemIdMap = <int, int>{};
      final invoices = data['invoices'] as List? ?? [];
      for (final invoiceData in invoices) {
        final invoice = Map<String, dynamic>.from(invoiceData);
        final items = invoice['items'] as List? ?? [];
        invoice.remove('items');
        final oldInvoiceId = invoice.remove('id') as int?;
        final invoiceId = await txn.insert('invoices', invoice, conflictAlgorithm: ConflictAlgorithm.replace);
        if (oldInvoiceId != null) invoiceIdMap[oldInvoiceId] = invoiceId;
        for (final itemData in items) {
          final item = Map<String, dynamic>.from(itemData);
          final oldItemId = item.remove('id') as int?;
          item.remove('invoice_id');
          item['invoice_id'] = invoiceId;
          final newItemId = await txn.insert('invoice_items', item);
          if (oldItemId != null) invoiceItemIdMap[oldItemId] = newItemId;
        }
      }
      final savedReturns = data['invoice_return_items'] as List? ?? [];
      for (final returnData in savedReturns) {
        final record = Map<String, dynamic>.from(returnData);
        final oldInvoiceId = record.remove('invoice_id') as int?;
        final oldItemId = record.remove('invoice_item_id') as int?;
        record.remove('id');
        record.remove('transaction_id');
        final newInvoiceId = oldInvoiceId == null ? null : invoiceIdMap[oldInvoiceId];
        final newItemId = oldItemId == null ? null : invoiceItemIdMap[oldItemId];
        if (newInvoiceId == null || newItemId == null) continue;
        record['invoice_id'] = newInvoiceId;
        record['invoice_item_id'] = newItemId;
        record['transaction_id'] = null;
        await txn.insert('invoice_return_items', record);
      }
    });
  }

  /// Seed only products from the built-in seed_products.json (or provided list)
  Future<int> seedProducts(List<Map<String, dynamic>> products, {bool clearExisting = false}) async {
    final db = await database;
    int count = 0;
    await db.transaction((txn) async {
      if (clearExisting) {
        await txn.delete('products');
      }
      for (final p in products) {
        final map = Map<String, dynamic>.from(p)..remove('id');
        map['is_active'] = map['is_active'] ?? 1;
        try {
          await txn.insert('products', map, conflictAlgorithm: ConflictAlgorithm.ignore);
          count++;
        } catch (_) {
          // skip duplicates
        }
      }
    });
    return count;
  }

  /// Check if products table is empty
  Future<bool> isProductsEmpty() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM products');
    return ((result.first['c'] as int?) ?? 0) == 0;
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
