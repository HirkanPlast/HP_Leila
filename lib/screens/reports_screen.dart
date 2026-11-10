import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';
import '../database/database_helper.dart';
import '../utils/number_format.dart';
import '../utils/persian_date.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late int _year;
  late int _month;
  bool _loading = true;
  double _lifetimeSales = 0;
  double _lifetimePurchases = 0;
  double _monthSales = 0;
  double _yearSales = 0;
  double _previousMonthSales = 0;
  double _previousYearSales = 0;
  double _bestDaySales = 0;
  String? _bestDay;
  List<MapEntry<String, double>> _daily = [];
  List<MapEntry<String, double>> _monthly = [];
  List<MapEntry<String, double>> _weekdays = [];
  List<String> _noSalesDays = [];
  bool _selectedMonthIsFuture = false;

  @override
  void initState() {
    super.initState();
    final now = PersianDateHelper.parse(PersianDateHelper.today())!;
    _year = now.year;
    _month = now.month;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = await DatabaseHelper.instance.database;
    final all = await db.rawQuery("SELECT date, type, quantity, unit_price, created_by FROM transactions WHERE type IN ('فروش','ورود','برگشت') ORDER BY date ASC");
    double lifetimeSales = 0, lifetimePurchases = 0, monthSales = 0, yearSales = 0;
    double previousMonthSales = 0, previousYearSales = 0;
    final previousMonth = _month == 1 ? 12 : _month - 1;
    final previousMonthYear = _month == 1 ? _year - 1 : _year;
    final dailyMap = <int, double>{};
    final monthlyMap = <int, double>{};
    final weekdayMap = <int, double>{};
    final allSalesDays = <String, double>{};
    for (final row in all) {
      final date = row['date'] as String;
      final type = row['type'] as String;
      final createdBy = row['created_by'] as String?;
      final amount = (row['quantity'] as num).toDouble() * (row['unit_price'] as num).toDouble();
      final parsed = PersianDateHelper.parse(date);
      if (type == 'فروش' || type == 'برگشت') {
        final salesAmount = type == 'برگشت' ? -amount : amount;
        lifetimeSales += salesAmount;
        allSalesDays[date] = (allSalesDays[date] ?? 0) + salesAmount;
        if (parsed != null) {
          if (parsed.year == _year) {
            yearSales += salesAmount;
            monthlyMap[parsed.month] = (monthlyMap[parsed.month] ?? 0) + salesAmount;
          }
          if (parsed.year == _year - 1) previousYearSales += salesAmount;
          if (parsed.year == previousMonthYear && parsed.month == previousMonth) previousMonthSales += salesAmount;
          if (parsed.year == _year && parsed.month == _month) {
            monthSales += salesAmount;
            dailyMap[parsed.day] = (dailyMap[parsed.day] ?? 0) + salesAmount;
            final weekday = parsed.toDateTime().weekday;
            weekdayMap[weekday] = (weekdayMap[weekday] ?? 0) + salesAmount;
          }
        }
      } else if (type == 'ورود') {
        lifetimePurchases += amount;
      }
    }
    final monthLength = JalaliMonthDays.length(_year, _month);
    final today = PersianDateHelper.parse(PersianDateHelper.today())!;
    final selectedMonthIsFuture = _year > today.year || (_year == today.year && _month > today.month);
    final daysToReport = selectedMonthIsFuture ? 0 : (_year == today.year && _month == today.month ? today.day : monthLength);
    final noSales = <String>[];
    for (var day = 1; day <= daysToReport; day++) {
      final date = '${_year}/${_month.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}';
      if ((dailyMap[day] ?? 0) == 0) noSales.add(date);
    }
    final sortedDays = dailyMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final sortedMonths = monthlyMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    const weekdayNames = {1:'دوشنبه',2:'سه‌شنبه',3:'چهارشنبه',4:'پنجشنبه',5:'جمعه',6:'شنبه',7:'یکشنبه'};
    final sortedWeekdays = weekdayMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final salesByDay = allSalesDays.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (!mounted) return;
    setState(() {
      _lifetimeSales = lifetimeSales;
      _lifetimePurchases = lifetimePurchases;
      _monthSales = monthSales;
      _yearSales = yearSales;
      _previousMonthSales = previousMonthSales;
      _previousYearSales = previousYearSales;
      _bestDay = salesByDay.isEmpty ? null : salesByDay.first.key;
      _bestDaySales = salesByDay.isEmpty ? 0 : salesByDay.first.value;
      _daily = sortedDays.map((e) => MapEntry('${e.key}', e.value)).toList();
      _monthly = sortedMonths.map((e) => MapEntry(PersianDateHelper.monthName(e.key), e.value)).toList();
      _weekdays = sortedWeekdays.map((e) => MapEntry(weekdayNames[e.key]!, e.value)).toList();
      _noSalesDays = noSales;
      _selectedMonthIsFuture = selectedMonthIsFuture;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('گزارش فروش و خرید'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
    body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(child: DropdownButtonFormField<int>(
            value: _year, decoration: const InputDecoration(labelText: 'سال'),
            items: List.generate(8, (i) => _year - 5 + i).map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
            onChanged: (v) { if (v != null) setState(() { _year = v; }); _load(); },
          )),
          const SizedBox(width: 12),
          Expanded(child: DropdownButtonFormField<int>(
            value: _month, decoration: const InputDecoration(labelText: 'ماه'),
            items: List.generate(12, (i) => i + 1).map((m) => DropdownMenuItem(value: m, child: Text(PersianDateHelper.monthName(m)))).toList(),
            onChanged: (v) { if (v != null) setState(() { _month = v; }); _load(); },
          )),
        ]),
        const SizedBox(height: 16),
        _MetricCard(title: 'کل فروش تا امروز', value: _lifetimeSales),
        _MetricCard(title: 'کل خرید تا امروز', value: _lifetimePurchases),
        _MetricCard(title: 'فروش سال $_year', value: _yearSales, subtitle: 'سال قبل: ${NumberFormatHelper.integer(_previousYearSales / 10)} تومان'),
        _MetricCard(title: 'فروش ${PersianDateHelper.monthName(_month)} $_year', value: _monthSales, subtitle: 'ماه قبل: ${NumberFormatHelper.integer(_previousMonthSales / 10)} تومان'),
        _MetricCard(title: 'پرفروش‌ترین روز ثبت‌شده', value: _bestDaySales, subtitle: _bestDay ?? 'هنوز فروشی ثبت نشده است'),
        const SizedBox(height: 12),
        _BarsCard(title: 'فروش ماهانه در سال $_year', entries: _monthly),
        _BarsCard(title: 'فروش روزانه در ماه انتخاب‌شده', entries: _daily),
        _BarsCard(title: 'فروش به تفکیک روز هفته', entries: _weekdays),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('روزهای بدون فروش در ${PersianDateHelper.monthName(_month)}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(_selectedMonthIsFuture ? 'ماه انتخاب‌شده هنوز نرسیده است.' : (_noSalesDays.isEmpty ? 'برای این ماه روز بدون فروش ثبت‌شده‌ای وجود ندارد.' : _noSalesDays.join('، '))),
        ]))),
        const Padding(padding: EdgeInsets.only(top: 8), child: Text('توجه: مبلغ خرید بر اساس تراکنش‌های «ورود» و مبلغ فروش پس از کسر همهٔ تراکنش‌های برگشت ثبت‌شده محاسبه می‌شود. این گزارش سود حسابداری را محاسبه نمی‌کند.')),
      ],
    ),
  );
}

class JalaliMonthDays {
  static int length(int year, int month) {
    return Jalali(year, month, 1).monthLength;
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final double value;
  final String? subtitle;
  const _MetricCard({required this.title, required this.value, this.subtitle});
  @override
  Widget build(BuildContext context) => Card(child: ListTile(
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: Text('${NumberFormatHelper.integer(value / 10)} تومان', style: const TextStyle(fontWeight: FontWeight.bold)),
  ));
}

class _BarsCard extends StatelessWidget {
  final String title;
  final List<MapEntry<String, double>> entries;
  const _BarsCard({required this.title, required this.entries});
  @override
  Widget build(BuildContext context) {
    final maxValue = entries.fold<double>(0, (max, e) => e.value > max ? e.value : max);
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (entries.isEmpty) const Text('هنوز داده‌ای برای نمایش وجود ندارد.'),
        ...entries.map((e) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(width: 82, child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(
              value: maxValue <= 0 ? 0 : e.value / maxValue, minHeight: 12,
            ))),
            const SizedBox(width: 8),
            SizedBox(width: 72, child: Text(NumberFormatHelper.integer(e.value / 10), textAlign: TextAlign.end)),
          ]),
        )),
      ],
    )));
  }
}
