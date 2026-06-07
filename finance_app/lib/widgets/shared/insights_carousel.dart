import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/db/database_helper.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/providers/refresh_provider.dart';

class InsightsCarousel extends ConsumerStatefulWidget {
  const InsightsCarousel({super.key});

  @override
  ConsumerState<InsightsCarousel> createState() => _InsightsCarouselState();
}

class _InsightsCarouselState extends ConsumerState<InsightsCarousel> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _timer;
  bool _loading = true;

  // Stats
  double _income = 0;
  double _expense = 0;
  List<Map<String, dynamic>> _topMerchants = [];
  Map<String, dynamic>? _frequencyInsight;
  List<Map<String, dynamic>> _budgetAlerts = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
    _startAutoScroll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted && _pageController.hasClients) {
        final nextPage = (_currentPage + 1) % 4;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  Future<void> _loadStats() async {
    try {
      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
      final endOfMonth = DateTime(now.year, now.month + 1, 1).millisecondsSinceEpoch;

      // 1. Monthly Overview
      final overviewRows = await db.rawQuery('''
        SELECT type, SUM(amount) as total FROM transactions
        WHERE date >= ? AND date < ?
        GROUP BY type
      ''', [startOfMonth, endOfMonth]);

      double income = 0;
      double expense = 0;
      for (final r in overviewRows) {
        if (r['type'] == 'INCOME') {
          income = (r['total'] as num).toDouble();
        } else if (r['type'] == 'EXPENSE') {
          expense = (r['total'] as num).toDouble();
        }
      }

      // 2. Top Merchants
      final merchantRows = await db.rawQuery('''
        SELECT note, SUM(amount) as total FROM transactions
        WHERE type = 'EXPENSE' AND note IS NOT NULL AND note != '' AND date >= ? AND date < ?
        GROUP BY note
        ORDER BY total DESC
        LIMIT 3
      ''', [startOfMonth, endOfMonth]);

      List<Map<String, dynamic>> topMerchants = merchantRows.map((r) => {
        'name': r['note'] as String,
        'total': (r['total'] as num).toDouble(),
      }).toList();

      // 3. Frequency / Avg Spend
      final freqRows = await db.rawQuery('''
        SELECT note, COUNT(*) as cnt, AVG(amount) as avg_amt FROM transactions
        WHERE type = 'EXPENSE' AND note IS NOT NULL AND note != '' AND date >= ? AND date < ?
        GROUP BY note
        ORDER BY cnt DESC
        LIMIT 1
      ''', [startOfMonth, endOfMonth]);

      Map<String, dynamic>? frequencyInsight;
      if (freqRows.isNotEmpty) {
        frequencyInsight = {
          'name': freqRows.first['note'] as String,
          'count': freqRows.first['cnt'] as int,
          'avg': (freqRows.first['avg_amt'] as num).toDouble(),
        };
      }

      // 4. Budget Alerts
      final budgetRows = await db.rawQuery('''
        SELECT b.amount as limit_amount, c.name as category_name, c.icon as category_icon,
               (SELECT SUM(amount) FROM transactions WHERE category_id = b.category_id AND type = 'EXPENSE' AND date >= ? AND date < ?) as spent
        FROM budgets b
        JOIN categories c ON b.category_id = c.id
        WHERE b.month = ? AND b.year = ?
      ''', [startOfMonth, endOfMonth, now.month, now.year]);

      List<Map<String, dynamic>> budgetAlerts = [];
      for (final r in budgetRows) {
        final limitAmt = (r['limit_amount'] as num).toDouble();
        final spentAmt = (r['spent'] as num?)?.toDouble() ?? 0.0;
        final usage = limitAmt > 0 ? (spentAmt / limitAmt) : 0.0;
        budgetAlerts.add({
          'category_name': r['category_name'] as String,
          'category_icon': r['category_icon'] as String?,
          'limit': limitAmt,
          'spent': spentAmt,
          'usage': usage,
        });
      }
      budgetAlerts.sort((a, b) => (b['usage'] as double).compareTo(a['usage'] as double));
      if (budgetAlerts.length > 3) {
        budgetAlerts = budgetAlerts.sublist(0, 3);
      }

      if (mounted) {
        setState(() {
          _income = income;
          _expense = expense;
          _topMerchants = topMerchants;
          _frequencyInsight = frequencyInsight;
          _budgetAlerts = budgetAlerts;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading carousel stats: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(transactionUpdateProvider, (previous, next) {
      _loadStats();
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return Container(
        height: 170,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      height: 180,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (page) {
                setState(() {
                  _currentPage = page;
                });
                _startAutoScroll(); // restart scroll timer on manual swipe
              },
              children: [
                _buildOverviewSlide(),
                _buildMerchantsSlide(),
                _buildFrequencySlide(),
                _buildBudgetsSlide(),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              final isSelected = index == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: isSelected ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? Colors.white24 : Colors.black12),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewSlide() {
    final net = _income - _expense;
    final pct = _income > 0 ? (_expense / _income).clamp(0.0, 1.0) : 0.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _SlideCard(
      title: 'Monthly Overview',
      subtitle: 'Spent vs Income',
      icon: Icons.pie_chart_outline_rounded,
      onTap: () {
        ref.read(currentTabProvider.notifier).state = 1;
        ref.read(reportsSubTabProvider.notifier).state = 'OVERVIEW';
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Spent / Income', style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
                    Text(
                      '${(_expense / (_income > 0 ? _income : 1) * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation(
                      _expense > _income ? AppColors.expense : AppColors.primary,
                    ),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Spent', style: TextStyle(fontSize: 10, color: AppColors.lightTextSecondary)),
                        Text(
                          CurrencyFormatter.formatCompact(_expense),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.expense),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Income', style: TextStyle(fontSize: 10, color: AppColors.lightTextSecondary)),
                        Text(
                          CurrencyFormatter.formatCompact(_income),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.income),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Net Savings', style: TextStyle(fontSize: 10, color: AppColors.lightTextSecondary)),
                        Text(
                          CurrencyFormatter.formatCompact(net),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: net >= 0 ? AppColors.income : AppColors.expense,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMerchantsSlide() {
    return _SlideCard(
      title: 'Top Merchants',
      subtitle: 'Highest spending this month',
      icon: Icons.storefront_rounded,
      onTap: () {
        ref.read(currentTabProvider.notifier).state = 1;
        ref.read(reportsSubTabProvider.notifier).state = 'MERCHANTS';
      },
      child: _topMerchants.isEmpty
          ? const Center(
              child: Text(
                'No merchant expenses recorded yet',
                style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _topMerchants.map((m) {
                final pct = _expense > 0 ? (m['total'] / _expense).clamp(0.0, 1.0) : 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          m['name'],
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: pct,
                            backgroundColor: Colors.teal.withOpacity(0.08),
                            valueColor: AlwaysStoppedAnimation(Colors.teal.shade300),
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            CurrencyFormatter.formatCompact(m['total']),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildFrequencySlide() {
    return _SlideCard(
      title: 'Spend Frequency',
      subtitle: 'Most visited merchant',
      icon: Icons.repeat_rounded,
      onTap: () {
        ref.read(currentTabProvider.notifier).state = 2; // Copilot Screen
      },
      child: _frequencyInsight == null
          ? const Center(
              child: Text(
                'Add merchant names in notes to get insights',
                style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.flash_on_rounded, color: Colors.orange, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _frequencyInsight!['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Visited ${_frequencyInsight!['count']} times this month',
                            style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Average transaction cost:',
                      style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                    ),
                    Text(
                      CurrencyFormatter.format(_frequencyInsight!['avg']),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildBudgetsSlide() {
    final activeAlerts = _budgetAlerts.where((b) => b['usage'] >= 0.8).toList();

    return _SlideCard(
      title: 'Budget Thresholds',
      subtitle: activeAlerts.isEmpty ? 'All budgets within limits' : 'Highest budget utilization',
      icon: Icons.warning_amber_rounded,
      iconColor: activeAlerts.isEmpty ? AppColors.success : Colors.orange,
      onTap: () {
        ref.read(currentTabProvider.notifier).state = 3; // Budget Screen
      },
      child: _budgetAlerts.isEmpty
          ? const Center(
              child: Text(
                'Set custom limits on categories to monitor budgets',
                style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _budgetAlerts.map((b) {
                final isWarning = b['usage'] >= 0.8;
                final barColor = isWarning
                    ? (b['usage'] >= 1.0 ? AppColors.expense : Colors.orange)
                    : AppColors.success;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${b['category_icon'] ?? '❓'} ${b['category_name']}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '${CurrencyFormatter.formatCompact(b['spent'])} / ${CurrencyFormatter.formatCompact(b['limit'])} (${(b['usage'] * 100).toStringAsFixed(0)}%)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isWarning ? barColor : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: (b['usage'] as double).clamp(0.0, 1.0),
                          backgroundColor: barColor.withOpacity(0.08),
                          valueColor: AlwaysStoppedAnimation(barColor),
                          minHeight: 5,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _SlideCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color? iconColor;
  final VoidCallback onTap;
  final Widget child;

  const _SlideCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.iconColor,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : Colors.white;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.12)),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: iconColor ?? AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 10, color: AppColors.lightTextSecondary),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 12,
                  color: AppColors.lightTextSecondary,
                ),
              ],
            ),
            const Divider(height: 16),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
