import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hps/database/database_helper.dart';
import 'package:hps/models/product.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DatabaseHelper.instance.close();
    await deleteDatabase(path.join(await getDatabasesPath(), 'hps.db'));
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    await deleteDatabase('hps.db');
  });

  Future<int> createInvoice({
    required String date,
    List<Map<String, dynamic>>? items,
  }) async {
    final db = DatabaseHelper.instance;
    await db.insertProduct(Product(
      code: 'P1',
      name: 'کالای یک',
      category: 'عمومی',
      unit: 'عدد',
      initialStock: 20,
      buyPrice: 50,
      sellPrice: 100,
    ));
    await db.insertProduct(Product(
      code: 'P2',
      name: 'کالای دو',
      category: 'عمومی',
      unit: 'عدد',
      initialStock: 20,
      buyPrice: 25,
      sellPrice: 60,
    ));
    return db.insertInvoice(
      date: date,
      discount: 0,
      items: items ?? [
        {'product_code': 'P1', 'product_name': 'کالای یک', 'unit': 'عدد', 'quantity': 2.0, 'unit_price': 100.0},
        {'product_code': 'P2', 'product_name': 'کالای دو', 'unit': 'عدد', 'quantity': 3.0, 'unit_price': 60.0},
      ],
    );
  }

  test('full multi-item return restores stock and cannot be duplicated', () async {
    final db = DatabaseHelper.instance;
    final invoiceId = await createInvoice(date: '1405/08/20');
    final items = await db.getInvoiceItems(invoiceId);

    expect(await db.getCurrentStock('P1'), 18);
    expect(await db.getCurrentStock('P2'), 17);

    await db.returnInvoice(invoiceId, date: '1405/08/20');

    expect(await db.getCurrentStock('P1'), 20);
    expect(await db.getCurrentStock('P2'), 20);
    expect(await db.hasInvoiceReturn(invoiceId), isTrue);
    await expectLater(
      db.returnInvoice(invoiceId, date: '1405/08/20'),
      throwsStateError,
    );
    expect(items.length, 2);
  });

  test('multiple partial returns accumulate per invoice item and reject over-return', () async {
    final db = DatabaseHelper.instance;
    final invoiceId = await createInvoice(date: '1405/08/20');
    final items = await db.getInvoiceItems(invoiceId);
    final firstId = items[0]['id'] as int;
    final secondId = items[1]['id'] as int;

    await db.returnInvoice(
      invoiceId,
      date: '1405/08/20',
      itemQuantities: {firstId: 0.5, secondId: 1.0},
    );
    var remaining = await db.getInvoiceReturnStatus(invoiceId);
    expect(remaining[firstId], 1.5);
    expect(remaining[secondId], 2.0);
    expect(await db.hasInvoiceReturn(invoiceId), isFalse);

    await db.returnInvoice(
      invoiceId,
      date: '1405/08/21',
      itemQuantities: {firstId: 1.5, secondId: 2.0},
    );
    expect(await db.hasInvoiceReturn(invoiceId), isTrue);
    await expectLater(
      db.returnInvoice(
        invoiceId,
        date: '1405/08/22',
        itemQuantities: {firstId: 0.1},
      ),
      throwsStateError,
    );
    expect(await db.getCurrentStock('P1'), 20);
    expect(await db.getCurrentStock('P2'), 20);
  });

  test('same-day and next-month returns use their own transaction dates', () async {
    final db = DatabaseHelper.instance;
    final invoiceId = await createInvoice(
      date: '1405/08/30',
      items: [
        {'product_code': 'P1', 'product_name': 'کالای یک', 'unit': 'عدد', 'quantity': 2.0, 'unit_price': 100.0},
      ],
    );
    final item = (await db.getInvoiceItems(invoiceId)).single;
    final itemId = item['id'] as int;

    await db.returnInvoice(
      invoiceId,
      date: '1405/08/30',
      itemQuantities: {itemId: 1.0},
    );
    final sameDay = await db.getDashboardStats(
      today: '1405/08/30',
      monthStart: '1405/08/01',
    );
    expect(sameDay['sales_today'], 100.0);

    await db.returnInvoice(
      invoiceId,
      date: '1405/09/01',
      itemQuantities: {itemId: 0.5},
    );
    final nextMonth = await db.getDashboardStats(
      today: '1405/09/30',
      monthStart: '1405/09/01',
    );
    expect(nextMonth['sales_month'], -50.0);
    final transactions = await db.getTransactions(type: 'برگشت');
    expect(transactions.map((row) => row.date).toSet(), {'1405/08/30', '1405/09/01'});
  });
}
