import 'package:flutter/material.dart';
import 'reports_screen.dart';
import '../utils/home_navigation.dart';
import '../database/database_helper.dart';
import '../utils/persian_date.dart';
import '../utils/constants.dart';
import '../utils/number_format.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final stats = await DatabaseHelper.instance.getDashboardStats(
      today: PersianDateHelper.today(),
      monthStart: PersianDateHelper.monthStart(),
    );
    if (mounted) {
      setState(() {
        _stats = stats;
        _loading = false;
      });
    }
  }

  String _formatNumber(double value) {
    final rounded = value.round().toString();
    return rounded.replaceAllMapped(
      RegExp(r'(?<!^)(?=(\d{3})+$)'),
      (match) => ',',
    );
  }

  // Stored amounts remain Rial; dashboard displays reports in Toman only.
  String _money(double value) => '${_formatNumber(value / 10)} تومان';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'منوی اصلی', icon: const Icon(Icons.menu), onPressed: openHomeDrawer),
        title: const Text('در یک نگاه'),
        actions: [
          IconButton(
            tooltip: 'آمار و گزارش‌ها',
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const ReportsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Header
                  Text(
                    'فروشگاه هیرکان پلاست',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    'امروز: ${PersianDateHelper.today()}',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 20),

                  // Sales cards
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'فروش امروز',
                          value: _money(_stats!['sales_today'] ?? 0),
                          subtitle: '${_stats!['sales_today_qty']?.toStringAsFixed(0) ?? 0} قلم',
                          color: Colors.green,
                          icon: Icons.today,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          title: 'فروش ماه',
                          value: _money(_stats!['sales_month'] ?? 0),
                          subtitle: '${_stats!['sales_month_qty']?.toStringAsFixed(0) ?? 0} قلم',
                          color: Colors.blue,
                          icon: Icons.calendar_month,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Profit cards
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'سود ناخالص ماه',
                          value: _money(_stats!['gross_profit_month'] ?? 0),
                          color: Colors.teal,
                          icon: Icons.trending_up,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          title: 'سود خالص ماه',
                          value: _money(_stats!['net_profit_month'] ?? 0),
                          subtitle: 'بعد از هزینه‌ها',
                          color: (_stats!['net_profit_month'] ?? 0) >= 0
                              ? Colors.green.shade700
                              : Colors.red,
                          icon: Icons.account_balance_wallet,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Expenses
                  _StatCard(
                    title: 'هزینه‌های این ماه',
                    value: _money(_stats!['expenses_month'] ?? 0),
                    color: Colors.orange,
                    icon: Icons.money_off,
                    fullWidth: true,
                  ),
                  const SizedBox(height: 20),

                  // Inventory summary
                  Text(
                    'وضعیت انبار',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MiniStat(
                          label: 'تأمین',
                          value: '${_stats!['products_ok'] ?? 0}',
                          color: Colors.green,
                        ),
                      ),
                      Expanded(
                        child: _MiniStat(
                          label: 'کمبود',
                          value: '${_stats!['products_low'] ?? 0}',
                          color: Colors.orange,
                        ),
                      ),
                      Expanded(
                        child: _MiniStat(
                          label: 'بدون موجودی',
                          value: '${_stats!['products_out'] ?? 0}',
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _InfoRow(
                            label: 'ارزش انبار (خرید)',
                            value: _money(_stats!['stock_value_buy'] ?? 0),
                          ),
                          const Divider(),
                          _InfoRow(
                            label: 'ارزش انبار (فروش)',
                            value: _money(_stats!['stock_value_sell'] ?? 0),
                          ),
                          const Divider(),
                          _InfoRow(
                            label: 'تعداد کل کالاها',
                            value: '${_stats!['total_products'] ?? 0}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'نسخه ${AppConstants.version}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final Color color;
  final IconData icon;
  final bool fullWidth;

  const _StatCard({
    required this.title,
    required this.value,
    this.subtitle,
    required this.color,
    required this.icon,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
