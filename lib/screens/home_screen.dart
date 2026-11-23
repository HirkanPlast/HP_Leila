import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../utils/home_navigation.dart';
import 'invoice_screen.dart';
import 'help_screen.dart';
import 'backup_restore_screen.dart';
import 'dashboard_screen.dart';
import 'transactions_screen.dart';
import 'inventory_screen.dart';
import 'expenses_screen.dart';
import 'products_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final String role; // 'seller' or 'manager'
  const HomeScreen({super.key, required this.role});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  late final List<Widget> _pages;
  late final List<BottomNavigationBarItem> _items;

  // Distinct, moderately saturated page accents. Text colors remain theme-driven
  // to preserve contrast in both light and dark modes.
  static const List<Color> _pageAccents = [
    Color(0xFF1976D2), // Dashboard: blue
    Color(0xFF6554C0), // Transactions: violet
    Color(0xFFB7791F), // Inventory: amber
    Color(0xFFD65F4A), // Expenses: coral
    Color(0xFF168C83), // Products: teal
    Color(0xFF60758A), // Settings: slate
  ];

  ThemeData _themeForPage(BuildContext context, int index) {
    final base = Theme.of(context);
    final seed = _pageAccents[index.clamp(0, _pageAccents.length - 1)];
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: base.brightness,
    );
    return base.copyWith(
      colorScheme: scheme,
      primaryColor: scheme.primary,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        iconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: (base.textTheme.titleLarge ?? const TextStyle()).copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
    );
  }

  ThemeData _specialPageTheme(BuildContext context, Color seed) {
    final base = Theme.of(context);
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: base.brightness);
    return base.copyWith(
      colorScheme: scheme,
      primaryColor: scheme.primary,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        iconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: (base.textTheme.titleLarge ?? const TextStyle()).copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final isManager = widget.role == 'manager';
    _pages = [
      const DashboardScreen(),
      const TransactionsScreen(),
      const InventoryScreen(),
      const ExpensesScreen(),
      if (isManager) const ProductsScreen(),
      SettingsScreen(role: widget.role),
    ];
    _items = [
      const BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'در یک نگاه'),
      const BottomNavigationBarItem(icon: Icon(Icons.swap_horiz), label: 'تراکنش'),
      const BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'موجودی'),
      const BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'هزینه‌ها'),
      if (isManager) const BottomNavigationBarItem(icon: Icon(Icons.category), label: 'کالاها'),
      const BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'تنظیمات'),
    ];
  }

  void _selectPage(BuildContext context, int index) {
    Navigator.pop(context);
    setState(() => _currentIndex = index);
  }

  ListTile _drawerItem(BuildContext context, int index, IconData icon, String label) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    selected: _currentIndex == index,
    onTap: () => _selectPage(context, index),
  );

  @override
  Widget build(BuildContext context) {
    final currentScheme = _themeForPage(context, _currentIndex).colorScheme;
    return Scaffold(
      key: homeScaffoldKey,
      drawer: Drawer(
        child: SafeArea(child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF087F73), Color(0xFF003D38)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
              child: Align(
                alignment: Alignment.bottomRight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SvgPicture.asset('assets/leila-logo.svg', width: 88, height: 88),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('مدیریت فروشگاه هیرکان پلاست', style: TextStyle(color: Colors.white, fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _drawerItem(context, 0, Icons.dashboard_outlined, 'در یک نگاه'),
            _drawerItem(context, 1, Icons.swap_horiz, 'تراکنش‌ها'),
            _drawerItem(context, 2, Icons.inventory_2_outlined, 'موجودی انبار'),
            _drawerItem(context, 3, Icons.money_off_outlined, 'هزینه‌ها'),
            if (widget.role == 'manager') _drawerItem(context, 4, Icons.category_outlined, 'مدیریت کالاها'),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('فاکتورهای فروش'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => Theme(
                    data: _specialPageTheme(context, const Color(0xFF27965B)),
                    child: const InvoicesScreen(),
                  ),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.analytics_outlined),
              title: const Text('آمار و گزارش‌ها'),
              subtitle: const Text('گزارش ماهانه، سالانه و مقایسه فروش'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => Theme(
                    data: _specialPageTheme(context, const Color(0xFF8B5CC7)),
                    child: const ReportsScreen(),
                  ),
                ));
              },
            ),
            _drawerItem(context, widget.role == 'manager' ? 5 : 4, Icons.settings_outlined, 'تنظیمات'),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('راهنما و اطلاعات حقوقی'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => Theme(
                    data: _specialPageTheme(context, const Color(0xFF278FAD)),
                    child: const HelpScreen(),
                  ),
                ));
              },
            ),
          ],
        )),
      ),
      floatingActionButton: _currentIndex == 0 ? FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => Theme(
            data: _specialPageTheme(context, const Color(0xFF27965B)),
            child: const InvoicesScreen(),
          ),
        )),
        icon: const Icon(Icons.receipt_long),
        label: const Text('فاکتور فروش'),
      ) : null,
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(
          _pages.length,
          (index) => Theme(data: _themeForPage(context, index), child: _pages[index]),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: currentScheme.primary,
        unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
        selectedFontSize: 12,
        unselectedFontSize: 11,
        items: _items,
      ),
    );
  }
}