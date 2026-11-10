import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../database/database_helper.dart';
import '../models/product.dart';
import '../utils/number_format.dart';
import '../utils/persian_date.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});
  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  List<Map<String, dynamic>> _invoices = [];
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  List<Map<String, dynamic>> get _filteredInvoices {
    final query = _searchCtrl.text.trim().toLowerCase().replaceAll(',', '');
    if (query.isEmpty) return _invoices;
    return _invoices.where((invoice) {
      final haystack = '${invoice['invoice_number']} ${invoice['customer_name'] ?? ''} ${invoice['customer_phone'] ?? ''} ${invoice['date']} ${invoice['total']}'.toLowerCase().replaceAll(',', '');
      return haystack.contains(query);
    }).toList();
  }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await DatabaseHelper.instance.getInvoices();
    if (!mounted) return;
    setState(() { _invoices = rows; _loading = false; });
  }
  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateInvoiceScreen()),
    );
    if (created == true) _load();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('فاکتورهای فروش')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create, icon: const Icon(Icons.add), label: const Text('فاکتور جدید'),
    ),
    body: _loading
      ? const Center(child: CircularProgressIndicator())
      : Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'جست‌وجوی شماره، مشتری یا تاریخ فاکتور',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isEmpty ? null : IconButton(
                  tooltip: 'پاک‌کردن جست‌وجو', icon: const Icon(Icons.close),
                  onPressed: () { _searchCtrl.clear(); setState(() {}); },
                ),
              ),
            ),
          ),
          Expanded(child: _filteredInvoices.isEmpty
            ? Center(child: Text(_invoices.isEmpty ? 'هنوز فاکتوری ثبت نشده است' : 'فاکتوری با این مشخصات پیدا نشد'))
            : RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 88, top: 8),
            itemCount: _filteredInvoices.length,
            itemBuilder: (context, index) {
              final invoice = _filteredInvoices[index];
              final customer = (invoice['customer_name'] as String?)?.trim();
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                  title: Text('${invoice['invoice_number']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${invoice['date']} • ${customer == null || customer.isEmpty ? 'مشتری آزاد' : customer}'),
                  trailing: Text('${NumberFormatHelper.integer((invoice['total'] as num).toDouble())} ریال',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
                    builder: (_) => InvoiceDetailScreen(invoiceId: invoice['id'] as int),
                  )),
                ),
              );
            },
          ),
        )),
      ]),
  );
}

class _InvoiceLine {
  final Product product;
  final double quantity;
  final double unitPrice;
  const _InvoiceLine({required this.product, required this.quantity, required this.unitPrice});
  double get total => quantity * unitPrice;
}

