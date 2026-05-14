import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/db/database_helper.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';

/// Monthly summary card shown on Dashboard — compares this month vs last month.
class MonthlySummaryCard extends ConsumerStatefulWidget {
  const MonthlySummaryCard({super.key});
  @override
  ConsumerState<MonthlySummaryCard> createState() => _MonthlySummaryCardState();
}

class _MonthlySummaryCardState extends ConsumerState<MonthlySummaryCard> {
  _SummaryData? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final now = DateTime.now();

    final thisStart = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
    final lastStart = DateTime(now.year, now.month - 1, 1).millisecondsSinceEpoch;
    final lastEnd   = thisStart;

    Future<Map<String, double>> fetch(int from, int to) async {
      final rows = await db.rawQuery(
        'SELECT type, SUM(amount) as total FROM transactions WHERE date >= ? AND date < ? GROUP BY type',
        [from, to],
      );
      double inc = 0, exp = 0;
      for (final r in rows) {
        if (r['type'] == 'INCOME')  inc = (r['total'] as num).toDouble();
        if (r['type'] == 'EXPENSE') exp = (r['total'] as num).toDouble();
      }
      return {'income': inc, 'expense': exp};
    }

    final thisMonth = await fetch(thisStart, now.millisecondsSinceEpoch);
    final lastMonth = await fetch(lastStart, lastEnd);

    // Top spending category this month
    final catRows = await db.rawQuery('''
      SELECT c.name, SUM(t.amount) as total
      FROM transactions t LEFT JOIN categories c ON t.category_id = c.id
      WHERE t.type = 'EXPENSE' AND t.date >= ?
      GROUP BY t.category_id ORDER BY total DESC LIMIT 1
    ''', [thisStart]);

    // No-spend days this month
    final spendDays = await db.rawQuery('''
      SELECT COUNT(DISTINCT strftime('%d', datetime(date/1000,'unixepoch'))) as cnt
      FROM transactions WHERE type = 'EXPENSE' AND date >= ?
    ''', [thisStart]);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final spentDayCount = (spendDays.first['cnt'] as int? ?? 0);
    final noSpendDays = daysInMonth - spentDayCount;

    if (mounted) {
      setState(() {
        _data = _SummaryData(
          thisIncome: thisMonth['income']!,
          thisExpense: thisMonth['expense']!,
          lastIncome: lastMonth['income']!,
          lastExpense: lastMonth['expense']!,
          topCategory: catRows.isNotEmpty ? catRows.first['name'] as String? : null,
          topCategoryAmount: catRows.isNotEmpty ? (catRows.first['total'] as num).toDouble() : 0,
          noSpendDays: noSpendDays,
          month: DateFormatter.formatMonth(now),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) return const SizedBox.shrink();
    final d = _data!;
    final saved = d.thisIncome - d.thisExpense;
    final lastSaved = d.lastIncome - d.lastExpense;
    final savingsDiff = saved - lastSaved;
    final expenseDiff = d.lastExpense > 0
        ? ((d.thisExpense - d.lastExpense) / d.lastExpense * 100)
        : 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1D2E), Color(0xFF252838)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(children: [
              const Text('📊', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(d.month, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                child: const Text('Monthly Summary', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),

          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),

          // Stats grid
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                Expanded(child: _StatItem(
                  label: 'Saved',
                  value: CurrencyFormatter.formatCompact(saved),
                  color: saved >= 0 ? AppColors.income : AppColors.expense,
                  sub: savingsDiff >= 0
                      ? '↑ ${CurrencyFormatter.formatCompact(savingsDiff)} more than last month'
                      : '↓ ${CurrencyFormatter.formatCompact(savingsDiff.abs())} less than last month',
                  subColor: savingsDiff >= 0 ? AppColors.income : AppColors.expense,
                )),
                Container(width: 1, height: 48, color: Colors.white12),
                Expanded(child: _StatItem(
                  label: 'Spent',
                  value: CurrencyFormatter.formatCompact(d.thisExpense),
                  color: AppColors.expense,
                  sub: expenseDiff == 0
                      ? 'Same as last month'
                      : expenseDiff > 0
                          ? '↑ ${expenseDiff.toStringAsFixed(0)}% vs last month'
                          : '↓ ${expenseDiff.abs().toStringAsFixed(0)}% vs last month',
                  subColor: expenseDiff <= 0 ? AppColors.income : AppColors.expense,
                )),
              ]),

              const SizedBox(height: 12),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 12),

              Row(children: [
                if (d.topCategory != null)
                  Expanded(child: _StatItem(
                    label: 'Top Category',
                    value: d.topCategory!,
                    color: Colors.white,
                    sub: CurrencyFormatter.formatCompact(d.topCategoryAmount),
                    subColor: AppColors.expense,
                  )),
                if (d.noSpendDays > 0) ...[
                  Container(width: 1, height: 48, color: Colors.white12),
                  Expanded(child: _StatItem(
                    label: 'No-Spend Days',
                    value: '${d.noSpendDays} days 🎉',
                    color: AppColors.income,
                    sub: 'This month',
                    subColor: Colors.white38,
                  )),
                ],
              ]),
            ]),
          ),

          // Insight bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Text(
              _insight(d, saved, expenseDiff),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.1);
  }

  String _insight(_SummaryData d, double saved, double expDiff) {
    if (saved > 0 && expDiff < 0) return '🎉 Great month! You\'re spending less and saving more.';
    if (saved < 0) return '⚠️ You spent more than you earned this month. Review your expenses.';
    if (expDiff > 20) return '📈 Spending is up ${expDiff.toStringAsFixed(0)}% vs last month. Keep an eye on it.';
    if (d.noSpendDays > 10) return '🏆 ${d.noSpendDays} no-spend days this month — excellent discipline!';
    return '💡 Keep tracking every transaction for better insights.';
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String sub;
  final Color subColor;
  const _StatItem({required this.label, required this.value, required this.color, required this.sub, required this.subColor});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(sub, style: TextStyle(color: subColor, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  );
}

class _SummaryData {
  final double thisIncome, thisExpense, lastIncome, lastExpense, topCategoryAmount;
  final String? topCategory;
  final int noSpendDays;
  final String month;
  const _SummaryData({
    required this.thisIncome, required this.thisExpense,
    required this.lastIncome, required this.lastExpense,
    required this.topCategory, required this.topCategoryAmount,
    required this.noSpendDays, required this.month,
  });
}
