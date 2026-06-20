import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/db/database_helper.dart';
import '../../core/models/models.dart';
import '../../core/models/transaction_model.dart';
import '../../widgets/shared/insights_carousel.dart';
import '../../core/providers/refresh_provider.dart';

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
             a.name as account_name
      FROM transactions t
      LEFT JOIN categories c ON t.category_id = c.id
      LEFT JOIN accounts a ON t.account_id = a.id
      ORDER BY t.date DESC LIMIT 20
    ''');
    final monthTx = await db.rawQuery(
      'SELECT type, SUM(amount) as total FROM transactions WHERE date >= ? GROUP BY type',
      [startOfMonth],
    );

    double income = 0, expense = 0;
    for (final row in monthTx) {
      if (row['type'] == 'INCOME') income = (row['total'] as num).toDouble();
      if (row['type'] == 'EXPENSE') expense = (row['total'] as num).toDouble();
    }

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

    if (mounted) {
      setState(() {
        _accounts = accountMaps.map(AccountModel.fromMap).toList();
        _recentTx = txMaps.map(TransactionModel.fromMap).toList();
        _upcomingSubs = upcoming;
        _monthIncome = income;
        _monthExpense = expense;
        _loading = false;
      });
    }
  }

  double get _totalBalance => _accounts.fold(0, (sum, a) => sum + a.balance);

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(transactionUpdateProvider, (previous, next) {
      _loadData();
    });
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.primary,
        child: CustomScrollView(
          slivers: [
            _buildAppBar(),
            if (_loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else ...[
              SliverToBoxAdapter(child: _buildBalanceCard()),
              SliverToBoxAdapter(child: _buildIncomeExpenseRow()),
              SliverToBoxAdapter(child: _buildUpcomingSubsAlerts()),
              const SliverToBoxAdapter(child: InsightsCarousel()),
              SliverToBoxAdapter(child: _buildQuickActions()),
              SliverToBoxAdapter(child: _buildMonthlyChart()),
              SliverToBoxAdapter(child: _buildAccountsRow()),
              SliverToBoxAdapter(child: _buildCreditCardsRow()),
              SliverToBoxAdapter(child: _buildRecentHeader()),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _TxListItem(tx: _recentTx[i]).animate().fadeIn(delay: (i * 50).ms),
                  childCount: _recentTx.length,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ],
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      floating: true,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('Orbit'),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.auto_awesome, color: AppColors.income),
          onPressed: () => Navigator.pushNamed(context, '/copilot'),
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () => Navigator.pushNamed(context, '/settings'),
        ),
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => Navigator.pushNamed(context, '/transactions'),
        ),
      ],
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Balance', style: TextStyle(color: Colors.white70, fontSize: 14)),
              GestureDetector(
                onTap: () => setState(() => _balanceVisible = !_balanceVisible),
                child: Icon(_balanceVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: Colors.white70, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _balanceVisible ? CurrencyFormatter.format(_totalBalance) : '₹ ••••••',
            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormatter.formatMonth(DateTime.now()),
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1);
  }

  Widget _buildIncomeExpenseRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(child: _SummaryCard(
            label: 'Income', amount: _monthIncome,
            icon: Icons.arrow_downward_rounded, color: AppColors.income,
          )),
          const SizedBox(width: 12),
          Expanded(child: _SummaryCard(
            label: 'Expenses', amount: _monthExpense,
            icon: Icons.arrow_upward_rounded, color: AppColors.expense,
          )),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildUpcomingSubsAlerts() {
    if (_upcomingSubs.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.notification_important_rounded, color: AppColors.expense, size: 18),
              SizedBox(width: 6),
              Text(
                'Action Required',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.expense),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._upcomingSubs.map((sub) {
            final billingMidnight = DateTime(sub.nextBillingDate.year, sub.nextBillingDate.month, sub.nextBillingDate.day);
            final today = DateTime.now();
            final todayMidnight = DateTime(today.year, today.month, today.day);
            final days = billingMidnight.difference(todayMidnight).inDays;

            final String daysText = days == 0
                ? 'billing today'
                : days == 1
                    ? '1 day left'
                    : '$days days left';

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.expense.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.expense.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Text(
                    sub.icon,
                    style: const TextStyle(fontSize: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sub.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          '₹${sub.amount.toStringAsFixed(0)} • $daysText',
                          style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/subscriptions');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.expense,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Pay Now', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    ).animate().fadeIn(delay: 150.ms);
  }

  Widget _buildQuickActions() {
    final actions = [
      {'icon': Icons.map_outlined, 'label': 'Trips', 'route': '/trips'},
      {'icon': Icons.flag_outlined, 'label': 'Goals', 'route': '/goals'},
      {'icon': Icons.donut_large_rounded, 'label': 'Bifurcation', 'route': '/bifurcation'},
      {'icon': Icons.loop, 'label': 'Subs', 'route': '/subscriptions'},
      {'icon': Icons.pie_chart_outline, 'label': 'Net Worth', 'route': '/net-worth'},
      {'icon': Icons.favorite_border, 'label': 'Health', 'route': '/health-score'},
    ];
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        itemCount: actions.length,
        itemBuilder: (_, i) {
          final a = actions[i];
          return GestureDetector(
            onTap: () => Navigator.pushNamed(context, a['route'] as String),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withOpacity(0.15)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(a['icon'] as IconData, color: AppColors.primary, size: 24),
                  const SizedBox(height: 4),
                  Text(a['label'] as String, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.primary)),
                ],
              ),
            ),
          ).animate().fadeIn(delay: (i * 60).ms);
        },
      ),
    );
  }

  Widget _buildMonthlyChart() {
    final hasData = _monthIncome > 0 || _monthExpense > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This Month', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 16),
          if (!hasData)
            const SizedBox(
              height: 120,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bar_chart_outlined, color: Colors.grey, size: 36),
                    SizedBox(height: 8),
                    Text(
                      'No transactions logged this month',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 120,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.center,
                  maxY: (_monthIncome > _monthExpense ? _monthIncome : _monthExpense) * 1.2,
                  barGroups: [
                    BarChartGroupData(x: 0, barRods: [
                      BarChartRodData(toY: _monthIncome, color: AppColors.income, width: 40, borderRadius: BorderRadius.circular(8)),
                    ]),
                    BarChartGroupData(x: 1, barRods: [
                      BarChartRodData(toY: _monthExpense, color: AppColors.expense, width: 40, borderRadius: BorderRadius.circular(8)),
                    ]),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) => Text(v == 0 ? 'Income' : 'Expense', style: const TextStyle(fontSize: 11)),
                    )),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildAccountsRow() {
    final nonCcAccounts = _accounts.where((a) => a.type != 'CREDIT_CARD').toList();
    if (nonCcAccounts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Accounts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              TextButton(onPressed: () => Navigator.pushNamed(context, '/accounts'),
                  child: const Text('See all', style: TextStyle(color: AppColors.primary))),
            ],
          ),
        ),
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: nonCcAccounts.length,
            itemBuilder: (_, i) {
              final a = nonCcAccounts[i];
              return Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(14),
                width: 150,
                decoration: BoxDecoration(
                  color: Color(a.color).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Color(a.color).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(a.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    Text(
                      CurrencyFormatter.formatCompact(a.balance),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(a.color)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCreditCardsRow() {
    final ccAccounts = _accounts.where((a) => a.type == 'CREDIT_CARD').toList();
    if (ccAccounts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Credit Cards', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: ccAccounts.length,
            itemBuilder: (_, i) {
              final a = ccAccounts[i];
              final outstanding = a.balance < 0 ? a.balance.abs() : 0.0;
              final limit = a.creditLimit ?? 0.0;
              final available = limit + a.balance;
              final usagePercent = limit > 0 ? (outstanding / limit).clamp(0.0, 1.0) : 0.0;

              return Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(14),
                width: 200,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(a.color), Color(a.color).withRed(100).withGreen(100)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Color(a.color).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            a.name,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.credit_card, color: Colors.white70, size: 16),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Outstanding: ₹${outstanding.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        if (limit > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Available: ₹${available.toStringAsFixed(0)} / ₹${limit.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 10, color: Colors.white70),
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: usagePercent,
                              minHeight: 4,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecentHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Recent Transactions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/transactions'),
            child: const Text('See all', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final double amount;
  final IconData icon;
  final Color color;

  const _SummaryCard({required this.label, required this.amount, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
                Text(CurrencyFormatter.formatCompact(amount),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
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
    final color = isExpense ? AppColors.expense : AppColors.income;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: (tx.categoryColor != null ? Color(tx.categoryColor!) : AppColors.primary).withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(child: Text(
          _categoryEmoji(tx.categoryId ?? '', tx.categoryIcon),
          style: const TextStyle(fontSize: 20),
        )),
      ),
      title: Text(tx.categoryName ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(
        '${tx.note ?? tx.accountName ?? ''} · ${DateFormatter.relativeDate(tx.date)}',
        style: const TextStyle(fontSize: 12),
        maxLines: 1, overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '${isExpense ? '-' : '+'}${CurrencyFormatter.formatCompact(tx.amount)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15),
      ),
    );
  }

  String _categoryEmoji(String id, String? customIcon) {
    if (customIcon != null && customIcon.isNotEmpty) return customIcon;
    const map = {
      'cat_food': '🍕', 'cat_grocery': '🛒', 'cat_transport': '🚗',
      'cat_shopping': '🛍️', 'cat_entertainment': '🎬', 'cat_health': '💊',
      'cat_utilities': '⚡', 'cat_telecom': '📱', 'cat_education': '🎓',
      'cat_subscription': '🔄', 'cat_salary': '💰', 'cat_freelance': '💻',
      'cat_investment': '📈', 'cat_gift': '🎁',
    };
    return map[id] ?? '💸';
  }
}
