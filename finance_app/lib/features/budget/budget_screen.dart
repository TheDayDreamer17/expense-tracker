import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/db/database_helper.dart';
import '../../core/models/models.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/services/ai_service.dart';
import 'package:uuid/uuid.dart';
import '../../core/providers/refresh_provider.dart';

class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({super.key});
  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  List<BudgetModel> _budgets = [];
  bool _loading = true;
  DateTime _selectedMonth = DateTime.now();
  String? _prediction;
  bool _loadingPrediction = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final rows = await db.rawQuery('''
      SELECT b.*, c.name as category_name, c.icon as category_icon, c.color as category_color,
        COALESCE((
          SELECT SUM(t.amount) FROM transactions t
          WHERE t.category_id = b.category_id
            AND t.type = 'EXPENSE'
            AND strftime('%m', datetime(t.date/1000, 'unixepoch')) = printf('%02d', b.month)
            AND strftime('%Y', datetime(t.date/1000, 'unixepoch')) = CAST(b.year AS TEXT)
        ), 0) as spent
      FROM budgets b
      LEFT JOIN categories c ON b.category_id = c.id
      WHERE b.month = ? AND b.year = ?
      ORDER BY c.name
    ''', [_selectedMonth.month, _selectedMonth.year]);

    if (mounted) {
      setState(() {
        _budgets = rows.map(BudgetModel.fromMap).toList();
        _loading = false;
        _prediction = null;
      });

      if (_selectedMonth.month == DateTime.now().month &&
          _selectedMonth.year == DateTime.now().year &&
          _totalBudget > 0) {
        setState(() => _loadingPrediction = true);
        final res = await ref
            .read(aiServiceProvider)
            .getPredictiveBudget(_totalBudget, _totalSpent);
        if (mounted)
          setState(() {
            _prediction = res;
            _loadingPrediction = false;
          });
      }
    }
  }

  double get _totalBudget => _budgets.fold(0, (s, b) => s + b.amount);
  double get _totalSpent => _budgets.fold(0, (s, b) => s + (b.spent ?? 0));

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(transactionUpdateProvider, (previous, next) {
      _load();
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget'),
        actions: [
          IconButton(
              icon: const Icon(Icons.add), onPressed: _showAddBudgetSheet)
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildMonthSelector(),
                  const SizedBox(height: 16),
                  if (_budgets.isNotEmpty) ...[
                    _buildSummaryCard(),
                    if (_loadingPrediction || _prediction != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.income.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.income.withOpacity(0.3)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.auto_awesome,
                              color: AppColors.income, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _loadingPrediction
                                ? const Text(
                                    'AI is analyzing your spending pace...',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic))
                                : Text(_prediction!,
                                    style: const TextStyle(fontSize: 12)),
                          ),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildPieChart(),
                    const SizedBox(height: 20),
                  ],
                  const Text('Category Budgets',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  if (_budgets.isEmpty)
                    Center(
                      child: Column(
                        children: [
                          const SizedBox(height: 40),
                          const Text('🎯', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 12),
                          const Text('No budgets set',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          const Text('Tap + to add a budget for a category',
                              style: TextStyle(
                                  color: AppColors.lightTextSecondary)),
                        ],
                      ),
                    )
                  else
                    ..._budgets.asMap().entries.map((e) => _BudgetProgressCard(
                            budget: e.value,
                            onEdit: () => _showEditSheet(e.value))
                        .animate()
                        .fadeIn(delay: (e.key * 60).ms)),
                ],
              ),
            ),
    );
  }

  Widget _buildMonthSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () {
            setState(() => _selectedMonth =
                DateTime(_selectedMonth.year, _selectedMonth.month - 1));
            _load();
          },
        ),
        Text(DateFormatter.formatMonth(_selectedMonth),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () {
            setState(() => _selectedMonth =
                DateTime(_selectedMonth.year, _selectedMonth.month + 1));
            _load();
          },
        ),
      ],
    );
  }

  Widget _buildSummaryCard() {
    final usagePct =
        _totalBudget > 0 ? (_totalSpent / _totalBudget).clamp(0.0, 1.0) : 0.0;
    final color = usagePct < 0.8
        ? AppColors.income
        : usagePct < 1.0
            ? AppColors.warning
            : AppColors.expense;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withOpacity(0.8), color]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Budget',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              Text('${(usagePct * 100).toInt()}% used',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Text(CurrencyFormatter.format(_totalSpent),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700)),
          Text('of ${CurrencyFormatter.format(_totalBudget)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: usagePct,
              backgroundColor: Colors.white30,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPieChart() {
    if (_budgets.isEmpty) return const SizedBox();
    return SizedBox(
      height: 200,
      child: PieChart(PieChartData(
        sections: _budgets.map((b) {
          final color = b.categoryColor != null
              ? Color(b.categoryColor!)
              : AppColors.primary;
          return PieChartSectionData(
            value: b.spent ?? 0,
            color: color,
            title: b.categoryName ?? '',
            radius: 70,
            titleStyle: const TextStyle(
                fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
          );
        }).toList(),
        centerSpaceRadius: 40,
        sectionsSpace: 2,
      )),
    );
  }

  void _showAddBudgetSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetFormSheet(month: _selectedMonth, onSaved: _load),
    );
  }

  void _showEditSheet(BudgetModel budget) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetFormSheet(
          month: _selectedMonth, existing: budget, onSaved: _load),
    );
  }
}

