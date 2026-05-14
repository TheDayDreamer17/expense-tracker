import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/db/database_helper.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';

class HealthScoreScreen extends ConsumerStatefulWidget {
  const HealthScoreScreen({super.key});
  @override
  ConsumerState<HealthScoreScreen> createState() => _HealthScoreScreenState();
}

class _HealthScoreScreenState extends ConsumerState<HealthScoreScreen> {
  bool _loading = true;
  int _score = 0;
  Map<String, _ScoreComponent> _components = {};
  List<String> _insights = [];

  @override
  void initState() { super.initState(); _compute(); }

  Future<void> _compute() async {
    final db = DatabaseHelper.instance;
    final now = DateTime.now();
    final threeMonthsAgo = DateTime(now.year, now.month - 3, 1).millisecondsSinceEpoch;
    final thisMonthStart = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;

    // Monthly income & expense averages
    final monthlyData = await db.rawQuery('''
      SELECT 
        strftime('%Y-%m', datetime(date/1000, 'unixepoch')) as month,
        type, SUM(amount) as total
      FROM transactions WHERE date >= ? GROUP BY month, type
    ''', [threeMonthsAgo]);

    double avgIncome = 0, avgExpense = 0;
    final monthMap = <String, Map<String, double>>{};
    for (final r in monthlyData) {
      final m = r['month'] as String;
      monthMap.putIfAbsent(m, () => {});
      monthMap[m]![r['type'] as String] = (r['total'] as num).toDouble();
    }
    if (monthMap.isNotEmpty) {
      avgIncome = monthMap.values.map((m) => m['INCOME'] ?? 0).fold(0.0, (a, b) => a + b) / monthMap.length;
      avgExpense = monthMap.values.map((m) => m['EXPENSE'] ?? 0).fold(0.0, (a, b) => a + b) / monthMap.length;
    }

    // This month's stats
    final thisMonth = await db.rawQuery(
        'SELECT type, SUM(amount) as total FROM transactions WHERE date >= ? GROUP BY type', [thisMonthStart]);
    double thisIncome = 0, thisExpense = 0;
    for (final r in thisMonth) {
      if (r['type'] == 'INCOME') thisIncome = (r['total'] as num).toDouble();
      if (r['type'] == 'EXPENSE') thisExpense = (r['total'] as num).toDouble();
    }

    // Net worth
    final nwRows = await db.rawQuery('SELECT entry_type, SUM(amount) as total FROM (SELECT name, entry_type, amount FROM net_worth_entries GROUP BY name ORDER BY date DESC) GROUP BY entry_type');
    double totalAssets = 0, totalLiabilities = 0;
    for (final r in nwRows) {
      if (r['entry_type'] == 'ASSET') totalAssets = (r['total'] as num).toDouble();
      if (r['entry_type'] == 'LIABILITY') totalLiabilities = (r['total'] as num).toDouble();
    }

    // Subscriptions
    final unusedSubs = await db.rawQuery(
        "SELECT COUNT(*) as cnt FROM subscriptions WHERE last_used_date IS NULL OR last_used_date < ?",
        [DateTime.now().subtract(const Duration(days: 14)).millisecondsSinceEpoch]);
    final unusedCount = (unusedSubs.first['cnt'] as int);

    // Weekend vs weekday
    final weekendTx = await db.rawQuery('''
      SELECT SUM(amount) as total FROM transactions
      WHERE type = 'EXPENSE' AND date >= ?
        AND CAST(strftime('%w', datetime(date/1000,'unixepoch')) AS INTEGER) IN (0,6)
    ''', [thisMonthStart]);
    final weekdayTx = await db.rawQuery('''
      SELECT SUM(amount) as total FROM transactions
      WHERE type = 'EXPENSE' AND date >= ?
        AND CAST(strftime('%w', datetime(date/1000,'unixepoch')) AS INTEGER) NOT IN (0,6)
    ''', [thisMonthStart]);
    final weekendSpend = (weekendTx.first['total'] as num?)?.toDouble() ?? 0;
    final weekdaySpend = (weekdayTx.first['total'] as num?)?.toDouble() ?? 0;
    final weekdayAvg = weekdaySpend / 5;
    final weekendAvg = weekendSpend / 2;
    final weekendRatio = weekdayAvg > 0 ? weekendAvg / weekdayAvg : 0.0;

    // Salary week (1st-7th)
    final salaryWeekTx = await db.rawQuery('''
      SELECT SUM(amount) as total FROM transactions
      WHERE type = 'EXPENSE' AND date >= ?
        AND CAST(strftime('%d', datetime(date/1000,'unixepoch')) AS INTEGER) <= 7
    ''', [thisMonthStart]);
    final restMonthTx = await db.rawQuery('''
      SELECT SUM(amount) as total FROM transactions
      WHERE type = 'EXPENSE' AND date >= ?
        AND CAST(strftime('%d', datetime(date/1000,'unixepoch')) AS INTEGER) > 7
    ''', [thisMonthStart]);
    final salaryWeekSpend = (salaryWeekTx.first['total'] as num?)?.toDouble() ?? 0;
    final restMonthSpend = (restMonthTx.first['total'] as num?)?.toDouble() ?? 0;
    final salaryWeekDailyAvg = salaryWeekSpend / 7;
    final restMonthDailyAvg = restMonthSpend / 23;
    final salarySpike = restMonthDailyAvg > 0 ? salaryWeekDailyAvg / restMonthDailyAvg : 0.0;

    // ─── Score computation ─────────────────────────────────────────────────
    // 1. Savings rate (20 pts): (income - expense) / income
    final savingsRate = thisIncome > 0 ? (thisIncome - thisExpense) / thisIncome : 0.0;
    final savingsScore = (savingsRate.clamp(0, 0.4) / 0.4 * 20).round();

    // 2. Emergency fund (20 pts): assets >= 3 months expense
    final emergencyTarget = avgExpense * 3;
    final efRatio = emergencyTarget > 0 ? (totalAssets / emergencyTarget).clamp(0, 1.0) : 0.0;
    final efScore = (efRatio * 20).round();

    // 3. Debt ratio (20 pts): liabilities / assets
    final debtRatio = totalAssets > 0 ? (totalLiabilities / totalAssets).clamp(0, 1.0) : 1.0;
    final debtScore = ((1 - debtRatio) * 20).round();

    // 4. Lifestyle inflation (15 pts): expense vs 3-month avg
    final lifestyleChange = avgExpense > 0 ? ((thisExpense - avgExpense) / avgExpense) : 0.0;
    final lifestyleScore = lifestyleChange > 0.2 ? 0 : lifestyleChange > 0 ? 8 : 15;

    // 5. Subscription wastage (10 pts)
    final subScore = unusedCount == 0 ? 10 : unusedCount <= 2 ? 5 : 0;

    // 6. Investment consistency (15 pts)
    final nwEntries = await db.query('net_worth_entries');
    final investmentScore = nwEntries.length >= 3 ? 15 : nwEntries.length >= 1 ? 8 : 0;

    final total = savingsScore + efScore + debtScore + lifestyleScore + subScore + investmentScore;

    // ─── Insights ──────────────────────────────────────────────────────────
    final insights = <String>[];
    if (savingsRate < 0.1) insights.add("💸 You're saving less than 10% of your income this month.");
    if (savingsRate >= 0.2) insights.add("🎉 Great! You saved ${(savingsRate * 100).toInt()}% of your income this month.");
    if (efRatio < 0.5) insights.add("⚠️ Emergency fund is below 1.5 months of expenses. Consider building it up.");
    if (lifestyleChange > 0.2) insights.add("📈 Spending increased ${(lifestyleChange * 100).toInt()}% vs your 3-month average.");
    if (weekendRatio > 2) insights.add("🍻 Weekend spending is ${weekendRatio.toStringAsFixed(1)}× your weekday average.");
    if (salarySpike > 1.5) insights.add("📅 Salary week spending is ${(salarySpike * 100).toInt()}% higher than rest of month.");
    if (unusedCount > 0) insights.add("🔄 $unusedCount subscription(s) unused for 14+ days — consider cancelling.");
    if (debtRatio > 0.5) insights.add("🔴 Debt ratio is high (${(debtRatio * 100).toInt()}% of assets). Focus on paying down liabilities.");

    if (mounted) {
      setState(() {
        _score = total.clamp(0, 100);
        _components = {
          'Savings Rate': _ScoreComponent(savingsScore, 20, '💰', 'Save at least 20% of income'),
          'Emergency Fund': _ScoreComponent(efScore, 20, '🛡', '3+ months of expenses saved'),
          'Debt Ratio': _ScoreComponent(debtScore, 20, '🏦', 'Keep liabilities below 50% of assets'),
          'Lifestyle Inflation': _ScoreComponent(lifestyleScore, 15, '📊', 'Avoid spending spikes month over month'),
          'Subscriptions': _ScoreComponent(subScore, 10, '🔄', 'No unused subscriptions'),
          'Investments': _ScoreComponent(investmentScore, 15, '📈', 'Track your investments regularly'),
        };
        _insights = insights;
        _loading = false;
      });
    }
  }

