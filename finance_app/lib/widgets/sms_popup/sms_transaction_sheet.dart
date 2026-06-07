import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/models.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'package:uuid/uuid.dart';
import '../../core/db/database_helper.dart';
import '../../core/providers/refresh_provider.dart';
import '../../core/services/native_sms_service.dart';
import '../shared/create_category_dialog.dart';

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
  late final TextEditingController _amountController;
  late final TextEditingController _merchantController;
  String _selectedAccountId = 'acc_bank';
  bool _saving = false;
  List<AccountModel> _accounts = [];
  bool _loadingAccounts = true;
  bool _hasPrompted = false;

  List<CategoryModel> _categories = [];
  bool _loadingCategories = true;
  String _lastCheckedMerchant = '';

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.parsed.suggestedCategory;
    _type = widget.parsed.type;
    _amountController = TextEditingController(text: widget.parsed.amount.toStringAsFixed(2));
    _merchantController = TextEditingController(text: widget.parsed.merchant ?? '');

    _amountController.addListener(_onInputChanged);
    _merchantController.addListener(_onInputChanged);

    _loadAccounts();
    _loadCategories();
    _loadLearnedCategory();
  }

  void _onInputChanged() {
    setState(() {});
    final currentMerchant = _merchantController.text.trim().toLowerCase();
    if (currentMerchant != _lastCheckedMerchant) {
      _lastCheckedMerchant = currentMerchant;
      _loadLearnedCategory();
    }
  }

  Future<void> _loadCategories() async {
    try {
      final db = DatabaseHelper.instance;
      final catMaps = await db.query('categories', orderBy: 'type, name');
      final categories = catMaps.map(CategoryModel.fromMap).toList();
      if (mounted) {
        setState(() {
          _categories = categories;
          _loadingCategories = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingCategories = false;
        });
      }
    }
  }

  Future<void> _loadLearnedCategory() async {
    final merchant = _merchantController.text.trim();
    if (merchant.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = 'merchant_cat_${merchant.toLowerCase()}';
        final learnedCatId = prefs.getString(key);
        if (learnedCatId != null && learnedCatId.isNotEmpty) {
          if (mounted) {
            setState(() {
              _selectedCategoryId = learnedCatId;
            });
          }
        }
      } catch (e) {
        debugPrint('Error loading learned category: $e');
      }
    }
  }

  Future<void> _loadAccounts() async {
    try {
      final db = DatabaseHelper.instance;
      final accMaps = await db.query('accounts', orderBy: 'created_at');
      final accounts = accMaps.map(AccountModel.fromMap).toList();
      if (mounted) {
        setState(() {
          _accounts = accounts;
          _loadingAccounts = false;
          
          if (_accounts.isNotEmpty) {
            bool hasMatchingCard = false;
            AccountModel? matched;
            final last4 = widget.parsed.accountLast4;
            if (last4 != null && last4.isNotEmpty) {
              for (final a in _accounts) {
                if (widget.parsed.isCreditCard && a.type != 'CREDIT_CARD') continue;
                if (a.name.toLowerCase().contains(last4.toLowerCase()) ||
                    a.id.toLowerCase().contains(last4.toLowerCase())) {
                  matched = a;
                  if (widget.parsed.isCreditCard && a.type == 'CREDIT_CARD') {
                    hasMatchingCard = true;
                  }
                  break;
                }
              }
            } else if (widget.parsed.isCreditCard) {
              final anyCard = _accounts.firstWhere(
                (a) => a.type == 'CREDIT_CARD',
                orElse: () => _accounts.first,
              );
              if (anyCard.type == 'CREDIT_CARD') {
                matched = anyCard;
                hasMatchingCard = true;
              }
            }

            matched ??= _accounts.firstWhere(
              (a) => widget.parsed.isCreditCard ? a.type == 'CREDIT_CARD' : a.type == 'BANK',
              orElse: () => _accounts.firstWhere(
                (a) => a.type == 'BANK',
                orElse: () => _accounts.first,
              ),
            );
            _selectedAccountId = matched.id;

            if (widget.parsed.isCreditCard && !hasMatchingCard && !_hasPrompted) {
              _hasPrompted = true;
              final ccLast4 = last4 ?? 'unknown';
              SharedPreferences.getInstance().then((prefs) {
                final ignoreKey = 'ignore_count_cc_$ccLast4';
                final ignores = prefs.getInt(ignoreKey) ?? 0;
                if (ignores < 5) {
                  _promptCreateCardAccount(prefs, ignoreKey, ignores);
                }
              });
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingAccounts = false;
        });
      }
    }
  }

  void _promptCreateCardAccount(SharedPreferences prefs, String ignoreKey, int ignores) {
    final last4 = widget.parsed.accountLast4 ?? '';
    final bankPrefix = widget.parsed.cardName ?? 'Credit Card';
    final suggestedName = '$bankPrefix${last4.isNotEmpty ? " XX$last4" : ""}';

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final nameController = TextEditingController(text: suggestedName.trim());

      final created = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Add Missing Credit Card?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'We detected a credit card transaction, but you do not have a matching card account configured. Would you like to create one now?',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Card Account Name',
                  prefixIcon: Icon(Icons.credit_card),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await prefs.setInt(ignoreKey, ignores + 1);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, false);
                }
              },
              child: const Text('Ignore'),
            ),
            ElevatedButton(
              onPressed: () {
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Create Card'),
            ),
          ],
        ),
      );

      if (created == true) {
        final cardName = nameController.text.trim();
        if (cardName.isNotEmpty) {
          await _createCardAccount(cardName);
        }
      }
    });
  }

  Future<void> _createCardAccount(String name) async {
    try {
      final db = DatabaseHelper.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = 'cc_${widget.parsed.accountLast4 ?? const Uuid().v4()}';

      final account = {
        'id': id,
        'name': name,
        'type': 'CREDIT_CARD',
        'balance': 0.0,
        'currency': 'INR',
        'color': 0xFFE91E63,
        'icon': 'card',
        'credit_limit': 100000.0,
        'created_at': now,
        'updated_at': now,
      };

      await db.insert('accounts', account);

      // Reload accounts and select the new one!
      await _loadAccounts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('💳 Card "$name" created successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating card: $e')),
        );
      }
    }
  }

  void _toggleType() {
    setState(() {
      if (_type == 'EXPENSE') {
        _type = 'INCOME';
        _selectedCategoryId = 'cat_salary';
      } else {
        _type = 'EXPENSE';
        _selectedCategoryId = 'cat_other_exp';
      }
    });
  }

  @override
  void dispose() {
    _amountController.removeListener(_onInputChanged);
    _merchantController.removeListener(_onInputChanged);
    _amountController.dispose();
    _merchantController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Widget _buildFieldCard({
    required IconData icon,
    required String label,
    required Widget child,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : Colors.grey.shade50;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.lightTextSecondary)),
                  const SizedBox(height: 2),
                  child,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkSurface : Colors.white;
    final isExpense = _type == 'EXPENSE';
    final parsedAmount = double.tryParse(_amountController.text) ?? 0.0;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
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
                        Text(
                          '📲 Transaction Detected',
                          style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          CurrencyFormatter.format(parsedAmount),
                          style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700,
                            color: isExpense ? AppColors.expense : AppColors.income,
                          ),
                        ),
                        if (_merchantController.text.isNotEmpty)
                          Text(
                            _merchantController.text,
                            style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                          ),
                      ],
                    ),
                  ),
                  // Type toggle
                  GestureDetector(
                    onTap: _toggleType,
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

            // Scrollable Fields List
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Amount Field
                    _buildFieldCard(
                      icon: Icons.currency_rupee_rounded,
                      label: 'Amount',
                      child: TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration.collapsed(hintText: 'Enter amount'),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),

                    // Merchant Field
                    _buildFieldCard(
                      icon: Icons.storefront_rounded,
                      label: 'Merchant / Payee',
                      child: TextField(
                        controller: _merchantController,
                        decoration: const InputDecoration.collapsed(hintText: 'Enter merchant or payee'),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),

                    // Account Field
                    _loadingAccounts
                        ? _buildFieldCard(
                            icon: Icons.account_balance_wallet_outlined,
                            label: 'Account',
                            child: const Text('Loading accounts...', style: TextStyle(fontSize: 14)),
                          )
                        : _buildFieldCard(
                            icon: Icons.account_balance_wallet_outlined,
                            label: 'Account',
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedAccountId,
                                isExpanded: true,
                                items: _accounts
                                    .map((a) => DropdownMenuItem(
                                          value: a.id,
                                          child: Text('${a.name} (₹${a.balance.toStringAsFixed(2)})', style: const TextStyle(fontSize: 14)),
                                        ))
                                    .toList(),
                                onChanged: (v) => setState(() => _selectedAccountId = v!),
                              ),
                            ),
                          ),

                    // Category Field
                    _buildFieldCard(
                      icon: Icons.category_outlined,
                      label: 'Category',
                      onTap: _pickCategory,
                      child: Row(
                        children: [
                          Text(_categoryName(_selectedCategoryId),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          const Spacer(),
                          const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey),
                        ],
                      ),
                    ),

                    // Note Field
                    _buildFieldCard(
                      icon: Icons.notes_outlined,
                      label: 'Note',
                      child: TextField(
                        controller: _noteController,
                        decoration: const InputDecoration.collapsed(hintText: 'Add a note...'),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
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
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Save Transaction', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryName(String id) {
    final cat = _categories.firstWhere(
      (c) => c.id == id,
      orElse: () => const CategoryModel(id: '', name: 'Other', type: '', icon: '❓', color: 0),
    );
    if (cat.id.isNotEmpty) {
      return '${cat.icon} ${cat.name}';
    }
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
    showModalBottomSheet(
      context: context,
      builder: (_) => _CategoryPicker(
        selected: _selectedCategoryId,
        type: _type,
        categories: _categories,
        onSelected: (id) {
          setState(() => _selectedCategoryId = id);
          Navigator.pop(context);
        },
        onAddCategory: () async {
          Navigator.pop(context);
          final newCatId = await showDialog<String>(
            context: context,
            builder: (ctx) => CreateCategoryDialog(
              initialType: _type,
              transactionMonth: DateTime.now().month,
              transactionYear: DateTime.now().year,
            ),
          );
          if (newCatId != null) {
            await _loadCategories();
            setState(() {
              _selectedCategoryId = newCatId;
            });
          }
        },
      ),
    );
  }

  Future<void> _saveTransaction() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    // Check Budget Limit threshold warning for EXPENSE
    if (_type == 'EXPENSE') {
      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      final month = now.month;
      final year = now.year;

      final budgetRows = await db.query(
        'budgets',
        where: 'category_id = ? AND month = ? AND year = ?',
        whereArgs: [_selectedCategoryId, month, year],
      );

      if (budgetRows.isNotEmpty) {
        final budgetLimit = (budgetRows.first['amount'] as num).toDouble();
        if (budgetLimit > 0) {
          final startOfMonth = DateTime(year, month, 1).millisecondsSinceEpoch;
          final endOfMonth = DateTime(year, month + 1, 1).millisecondsSinceEpoch;

          final result = await db.rawQuery('''
            SELECT SUM(amount) as total FROM transactions
            WHERE category_id = ? AND type = 'EXPENSE' AND date >= ? AND date < ?
          ''', [_selectedCategoryId, startOfMonth, endOfMonth]);

          final totalSpent = (result.first['total'] as num?)?.toDouble() ?? 0.0;

          if (totalSpent + amount >= 0.8 * budgetLimit) {
            final percentage = ((totalSpent + amount) / budgetLimit * 100).toStringAsFixed(0);
            final categoryRow = _categories.firstWhere(
              (c) => c.id == _selectedCategoryId,
              orElse: () => const CategoryModel(id: '', name: 'Selected Category', type: '', icon: '❓', color: 0),
            );

            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Budget Alert'),
                  ],
                ),
                content: Text(
                  'This transaction of ₹${amount.toStringAsFixed(2)} will put you at $percentage% of your monthly budget limit (₹${budgetLimit.toStringAsFixed(2)}) for "${categoryRow.name}".\n\nDo you want to continue?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                    child: const Text('Continue'),
                  ),
                ],
              ),
            );
            if (confirm != true) {
              return;
            }
          }
        }
      }
    }

    setState(() => _saving = true);
    try {
      // Save category mapping for self-learning
      final merchant = _merchantController.text.trim();
      if (merchant.isNotEmpty && _type == 'EXPENSE') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('merchant_cat_${merchant.toLowerCase()}', _selectedCategoryId);
      }
      final db = DatabaseHelper.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = const Uuid().v4();

      final tx = {
        'id': id,
        'account_id': _selectedAccountId,
        'category_id': _selectedCategoryId,
        'amount': amount,
        'type': _type,
        'date': now,
        'note': _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        'receipt_path': null,
        'is_recurring': 0,
        'is_template': 0,
        'next_due_date': null,
        'recurrence_rule': null,
        'trip_id': null,
        'sms_raw': widget.parsed.smsRaw,
        'is_sms_imported': 1,
        'created_at': now,
        'updated_at': now,
      };

      await db.insert('transactions', tx);

      // Audit log
      await db.insert('audit_logs', {
        'id': const Uuid().v4(),
        'transaction_id': id,
        'action': 'CREATE',
        'after_data': tx.toString(),
        'created_at': now,
      });

      // Update account balance
      await _updateAccountBalance(_selectedAccountId, amount, _type);

      // Delete from native SMS transactions Room DB so it doesn't get picked up again
      if (widget.parsed.id != null) {
        await NativeSmsService.instance.deleteTransaction(widget.parsed.id!);
      }

      // Refresh all screens watching this provider
      ref.read(transactionUpdateProvider.notifier).state++;

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transaction saved: ${CurrencyFormatter.format(amount)}'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    }
  }

  Future<void> _updateAccountBalance(
      String accountId, double amount, String type) async {
    final db = DatabaseHelper.instance;
    final rows =
        await db.query('accounts', where: 'id = ?', whereArgs: [accountId]);
    if (rows.isEmpty) return;
    final current = (rows.first['balance'] as num).toDouble();
    final newBalance = type == 'INCOME' ? current + amount : current - amount;
    await db.update(
        'accounts',
        {
          'balance': newBalance,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [accountId]);
  }
}

class _CategoryPicker extends StatelessWidget {
  final String selected;
  final String type;
  final List<CategoryModel> categories;
  final ValueChanged<String> onSelected;
  final VoidCallback onAddCategory;

  const _CategoryPicker({
    required this.selected,
    required this.type,
    required this.categories,
    required this.onSelected,
    required this.onAddCategory,
  });

  @override
  Widget build(BuildContext context) {
    final filteredCategories = categories.where((c) => c.type == type).toList();

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Select Category', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...filteredCategories.map((item) {
              final isSelected = item.id == selected;
              return GestureDetector(
                onTap: () => onSelected(item.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${item.icon} ${item.name}',
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.primary,
                      fontWeight: FontWeight.w600, fontSize: 13,
                    ),
                  ),
                ),
              );
            }),
            GestureDetector(
              onTap: onAddCategory,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16, color: AppColors.primary),
                    SizedBox(width: 4),
                    Text(
                      'Add Custom...',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold, fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
