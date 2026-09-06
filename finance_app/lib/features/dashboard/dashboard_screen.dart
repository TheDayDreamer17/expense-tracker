import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/db/database_helper.dart';
import '../../core/models/models.dart';
import '../../core/models/transaction_model.dart';
import '../../core/providers/refresh_provider.dart';
import '../../core/providers/settings_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _balanceVisible = true;
  List<AccountModel> _accounts = [];
  List<TransactionModel> _recentTx = [];
  List<SubscriptionModel> _upcomingSubs = [];
  double _monthIncome = 0;
  double _monthExpense = 0;
  double _totalBudgetLimit = 30000.0;
  List<FlSpot> _sparklineSpots = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = DatabaseHelper.instance;
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;

    final accountMaps = await db.query('accounts', orderBy: 'created_at ASC');
    
    final txMaps = await db.rawQuery('''
      SELECT t.*, c.name as category_name, c.icon as category_icon, c.color as category_color,
             a.name as account_name, a2.name as to_account_name
      FROM transactions t
      LEFT JOIN categories c ON t.category_id = c.id
      LEFT JOIN accounts a ON t.account_id = a.id
      LEFT JOIN accounts a2 ON t.to_account_id = a2.id
      WHERE t.is_template = 0
      ORDER BY t.date DESC LIMIT 5
    ''');

    final monthTxResult = await db.rawQuery(
      'SELECT type, SUM(amount) as total FROM transactions WHERE date >= ? AND is_template = 0 GROUP BY type',
      [startOfMonth],
    );

    double income = 0, expense = 0;
    for (final row in monthTxResult) {
      if (row['type'] == 'INCOME') income = (row['total'] as num).toDouble();
      if (row['type'] == 'EXPENSE') expense = (row['total'] as num).toDouble();
    }

    // Load active budget limits
    final budgetResult = await db.rawQuery(
      'SELECT SUM(amount) as total FROM budgets WHERE month = ? AND year = ?',
      [now.month, now.year],
    );
    final activeBudget = (budgetResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // Load upcoming subscriptions within 5 days limit
    final subMaps = await db.query('subscriptions');
    final allSubs = subMaps.map(SubscriptionModel.fromMap).toList();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final upcoming = allSubs.where((s) {
      final billingMidnight = DateTime(s.nextBillingDate.year, s.nextBillingDate.month, s.nextBillingDate.day);
      final days = billingMidnight.difference(todayMidnight).inDays;
      return days >= 0 && days <= 5;
    }).toList();

    upcoming.sort((a, b) {
      final billingMidnightA = DateTime(a.nextBillingDate.year, a.nextBillingDate.month, a.nextBillingDate.day);
      final billingMidnightB = DateTime(b.nextBillingDate.year, b.nextBillingDate.month, b.nextBillingDate.day);
      return billingMidnightA.difference(todayMidnight).inDays.compareTo(
        billingMidnightB.difference(todayMidnight).inDays
      );
    });

    // Query daily spending to build cumulative Sparkline
    final trendTxs = await db.rawQuery('''
      SELECT date, amount FROM transactions
      WHERE type = 'EXPENSE' AND date >= ? AND is_template = 0
      ORDER BY date ASC
    ''', [startOfMonth]);

    final Map<int, double> dailySpends = {};
    for (final tx in trendTxs) {
      final txDate = DateTime.fromMillisecondsSinceEpoch(tx['date'] as int);
      dailySpends[txDate.day] = (dailySpends[txDate.day] ?? 0.0) + (tx['amount'] as num).toDouble();
    }

    double cumulative = 0.0;
    final List<FlSpot> spots = [];
    for (int day = 1; day <= now.day; day++) {
      cumulative += dailySpends[day] ?? 0.0;
      spots.add(FlSpot(day.toDouble(), cumulative));
    }

    if (spots.isEmpty) {
      spots.add(const FlSpot(1, 0));
      spots.add(FlSpot(2, 0));
    }

    if (mounted) {
      setState(() {
        _accounts = accountMaps.map(AccountModel.fromMap).toList();
        _recentTx = txMaps.map(TransactionModel.fromMap).toList();
        _upcomingSubs = upcoming;
        _monthIncome = income;
        _monthExpense = expense;
        _totalBudgetLimit = activeBudget > 0 ? activeBudget : 30000.0;
        _sparklineSpots = spots;
        _loading = false;
      });
    }
  }

  double get _totalBalance => _accounts.fold(0, (sum, a) => sum + a.balance);

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(transactionUpdateProvider, (previous, next) {
      _loadData();
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Build Attention items
    final List<Map<String, dynamic>> attentionItems = [];
    final now = DateTime.now();

    // 1. Credit card bills
    for (final card in _accounts.where((a) => a.type == 'CREDIT_CARD')) {
      if (card.balance < 0) {
        final outstanding = card.balance.abs();
        final paymentDay = card.paymentDay ?? 15;
        int daysLeft = paymentDay - now.day;
        if (daysLeft < 0) {
          final nextMonthDate = DateTime(now.year, now.month + 1, paymentDay);
          daysLeft = nextMonthDate.difference(DateTime(now.year, now.month, now.day)).inDays;
        }
        if (daysLeft <= 5) {
          attentionItems.add({
            'title': '${card.name} bill due in $daysLeft day${daysLeft == 1 ? "" : "s"}',
            'detail': CurrencyFormatter.format(outstanding),
            'color': AppColors.expense,
            'route': '/accounts',
          });
        }
      }
    }

    // 2. Subscriptions
    for (final sub in _upcomingSubs) {
      final billingMidnight = DateTime(sub.nextBillingDate.year, sub.nextBillingDate.month, sub.nextBillingDate.day);
      final todayMidnight = DateTime(now.year, now.month, now.day);
      final days = billingMidnight.difference(todayMidnight).inDays;
      final daysText = days == 0
          ? 'billing today'
          : days == 1
              ? 'billing tomorrow'
              : 'billing in $days days';
      attentionItems.add({
        'title': '${sub.name} $daysText',
        'detail': CurrencyFormatter.format(sub.amount),
        'color': days <= 1 ? AppColors.expense : Colors.amber.shade700,
        'route': '/subscriptions',
      });
    }

    // 3. Projected budget overspend
    if (_monthExpense > _totalBudgetLimit) {
      attentionItems.add({
        'title': 'Monthly budget exceeded',
        'detail': CurrencyFormatter.format(_monthExpense - _totalBudgetLimit),
        'color': AppColors.expense,
        'route': '/budget',
      });
    } else {
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final dailyBurn = _monthExpense / (now.day > 0 ? now.day : 1);
      final projectedTotal = _monthExpense + (dailyBurn * (daysInMonth - now.day));
      if (projectedTotal > _totalBudgetLimit) {
        attentionItems.add({
          'title': 'Projected budget overspend warning',
          'detail': '₹${(projectedTotal - _totalBudgetLimit).toStringAsFixed(0)} over',
          'color': Colors.amber.shade700,
          'route': '/budget',
        });
      }
    }

    // 4. Missing API keys
    final settings = ref.watch(settingsProvider);
    if (settings.aiApiKey == null || settings.aiApiKey!.isEmpty) {
      attentionItems.add({
        'title': 'Set up Orbit AI Copilot Key',
        'detail': 'Setup now',
        'color': AppColors.primary,
        'route': '/settings',
      });
    }

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 100),
                children: [
                  // Greeting row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => _showNameDialog(context, settings.userName),
                        child: Text(
                          '$_greeting, ${settings.userName.isNotEmpty ? settings.userName : "Friend"}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.lightTextSecondary),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _showNameDialog(context, settings.userName),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: AppColors.primary.withOpacity(0.08),
                          child: const Icon(Icons.person_outline, color: AppColors.primary, size: 20),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(),
                  const SizedBox(height: 16),

                  // Balance info
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _balanceVisible ? CurrencyFormatter.format(_totalBalance) : '₹ ••••••',
                            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Net available balance',
                            style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(
                          _balanceVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: AppColors.lightTextSecondary,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _balanceVisible = !_balanceVisible),
                      ),
                    ],
                  ).animate().fadeIn(delay: 50.ms),
                  const SizedBox(height: 20),

                  // Safe Spend progress bar card
                  _buildSafeSpendCard().animate().fadeIn(delay: 100.ms),
                  const SizedBox(height: 24),

                  // Needs attention section
                  if (attentionItems.isNotEmpty) ...[
                    _buildNeedsAttentionSection(attentionItems).animate().fadeIn(delay: 150.ms),
                    const SizedBox(height: 24),
                  ],

                  // This Month Cumulative Sparkline Section
                  _buildThisMonthSection().animate().fadeIn(delay: 200.ms),
                  const SizedBox(height: 24),

                  // Recent activity activity
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recent activity',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      TextButton(
                        onPressed: () => ref.read(currentTabProvider.notifier).state = 1,
                        child: const Text('See all', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ).animate().fadeIn(delay: 250.ms),
                  const SizedBox(height: 8),

                  if (_recentTx.isEmpty)
                    _buildEmptyState()
                  else
                    Column(
                      children: _recentTx.asMap().entries.map((e) {
                        return _TxListItem(tx: e.value).animate().fadeIn(delay: (e.key * 50).ms);
                      }).toList(),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildSafeSpendCard() {
    final spent = _monthExpense;
    final limit = _totalBudgetLimit;
    final usagePercent = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;
    
    final Color progressColor = usagePercent >= 1.0
        ? AppColors.expense
        : usagePercent >= 0.8
            ? Colors.amber.shade700
            : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: progressColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: progressColor.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Spending: ${CurrencyFormatter.format(spent)} / ${CurrencyFormatter.format(limit)}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: progressColor),
              ),
              Text(
                '${(usagePercent * 100).toInt()}%',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: progressColor),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: usagePercent,
              minHeight: 6,
              backgroundColor: progressColor.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNeedsAttentionSection(List<Map<String, dynamic>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Needs attention',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ...items.take(3).map((item) {
          final color = item['color'] as Color;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.1)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: Text(
                item['title'] as String,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item['detail'] as String,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 16, color: color),
                ],
              ),
              onTap: () => Navigator.pushNamed(context, item['route'] as String),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildThisMonthSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chartBg = isDark ? AppColors.darkCard : Colors.grey.shade50;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: chartBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This month trend',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Income', style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                  Text(CurrencyFormatter.format(_monthIncome), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.success)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Spent', style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                  Text(CurrencyFormatter.format(_monthExpense), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.expense)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Cumulative Line Sparkline Chart
          SizedBox(
            height: 60,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(
                  show: false,
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minX: 1,
                maxX: DateTime.now().day.toDouble(),
                lineBarsData: [
                  LineChartBarData(
                    spots: _sparklineSpots,
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primary.withOpacity(0.05),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.08)),
      ),
      child: Center(
        child: Column(
          children: [
            const Text('🌱', style: TextStyle(fontSize: 32)),
            const SizedBox(height: 8),
            const Text(
              'No spending logged yet',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap the add button to log your first transaction today.',
              style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/add-transaction'),
              child: const Text('Add transaction'),
            ),
          ],
        ),
      ),
    );
  }

  void _showNameDialog(BuildContext context, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('What is your name?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter your name',
            labelText: 'Your Name',
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(settingsProvider.notifier).setUserName(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _TxListItem extends StatelessWidget {
  final TransactionModel tx;
  const _TxListItem({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isExpense = tx.isExpense;
    final isIncome = tx.isIncome;
    final amountColor = isExpense
        ? AppColors.expense
        : isIncome
            ? AppColors.success
            : AppColors.lightTextSecondary;

    final dateStr = DateFormatter.relativeDate(tx.date);
    final timeStr = DateFormatter.formatTime(tx.date);
    
    final displayAccount = tx.isTransfer && tx.toAccountName != null
        ? '${tx.accountName} ➔ ${tx.toAccountName}'
        : tx.accountName;

    final subtitleSegments = [
      tx.isTransfer ? 'Transfer' : tx.categoryName,
      displayAccount,
      '$dateStr, $timeStr',
    ];
    final detailText = subtitleSegments.where((s) => s != null && s.isNotEmpty).join(' · ');

    final colorHex = tx.categoryColor ?? AppColors.primary.value;
    final Color catColor = Color(colorHex);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.08)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: catColor.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              _categoryEmoji(tx.categoryId ?? '', tx.categoryIcon),
              style: const TextStyle(fontSize: 20),
            ),
          ),
        ),
        title: Text(
          tx.note ?? tx.categoryName ?? 'Unknown',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            detailText,
            style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tx.isSmsImported) ...[
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'SMS',
                  style: TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
            Text(
              '${isExpense ? '−' : isIncome ? '+' : ''}${CurrencyFormatter.format(tx.amount)}',
              style: TextStyle(color: amountColor, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryEmoji(String id, String? customIcon) {
    if (customIcon != null && customIcon.isNotEmpty) return customIcon;
    const map = {
      'cat_food': '🍔',
      'cat_grocery': '🛒',
      'cat_transport': '🚗',
      'cat_shopping': '🛍️',
      'cat_entertainment': '🎬',
      'cat_health': '💊',
      'cat_utilities': '⚡',
      'cat_telecom': '📱',
      'cat_education': '🎓',
      'cat_subscription': '🔄',
      'cat_salary': '💰',
      'cat_freelance': '💻',
      'cat_investment': '📈',
      'cat_gift': '🎁',
    };
    return map[id] ?? '💸';
  }
}
