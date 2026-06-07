import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/db/database_helper.dart';
import '../../core/models/transaction_model.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'add_transaction_screen.dart';
import '../../core/providers/refresh_provider.dart';

class TransactionListScreen extends ConsumerStatefulWidget {
  const TransactionListScreen({super.key});
  @override
  ConsumerState<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends ConsumerState<TransactionListScreen> {
  List<TransactionModel> _all = [];
  List<TransactionModel> _filtered = [];
  bool _loading = true;

  // Filters
  final _searchCtrl = TextEditingController();
  String _typeFilter = 'ALL';       // ALL | INCOME | EXPENSE | TRANSFER
  String? _categoryFilter;
  DateTimeRange? _dateRange;
  String? _accountFilter;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.rawQuery('''
      SELECT t.*, c.name as category_name, c.icon as category_icon, c.color as category_color,
             a.name as account_name
      FROM transactions t
      LEFT JOIN categories c ON t.category_id = c.id
      LEFT JOIN accounts a ON t.account_id = a.id
      ORDER BY t.date DESC
    ''');
    if (mounted) {
      setState(() {
        _all = rows.map(TransactionModel.fromMap).toList();
        _loading = false;
      });
      _applyFilters();
    }
  }

  void _applyFilters() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _all.where((t) {
        if (_typeFilter != 'ALL' && t.type != _typeFilter) return false;
        if (_categoryFilter != null && t.categoryId != _categoryFilter) return false;
        if (_accountFilter != null && t.accountId != _accountFilter) return false;
        if (_dateRange != null) {
          if (t.date.isBefore(_dateRange!.start) || t.date.isAfter(_dateRange!.end)) return false;
        }
        if (q.isNotEmpty) {
          final matchNote = t.note?.toLowerCase().contains(q) ?? false;
          final matchCat  = t.categoryName?.toLowerCase().contains(q) ?? false;
          final matchAcc  = t.accountName?.toLowerCase().contains(q) ?? false;
          final matchAmt  = t.amount.toString().contains(q);
          return matchNote || matchCat || matchAcc || matchAmt;
        }
        return true;
      }).toList();
    });
  }

  // Group by date
  Map<String, List<TransactionModel>> get _grouped {
    final map = <String, List<TransactionModel>>{};
    for (final t in _filtered) {
      final key = DateFormatter.relativeDate(t.date);
      map.putIfAbsent(key, () => []).add(t);
    }
    return map;
  }

  double get _filteredTotal => _filtered.fold(0, (s, t) => t.isExpense ? s - t.amount : t.isIncome ? s + t.amount : s);

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(transactionUpdateProvider, (previous, next) {
      _load();
    });
    final grouped = _grouped;
    final keys = grouped.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search by category, note, amount...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchCtrl.clear(); _applyFilters(); })
                    : null,
              ),
            ),
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.filter_list), onPressed: _showFilterSheet),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Type chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(children: [
                    _TypeChip(label: 'All', value: 'ALL', current: _typeFilter, onTap: (v) { setState(() => _typeFilter = v); _applyFilters(); }),
                    const SizedBox(width: 8),
                    _TypeChip(label: '🔴 Expense', value: 'EXPENSE', current: _typeFilter, color: AppColors.expense, onTap: (v) { setState(() => _typeFilter = v); _applyFilters(); }),
                    const SizedBox(width: 8),
                    _TypeChip(label: '🟢 Income', value: 'INCOME', current: _typeFilter, color: AppColors.income, onTap: (v) { setState(() => _typeFilter = v); _applyFilters(); }),
                    const SizedBox(width: 8),
                    _TypeChip(label: '🔵 Transfer', value: 'TRANSFER', current: _typeFilter, color: AppColors.transfer, onTap: (v) { setState(() => _typeFilter = v); _applyFilters(); }),
                  ]),
                ),

                // Summary bar
                if (_filtered.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(children: [
                      Text('${_filtered.length} transactions', style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
                      const Spacer(),
                      Text(
                        'Net: ${_filteredTotal >= 0 ? '+' : ''}${CurrencyFormatter.formatCompact(_filteredTotal)}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                            color: _filteredTotal >= 0 ? AppColors.income : AppColors.expense),
                      ),
                    ]),
                  ),

                if (_filtered.isEmpty)
                  const Expanded(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('🔍', style: TextStyle(fontSize: 48)),
                    SizedBox(height: 12),
                    Text('No transactions found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ])))
                else
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 100),
                        itemCount: keys.length,
                        itemBuilder: (_, gi) {
                          final key = keys[gi];
                          final items = grouped[key]!;
                          final dayTotal = items.fold(0.0, (s, t) => t.isExpense ? s - t.amount : t.isIncome ? s + t.amount : s);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Date header
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  Text(key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.lightTextSecondary)),
                                  Text(
                                    '${dayTotal >= 0 ? '+' : ''}${CurrencyFormatter.formatCompact(dayTotal)}',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                        color: dayTotal >= 0 ? AppColors.income : AppColors.expense),
                                  ),
                                ]),
                              ),
                              ...items.asMap().entries.map((e) => Dismissible(
                                key: Key(e.value.id),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  color: AppColors.expense,
                                  child: const Icon(Icons.delete_outline, color: Colors.white),
                                ),
                                confirmDismiss: (_) => showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('Delete Transaction'),
                                    content: const Text('This cannot be undone.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.expense),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                ),
                                onDismissed: (_) async {
                                  await DatabaseHelper.instance.delete('transactions', where: 'id = ?', whereArgs: [e.value.id]);
                                  ref.read(transactionUpdateProvider.notifier).state++;
                                  _load();
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('Transaction deleted'),
                                      action: SnackBarAction(label: 'Undo', onPressed: () async {
                                        await DatabaseHelper.instance.insert('transactions', e.value.toMap());
                                        ref.read(transactionUpdateProvider.notifier).state++;
                                        _load();
                                      }),
                                    ),
                                  );
                                },
                                child: _TxTile(tx: e.value, onTap: () async {
                                  final result = await Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => AddTransactionScreen(existing: e.value)));
                                  if (result == true) _load();
                                }).animate().fadeIn(delay: (e.key * 30).ms),
                              )),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(
        currentDateRange: _dateRange,
        onApply: (range) { setState(() => _dateRange = range); _applyFilters(); },
        onClear: () { setState(() { _dateRange = null; _categoryFilter = null; }); _applyFilters(); },
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label, value, current;
  final Color? color;
  final ValueChanged<String> onTap;
  const _TypeChip({required this.label, required this.value, required this.current, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? c : Colors.grey.withOpacity(0.3)),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w400, color: selected ? c : null)),
      ),
    );
  }
}