class CreateInvoiceScreen extends StatefulWidget {
  const CreateInvoiceScreen({super.key});
  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> {
  final _customerCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  List<Product> _products = [];
  Product? _selectedProduct;
  final List<_InvoiceLine> _lines = [];
  bool _loading = true;
  bool _saving = false;
  final String _date = PersianDateHelper.today();
  double get _subtotal => _lines.fold<double>(0, (sum, line) => sum + line.total);
  double get _discount => double.tryParse(_discountCtrl.text.replaceAll(',', '').trim()) ?? 0;
  double get _total => _subtotal - _discount;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _discountCtrl.addListener(() { if (mounted) setState(() {}); });
  }
  @override
  void dispose() {
    _customerCtrl.dispose(); _phoneCtrl.dispose(); _notesCtrl.dispose();
    _quantityCtrl.dispose(); _discountCtrl.dispose();
    super.dispose();
  }
  Future<void> _loadProducts() async {
    final products = await DatabaseHelper.instance.getAllProducts();
    if (!mounted) return;
    setState(() {
      _products = products;
      _selectedProduct = null;
      _loading = false;
    });
  }
  String _normalizeProductSearch(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll('ۀ', 'ه')
      .replaceAll('ة', 'ه');

  Future<void> _chooseProduct() async {
    final searchController = TextEditingController();
    final selected = await showDialog<Product>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = _normalizeProductSearch(searchController.text);
          final matches = _products.where((product) {
            final searchable = _normalizeProductSearch('${product.code} ${product.name}');
            return query.isEmpty || searchable.contains(query);
          }).toList();

          return AlertDialog(
            title: const Text('جست‌وجو و انتخاب کالا'),
            content: SizedBox(
              width: double.maxFinite,
              height: 380,
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    autofocus: true,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'نام یا کد کالا را تایپ کنید',
                      prefixIcon: Icon(Icons.search),
                      suffixIcon: Icon(Icons.keyboard),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: matches.isEmpty
                        ? const Center(child: Text('کالایی با این نام یا کد پیدا نشد'))
                        : ListView.separated(
                            itemCount: matches.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final product = matches[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(product.name),
                                subtitle: Text('${product.code} • ${product.unit}'),
                                onTap: () => Navigator.of(dialogContext).pop(product),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('انصراف'),
              ),
            ],
          );
        },
      ),
    );
    searchController.dispose();
    if (selected != null && mounted) {
      setState(() => _selectedProduct = selected);
    }
  }

  void _addLine() {
    final product = _selectedProduct;
    final quantity = double.tryParse(_quantityCtrl.text.replaceAll(',', '').trim()) ?? 0;
    final price = product?.sellPrice ?? -1;
    if (product == null || quantity <= 0 || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('کالا، تعداد و قیمت معتبر را وارد کنید')));
      return;
    }
    setState(() {
      _lines.add(_InvoiceLine(product: product, quantity: quantity, unitPrice: price));
      _quantityCtrl.clear();
    });
  }
  Future<void> _save() async {
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حداقل یک کالا به فاکتور اضافه کنید')));
      return;
    }
    if (_discount < 0 || _discount > _subtotal) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تخفیف نباید از جمع کالاها بیشتر باشد')));
      return;
    }
    setState(() => _saving = true);
    try {
      for (final line in _lines) {
        final current = await DatabaseHelper.instance.getCurrentStock(line.product.code);
        if (current < line.quantity && mounted) {
          final proceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('هشدار موجودی'),
              content: Text('موجودی ${line.product.name}: ${current.toStringAsFixed(2)} ${line.product.unit}\nمقدار در فاکتور: ${NumberFormatHelper.quantity(line.quantity)}\nآیا ادامه می‌دهید؟'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('ادامه')),
              ],
            ),
          );
          if (proceed != true) { if (mounted) setState(() => _saving = false); return; }
        }
      }
      await DatabaseHelper.instance.insertInvoice(
        date: _date,
        customerName: _customerCtrl.text,
        customerPhone: _phoneCtrl.text,
        notes: _notesCtrl.text,
        discount: _discount,
        items: _lines.map((line) => <String, dynamic>{
          'product_code': line.product.code,
          'product_name': line.product.name,
          'unit': line.product.unit,
          'quantity': line.quantity,
          'unit_price': line.unitPrice,
        }).toList(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ثبت فاکتور ناموفق بود: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('صدور فاکتور فروش')),
    body: _loading
      ? const Center(child: CircularProgressIndicator())
      : _products.isEmpty
        ? const Center(child: Text('ابتدا از بخش کالاها، کالا ثبت کنید'))
        : ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            TextField(controller: _customerCtrl, decoration: const InputDecoration(labelText: 'نام مشتری (اختیاری)', prefixIcon: Icon(Icons.person_outline))),
            const SizedBox(height: 10),
            TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'شماره تماس مشتری (اختیاری)', prefixIcon: Icon(Icons.phone_outlined))),
            const SizedBox(height: 10),
            InputDecorator(decoration: const InputDecoration(labelText: 'تاریخ فاکتور'), child: Text(_date)),
            const SizedBox(height: 16),
            const Text('افزودن کالا', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _chooseProduct,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'کالا',
                  hintText: 'برای جست‌وجو و انتخاب کالا بزنید',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _selectedProduct == null
                      ? 'انتخاب کنید'
                      : '${_selectedProduct!.code} — ${_selectedProduct!.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: _quantityCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(labelText: 'تعداد / مقدار', hintText: 'مثلاً 1.5 یا 2.25', helperText: 'برای کالاهای فله‌ای یا دانه‌ای'))),
              const SizedBox(width: 10),
              Expanded(child: InputDecorator(
                decoration: const InputDecoration(labelText: 'قیمت واحد (ریال)'),
                child: Text(_selectedProduct == null ? '—' : NumberFormatHelper.integer(_selectedProduct!.sellPrice),
                  textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)),
              )),
            ]),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: _addLine, icon: const Icon(Icons.add_shopping_cart), label: const Text('افزودن به فاکتور')),
            const SizedBox(height: 16),
            const Text('اقلام فاکتور', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            if (_lines.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Text('هنوز کالایی اضافه نشده است')),
            ..._lines.asMap().entries.map((entry) {
              final line = entry.value;
              return Card(child: ListTile(
                title: Text(line.product.name),
                subtitle: Text('${NumberFormatHelper.quantity(line.quantity)} ${line.product.unit} × ${NumberFormatHelper.integer(line.unitPrice)} = ${NumberFormatHelper.integer(line.total)} ریال'),
                trailing: IconButton(tooltip: 'حذف کالا', icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _lines.removeAt(entry.key))),
              ));
            }),
            const SizedBox(height: 12),
            TextField(controller: _notesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)')),
            const SizedBox(height: 16),
            _SummaryRow(label: 'جمع کالاها', value: _subtotal),
            const SizedBox(height: 8),
            TextField(controller: _discountCtrl, keyboardType: TextInputType.number,
              inputFormatters: [_ThousandsSeparatorInputFormatter()],
              decoration: const InputDecoration(labelText: 'تخفیف کل (ریال)', hintText: 'مبلغ را وارد کنید', helperText: 'پس از جمع اقلام از مبلغ نهایی کسر می‌شود')),
            _SummaryRow(label: 'تخفیف', value: _discount),
            const Divider(),
            _SummaryRow(label: 'مبلغ نهایی', value: _total, bold: true),
          ],
        ),
    bottomNavigationBar: _loading || _products.isEmpty ? null : SafeArea(
      minimum: const EdgeInsets.all(12),
      child: FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
        label: Text(_saving ? 'در حال ثبت...' : 'ثبت نهایی فاکتور'),
      ),
    ),
  );
}

