import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/models/models.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';

class SmsTransactionSheet extends ConsumerStatefulWidget {
  final ParsedSmsTransaction parsed;
  const SmsTransactionSheet({super.key, required this.parsed});

  @override
  ConsumerState<SmsTransactionSheet> createState() => _SmsTransactionSheetState();
}

class _SmsTransactionSheetState extends ConsumerState<SmsTransactionSheet> {
  late String _selectedCategoryId;
  late String _type;
  final _noteController = TextEditingController();
  String _selectedAccountId = 'acc_bank';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.parsed.suggestedCategory;
    _type = widget.parsed.type;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkSurface : Colors.white;
    final isExpense = _type == 'EXPENSE';

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header banner
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isExpense
                    ? [AppColors.expense.withOpacity(0.15), AppColors.expense.withOpacity(0.05)]
                    : [AppColors.income.withOpacity(0.15), AppColors.income.withOpacity(0.05)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isExpense ? AppColors.expense.withOpacity(0.3) : AppColors.income.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isExpense ? AppColors.expense : AppColors.income,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isExpense ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    color: Colors.white, size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '📲 Transaction Detected',
                            style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        CurrencyFormatter.format(widget.parsed.amount),
                        style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700,
                          color: isExpense ? AppColors.expense : AppColors.income,
                        ),
                      ),
                      if (widget.parsed.merchant != null)
                        Text(
                          widget.parsed.merchant!,
                          style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                        ),
                    ],
                  ),
                ),
                // Type toggle
                GestureDetector(
                  onTap: () => setState(() => _type = _type == 'EXPENSE' ? 'INCOME' : 'EXPENSE'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isExpense ? AppColors.expense : AppColors.income,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isExpense ? 'Debit' : 'Credit',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.2),

          // Info row
          if (widget.parsed.accountLast4 != null || widget.parsed.balance != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  if (widget.parsed.accountLast4 != null) ...[
                    const Icon(Icons.credit_card, size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text('••${widget.parsed.accountLast4}', style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 16),
                  ],
                  if (widget.parsed.balance != null) ...[
                    const Icon(Icons.account_balance_wallet, size: 14, color: AppColors.income),
                    const SizedBox(width: 4),
                    Text(
                      'Bal: ${CurrencyFormatter.format(widget.parsed.balance!)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),

          const Divider(height: 24, indent: 16, endIndent: 16),

          // Category selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('Category', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                GestureDetector(
                  onTap: _pickCategory,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_categoryName(_selectedCategoryId),
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit, size: 14, color: AppColors.primary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Note field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                hintText: 'Add a note (optional)',
                prefixIcon: Icon(Icons.note_outlined, size: 18),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Dismiss', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveTransaction,
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Transaction'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _categoryName(String id) {
    const names = {
      'cat_food': '🍕 Food',
      'cat_grocery': '🛒 Groceries',
      'cat_transport': '🚗 Transport',
      'cat_shopping': '🛍️ Shopping',
      'cat_entertainment': '🎬 Entertainment',
      'cat_health': '💊 Health',
      'cat_utilities': '⚡ Utilities',
      'cat_telecom': '📱 Telecom',
      'cat_education': '🎓 Education',
      'cat_subscription': '🔄 Subscription',
      'cat_other_exp': '❓ Other',
      'cat_salary': '💰 Salary',
      'cat_other_inc': '💵 Other Income',
    };
    return names[id] ?? '❓ Other';
  }

  void _pickCategory() {
    // Show category picker bottom sheet
    showModalBottomSheet(
      context: context,
      builder: (_) => _CategoryPicker(
        selected: _selectedCategoryId,
        type: _type,
        onSelected: (id) {
          setState(() => _selectedCategoryId = id);
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _saveTransaction() async {
    setState(() => _saving = true);
    try {
      // Save via transaction provider
      // ref.read(transactionRepositoryProvider).addTransaction(...)
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transaction saved: ${CurrencyFormatter.format(widget.parsed.amount)}'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      setState(() => _saving = false);
    }
  }
}

class _CategoryPicker extends StatelessWidget {
  final String selected;
  final String type;
  final ValueChanged<String> onSelected;

  const _CategoryPicker({required this.selected, required this.type, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final items = type == 'EXPENSE' ? _expenseCategories : _incomeCategories;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Select Category', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((item) {
            final isSelected = item['id'] == selected;
            return GestureDetector(
              onTap: () => onSelected(item['id']!),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  item['label']!,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.primary,
                    fontWeight: FontWeight.w600, fontSize: 13,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  static const _expenseCategories = [
    {'id': 'cat_food', 'label': '🍕 Food'},
    {'id': 'cat_grocery', 'label': '🛒 Groceries'},
    {'id': 'cat_transport', 'label': '🚗 Transport'},
    {'id': 'cat_shopping', 'label': '🛍️ Shopping'},
    {'id': 'cat_entertainment', 'label': '🎬 Entertainment'},
    {'id': 'cat_health', 'label': '💊 Health'},
    {'id': 'cat_utilities', 'label': '⚡ Utilities'},
    {'id': 'cat_telecom', 'label': '📱 Telecom'},
    {'id': 'cat_education', 'label': '🎓 Education'},
    {'id': 'cat_subscription', 'label': '🔄 Subscription'},
    {'id': 'cat_other_exp', 'label': '❓ Other'},
  ];

  static const _incomeCategories = [
    {'id': 'cat_salary', 'label': '💰 Salary'},
    {'id': 'cat_freelance', 'label': '💻 Freelance'},
    {'id': 'cat_business', 'label': '💼 Business'},
    {'id': 'cat_investment', 'label': '📈 Investment'},
    {'id': 'cat_gift', 'label': '🎁 Gift'},
    {'id': 'cat_other_inc', 'label': '💵 Other'},
  ];
}