class _TxTile extends StatelessWidget {
  final TransactionModel tx;
  final VoidCallback onTap;
  const _TxTile({required this.tx, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isExpense = tx.isExpense;
    final color = isExpense ? AppColors.expense : tx.isIncome ? AppColors.income : AppColors.transfer;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: (tx.categoryColor != null ? Color(tx.categoryColor!) : AppColors.primary).withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(child: Text(_emoji(tx.categoryId ?? '', tx.categoryIcon), style: const TextStyle(fontSize: 20))),
      ),
      title: Text(tx.categoryName ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(
        [tx.note, tx.accountName, DateFormatter.formatTime(tx.date)].where((s) => s != null && s.isNotEmpty).join(' · '),
        style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(
          '${isExpense ? '-' : tx.isIncome ? '+' : ''}${CurrencyFormatter.formatCompact(tx.amount)}',
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15),
        ),
        if (tx.isSmsImported) const Text('📲 SMS', style: TextStyle(fontSize: 10, color: AppColors.lightTextSecondary)),
      ]),
      onTap: onTap,
    );
  }

  String _emoji(String id, String? customIcon) {
    if (customIcon != null && customIcon.isNotEmpty) return customIcon;
    const map = {'cat_food':'🍕','cat_grocery':'🛒','cat_transport':'🚗','cat_shopping':'🛍️',
      'cat_entertainment':'🎬','cat_health':'💊','cat_utilities':'⚡','cat_telecom':'📱',
      'cat_education':'🎓','cat_subscription':'🔄','cat_salary':'💰','cat_freelance':'💻',
      'cat_investment':'📈','cat_gift':'🎁','cat_travel':'✈️'};
    return map[id] ?? '💸';
  }
}

class _FilterSheet extends StatefulWidget {
  final DateTimeRange? currentDateRange;
  final ValueChanged<DateTimeRange?> onApply;
  final VoidCallback onClear;
  const _FilterSheet({this.currentDateRange, required this.onApply, required this.onClear});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  DateTimeRange? _range;

  @override
  void initState() { super.initState(); _range = widget.currentDateRange; }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        const Text('Filter Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.date_range_outlined, color: AppColors.primary),
          title: Text(_range == null ? 'Select Date Range' : '${DateFormatter.formatDateShort(_range!.start)} – ${DateFormatter.formatDateShort(_range!.end)}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final r = await showDateRangePicker(
              context: context, firstDate: DateTime(2020), lastDate: DateTime(2100),
              initialDateRange: _range,
            );
            if (r != null) setState(() => _range = r);
          },
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () { widget.onClear(); Navigator.pop(context); },
            child: const Text('Clear All'),
          )),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(
            onPressed: () { widget.onApply(_range); Navigator.pop(context); },
            child: const Text('Apply'),
          )),
        ]),
        const SizedBox(height: 8),
      ]),
    );
  }
}