class InvoiceDetailScreen extends StatefulWidget {
  final int invoiceId;
  const InvoiceDetailScreen({super.key, required this.invoiceId});
  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  Map<String, dynamic>? _invoice;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _working = false;
  bool _returned = false;
  Map<int, double> _remainingToReturn = {};
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final invoice = await DatabaseHelper.instance.getInvoice(widget.invoiceId);
    final items = await DatabaseHelper.instance.getInvoiceItems(widget.invoiceId);
    final remaining = await DatabaseHelper.instance.getInvoiceReturnStatus(widget.invoiceId);
    if (!mounted) return;
    setState(() {
      _invoice = invoice;
      _items = items;
      _remainingToReturn = remaining;
      _returned = remaining.isNotEmpty && remaining.values.every((value) => value <= 0.0000001);
      _loading = false;
    });
  }
  Future<void> _returnInvoice() async {
    final invoice = _invoice;
    if (invoice == null || _returned || _working) return;
    final controllers = <int, TextEditingController>{
      for (final item in _items)
        (item['id'] as int): TextEditingController(
          text: NumberFormatHelper.quantity(_remainingToReturn[item['id'] as int] ?? 0),
        ),
    };
    try {
      final quantities = await showDialog<Map<int, double>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('ثبت برگشت کامل یا جزئی'),
          content: SizedBox(
            width: double.maxFinite,
            height: 420,
            child: ListView(
              children: [
                Text('فاکتور ${invoice['invoice_number']} — مقدار برگشتی را برای هر قلم وارد کنید. برای قلمی که برگشت ندارد، مقدار را صفر یا خالی بگذارید.'),
                const SizedBox(height: 12),
                for (final item in _items) ...[
                  Text('${item['product_name']} • ${item['unit']}'),
                  Text('مقدار باقی‌مانده برای برگشت: ${NumberFormatHelper.quantity(_remainingToReturn[item['id'] as int] ?? 0)}'),
                  TextField(
                    controller: controllers[item['id'] as int],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'مقدار برگشتی در این نوبت'),
                  ),
                  const Divider(),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
            FilledButton(
              onPressed: () {
                final selected = <int, double>{};
                for (final item in _items) {
                  final id = item['id'] as int;
                  final raw = controllers[id]!.text.trim();
                  final quantity = raw.isEmpty ? 0.0 : (double.tryParse(raw.replaceAll(',', '')) ?? -1);
                  final remaining = _remainingToReturn[id] ?? 0;
                  if (quantity < 0 || quantity > remaining + 0.0000001) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('مقدار برگشت برای ${item['product_name']} معتبر نیست.')),
                    );
                    return;
                  }
                  if (quantity > 0) selected[id] = quantity;
                }
                if (selected.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('مقدار برگشت را برای حداقل یک قلم وارد کنید.')),
                  );
                  return;
                }
                Navigator.pop(dialogContext, selected);
              },
              child: const Text('ادامه و ثبت برگشت'),
            ),
          ],
        ),
      );
      if (quantities == null || !mounted) return;
      setState(() => _working = true);
      await DatabaseHelper.instance.returnInvoice(
        widget.invoiceId,
        date: PersianDateHelper.today(),
        itemQuantities: quantities,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('برگشت اقلام ثبت شد؛ فاکتور اصلی حفظ شده است.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ثبت برگشت ناموفق بود: ${error.toString().replaceFirst('Bad state: ', '')}')),
        );
      }
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      if (mounted) setState(() => _working = false);
    }
  }
  Future<Uint8List> _buildPdf() async {
    final encodedFont = (await rootBundle.loadString('assets/fonts/Amiri-Regular.ttf.base64')).replaceAll(RegExp(r'\s'), '');
    final fontBytes = Uint8List.fromList(base64Decode(encodedFont));
    final font = pw.Font.ttf(ByteData.sublistView(fontBytes));
    final pdf = pw.Document();
    final invoice = _invoice!;
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: font, bold: font),
      build: (context) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text('HPLeila | فاکتور فروش', style: pw.TextStyle(font: font, fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text('شماره فاکتور: ${invoice['invoice_number']}'),
              pw.Text('تاریخ: ${invoice['date']}'),
              pw.Text('مشتری: ${(invoice['customer_name'] as String?)?.isNotEmpty == true ? invoice['customer_name'] : 'مشتری آزاد'}'),
              if ((invoice['customer_phone'] as String?)?.isNotEmpty == true) pw.Text('تلفن: ${invoice['customer_phone']}'),
              pw.SizedBox(height: 16),
              pw.TableHelper.fromTextArray(
                headers: ['مبلغ کل', 'قیمت واحد', 'تعداد', 'کالا'],
                data: _items.map((item) => [
                  NumberFormatHelper.integer((item['line_total'] as num).toDouble()),
                  NumberFormatHelper.integer((item['unit_price'] as num).toDouble()),
                  '${NumberFormatHelper.quantity((item['quantity'] as num).toDouble())} ${item['unit']}',
                  '${item['product_name']}',
                ]).toList(),
                headerStyle: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold),
                cellStyle: pw.TextStyle(font: font),
                cellAlignment: pw.Alignment.centerRight,
                headerAlignment: pw.Alignment.centerRight,
              ),
              pw.SizedBox(height: 16),
              pw.Text('جمع کالاها: ${NumberFormatHelper.integer((invoice['subtotal'] as num).toDouble())} ریال'),
              pw.Text('تخفیف: ${NumberFormatHelper.integer((invoice['discount'] as num).toDouble())} ریال'),
              pw.Text('مبلغ نهایی: ${NumberFormatHelper.integer((invoice['total'] as num).toDouble())} ریال',
                style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
              if ((invoice['notes'] as String?)?.isNotEmpty == true) ...[
                pw.SizedBox(height: 10), pw.Text('توضیحات: ${invoice['notes']}'),
              ],
            ],
          ),
        ),
      ],
    ));
    return pdf.save();
  }
  Future<void> _sharePdf() async {
    setState(() => _working = true);
    try {
      final bytes = await _buildPdf();
      await Printing.sharePdf(bytes: bytes, filename: '${_invoice!['invoice_number']}.pdf');
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ساخت یا اشتراک PDF ناموفق بود: $error')));
    } finally { if (mounted) setState(() => _working = false); }
  }
  Future<void> _printPdf() async {
    setState(() => _working = true);
    try {
      final bytes = await _buildPdf();
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('چاپ فاکتور ناموفق بود: $error')));
    } finally { if (mounted) setState(() => _working = false); }
  }
  @override
  Widget build(BuildContext context) {
    final invoice = _invoice;
    return Scaffold(
      appBar: AppBar(title: const Text('جزئیات فاکتور')),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : invoice == null ? const Center(child: Text('فاکتور پیدا نشد'))
        : ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${invoice['invoice_number']}', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('تاریخ: ${invoice['date']}'),
                Text('مشتری: ${(invoice['customer_name'] as String?)?.isNotEmpty == true ? invoice['customer_name'] : 'مشتری آزاد'}'),
                if ((invoice['customer_phone'] as String?)?.isNotEmpty == true) Text('تماس: ${invoice['customer_phone']}'),
              ],
            ))),
            const SizedBox(height: 8),
            ..._items.map((item) => Card(child: ListTile(
              title: Text('${item['product_name']}'),
              subtitle: Text('${item['quantity']} ${item['unit']} × ${NumberFormatHelper.integer((item['unit_price'] as num).toDouble())} ریال'),
              trailing: Text('${NumberFormatHelper.integer((item['line_total'] as num).toDouble())} ریال'),
            ))),
            const SizedBox(height: 8),
            _SummaryRow(label: 'جمع کالاها', value: (invoice['subtotal'] as num).toDouble()),
            _SummaryRow(label: 'تخفیف', value: (invoice['discount'] as num).toDouble()),
            const Divider(),
            _SummaryRow(label: 'مبلغ نهایی', value: (invoice['total'] as num).toDouble(), bold: true),
            if ((invoice['notes'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 12), Text('توضیحات: ${invoice['notes']}'),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: _working ? null : _sharePdf, icon: const Icon(Icons.share), label: const Text('اشتراک‌گذاری PDF')),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _working ? null : _printPdf, icon: const Icon(Icons.print), label: const Text('چاپ فاکتور')),
            const SizedBox(height: 8),
            if (_returned)
              const ListTile(
                leading: Icon(Icons.assignment_returned_outlined),
                title: Text('تمام اقلام فاکتور برگشت شده‌اند'),
                subtitle: Text('فاکتور اصلی حفظ شده و مقدار برگشتی در انبار ثبت شده است.'),
              )
            else
              OutlinedButton.icon(
                onPressed: _working ? null : _returnInvoice,
                icon: const Icon(Icons.assignment_returned_outlined),
                label: const Text('ثبت برگشت کالاها (کامل یا جزئی)'),
              ),

            if (_working) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
          ],
        ),
    );
  }
}

class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    final grouped = digits.replaceAllMapped(RegExp(r'([0-9])(?=([0-9]{3})+$)'), (m) => '${m[1]},');
    return TextEditingValue(text: grouped, selection: TextSelection.collapsed(offset: grouped.length));
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final bool bold;
  const _SummaryRow({required this.label, required this.value, this.bold = false});
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text('${NumberFormatHelper.integer(value)} ریال', style: style),
      ]),
    );
  }
}
