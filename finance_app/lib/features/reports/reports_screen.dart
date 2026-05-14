import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/db/database_helper.dart';
import '../../core/models/transaction_model.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  DateTime _selectedMonth = DateTime.now();
  List<TransactionModel> _transactions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1).millisecondsSinceEpoch;
    final end = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1).millisecondsSinceEpoch;
    final rows = await DatabaseHelper.instance.rawQuery('''
      SELECT t.*, c.name as category_name, c.icon as category_icon, c.color as category_color,
             a.name as account_name
      FROM transactions t
      LEFT JOIN categories c ON t.category_id = c.id
      LEFT JOIN accounts a ON t.account_id = a.id
      WHERE t.date >= ? AND t.date < ?
      ORDER BY t.date DESC
    ''', [start, end]);
    if (mounted) {
      setState(() {
        _transactions = rows.map(TransactionModel.fromMap).toList();
        _loading = false;
      });
    }
  }

  List<TransactionModel> get _expenses => _transactions.where((t) => t.isExpense).toList();
  List<TransactionModel> get _income => _transactions.where((t) => t.isIncome).toList();
  double get _totalExpense => _expenses.fold(0, (s, t) => s + t.amount);
  double get _totalIncome => _income.fold(0, (s, t) => s + t.amount);

  Map<String, double> get _expenseByCategory {
    final map = <String, double>{};
    for (final t in _expenses) {
      final key = t.categoryName ?? 'Other';
      map[key] = (map[key] ?? 0) + t.amount;
    }
    return Map.fromEntries(map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.lightTextSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [Tab(text: 'Overview'), Tab(text: 'Categories'), Tab(text: 'Calendar')],
        ),
      ),
      body: Column(
        children: [
          _buildMonthSelector(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tab,
                    children: [
                      _buildOverview(),
                      _buildCategories(),
                      _buildCalendar(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () {
            setState(() { _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1); _loading = true; });
            _load();
          }),
          Text(DateFormatter.formatMonth(_selectedMonth), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () {
            setState(() { _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1); _loading = true; });
            _load();
          }),
        ],
      ),
    );
  }

  Widget _buildOverview() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(child: _StatCard(label: 'Total Income', amount: _totalIncome, color: AppColors.income)),
          const SizedBox(width: 12),
          Expanded(child: _StatCard(label: 'Total Expenses', amount: _totalExpense, color: AppColors.expense)),
        ]),
        const SizedBox(height: 12),
        _StatCard(label: 'Net Savings', amount: _totalIncome - _totalExpense,
            color: (_totalIncome - _totalExpense) >= 0 ? AppColors.income : AppColors.expense),
        const SizedBox(height: 20),
        const Text('Income vs Expense', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: BarChart(BarChartData(
            alignment: BarChartAlignment.center,
            maxY: (_totalIncome > _totalExpense ? _totalIncome : _totalExpense) * 1.2,
            barGroups: [
              BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: _totalIncome, color: AppColors.income, width: 50, borderRadius: BorderRadius.circular(8))]),
              BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: _totalExpense, color: AppColors.expense, width: 50, borderRadius: BorderRadius.circular(8))]),
            ],
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true,
                getTitlesWidget: (v, _) => Text(v == 0 ? 'Income' : 'Expense', style: const TextStyle(fontSize: 12)))),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
          )),
        ),
        const SizedBox(height: 20),
        if (_transactions.isEmpty)
          const Center(child: Text('No transactions this month', style: TextStyle(color: AppColors.lightTextSecondary))),
      ],
    );
  }

  Widget _buildCategories() {
    final byCategory = _expenseByCategory;
    if (byCategory.isEmpty) {
      return const Center(child: Text('No expense data this month'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(
          height: 240,
          child: PieChart(PieChartData(
            sections: byCategory.entries.map((e) {
              final colors = [AppColors.catFood, AppColors.catGrocery, AppColors.catTransport,
                AppColors.catShopping, AppColors.catEntertainment, AppColors.catHealth];
              final idx = byCategory.keys.toList().indexOf(e.key) % colors.length;
              return PieChartSectionData(
                value: e.value, color: colors[idx],
                title: '${(e.value / _totalExpense * 100).toInt()}%',
                radius: 80,
                titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700),
              );
            }).toList(),
            centerSpaceRadius: 40, sectionsSpace: 2,
          )),
        ),
        const SizedBox(height: 16),
        ...byCategory.entries.map((e) {
          final pct = _totalExpense > 0 ? e.value / _totalExpense : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(e.key, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                    Text(CurrencyFormatter.formatCompact(e.value), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct.toDouble(),
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                      minHeight: 6,
                    ),
                  ),
                ],
              )),
            ]),
          );
        }),
      ],
    );
  }

  Widget _buildCalendar() {
    final dailyTotals = <DateTime, double>{};
    for (final t in _expenses) {
      final day = DateTime(t.date.year, t.date.month, t.date.day);
      dailyTotals[day] = (dailyTotals[day] ?? 0) + t.amount;
    }
    return TableCalendar(
      firstDay: DateTime(2020),
      lastDay: DateTime(2100),
      focusedDay: _selectedMonth,
      calendarFormat: CalendarFormat.month,
      headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
      calendarBuilders: CalendarBuilders(
        markerBuilder: (ctx, day, events) {
          final key = DateTime(day.year, day.month, day.day);
          final amount = dailyTotals[key];
          if (amount == null) return null;
          return Positioned(
            bottom: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: AppColors.expense.withOpacity(0.8), borderRadius: BorderRadius.circular(4)),
              child: Text('₹${(amount / 1000).toStringAsFixed(0)}K', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w600)),
            ),
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  const _StatCard({required this.label, required this.amount, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(CurrencyFormatter.format(amount), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