  Color _scoreColor(int score) {
    if (score >= 80) return AppColors.income;
    if (score >= 60) return AppColors.warning;
    return AppColors.expense;
  }

  String _scoreLabel(int score) {
    if (score >= 80) return 'Excellent 🏆';
    if (score >= 60) return 'Good 👍';
    if (score >= 40) return 'Fair ⚡';
    return 'Needs Work 🔧';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Financial Health Score')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _compute,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Score circle
                  Center(
                    child: Container(
                      width: 160, height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(
                          startAngle: -1.5708,
                          endAngle: -1.5708 + (6.2832 * _score / 100),
                          colors: [_scoreColor(_score), _scoreColor(_score).withOpacity(0.3)],
                        ),
                        boxShadow: [BoxShadow(color: _scoreColor(_score).withOpacity(0.3), blurRadius: 24, spreadRadius: 4)],
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).scaffoldBackgroundColor),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('$_score', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: _scoreColor(_score))),
                          Text(_scoreLabel(_score), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
                  const SizedBox(height: 24),

                  // Component breakdown
                  const Text('Score Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  ..._components.entries.map((e) => _ComponentRow(name: e.key, comp: e.value)).toList(),

                  // Insights
                  if (_insights.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text('💡 Insights', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    ..._insights.asMap().entries.map((e) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
                      ),
                      child: Text(e.value, style: const TextStyle(fontSize: 13)),
                    ).animate().fadeIn(delay: (e.key * 80).ms)),
                  ],
                ],
              ),
            ),
    );
  }
}

class _ScoreComponent {
  final int score;
  final int max;
  final String emoji;
  final String description;
  _ScoreComponent(this.score, this.max, this.emoji, this.description);
}

class _ComponentRow extends StatelessWidget {
  final String name;
  final _ScoreComponent comp;
  const _ComponentRow({required this.name, required this.comp});

  @override
  Widget build(BuildContext context) {
    final pct = comp.max > 0 ? comp.score / comp.max : 0.0;
    final color = pct >= 0.8 ? AppColors.income : pct >= 0.5 ? AppColors.warning : AppColors.expense;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(comp.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          Text('${comp.score}/${comp.max}', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        ]),
        const SizedBox(height: 6),
        Text(comp.description, style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: pct, minHeight: 6, backgroundColor: color.withOpacity(0.1), valueColor: AlwaysStoppedAnimation(color)),
        ),
      ]),
    );
  }
}