class _BudgetProgressCard extends StatelessWidget {
  final BudgetModel budget;
  final VoidCallback onEdit;
  const _BudgetProgressCard({required this.budget, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final usage = budget.usagePercent.clamp(0.0, 1.0);
    final color = usage < 0.8
        ? AppColors.income
        : usage < 1.0
            ? AppColors.warning
            : AppColors.expense;
    final catColor = budget.categoryColor != null
        ? Color(budget.categoryColor!)
        : AppColors.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: catColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Center(
                      child: Text(_emoji(budget.categoryIcon ?? ''),
                          style: const TextStyle(fontSize: 20))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(budget.categoryName ?? 'Category',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        '${CurrencyFormatter.formatCompact(budget.spent ?? 0)} / ${CurrencyFormatter.formatCompact(budget.amount)}',
                        style: TextStyle(fontSize: 12, color: color),
                      ),
                    ],
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: onEdit),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: usage,
                backgroundColor: color.withOpacity(0.15),
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${(usage * 100).toInt()}% used',
                    style: TextStyle(fontSize: 11, color: color)),
                Text(
                    budget.remaining >= 0
                        ? '${CurrencyFormatter.formatCompact(budget.remaining)} left'
                        : '${CurrencyFormatter.formatCompact(budget.remaining.abs())} over',
                    style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _emoji(String icon) {
    const map = {
      'food': '🍕',
      'cart': '🛒',
      'car': '🚗',
      'bag': '🛍️',
      'tv': '🎬',
      'heart': '💊',
      'flash': '⚡',
      'mobile': '📱',
      'book': '🎓',
      'refresh': '🔄'
    };
    return map[icon] ?? '💸';
  }
}

class _BudgetFormSheet extends StatefulWidget {
  final DateTime month;
  final BudgetModel? existing;
  final VoidCallback onSaved;
  const _BudgetFormSheet(
      {required this.month, this.existing, required this.onSaved});

  @override
  State<_BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends State<_BudgetFormSheet> {
  final _amountCtrl = TextEditingController();
  String? _selectedCategoryId;
  List<CategoryModel> _categories = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    if (widget.existing != null) {
      _amountCtrl.text = widget.existing!.amount.toStringAsFixed(2);
      _selectedCategoryId = widget.existing!.categoryId;
    }
  }

  Future<void> _loadCategories() async {
    final rows = await DatabaseHelper.instance.query('categories',
        where: 'type = ?', whereArgs: ['EXPENSE'], orderBy: 'name');
    if (mounted)
      setState(() => _categories = rows.map(CategoryModel.fromMap).toList());
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text(widget.existing == null ? 'Set Budget' : 'Edit Budget',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _selectedCategoryId,
            decoration: const InputDecoration(
                labelText: 'Category', prefixIcon: Icon(Icons.category)),
            items: _categories
                .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                .toList(),
            onChanged: (v) => setState(() => _selectedCategoryId = v),
          ),
          const SizedBox(height: 12),
          TextField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                  labelText: 'Monthly Budget', prefixText: '₹ '),
              keyboardType: TextInputType.number),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: Text(widget.existing == null ? 'Set Budget' : 'Update'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_selectedCategoryId == null || _amountCtrl.text.isEmpty) return;
    setState(() => _saving = true);
    final db = DatabaseHelper.instance;
    await db.insert('budgets', {
      'id': widget.existing?.id ?? const Uuid().v4(),
      'category_id': _selectedCategoryId,
      'month': widget.month.month,
      'year': widget.month.year,
      'amount': double.tryParse(_amountCtrl.text) ?? 0,
    });
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }
}
