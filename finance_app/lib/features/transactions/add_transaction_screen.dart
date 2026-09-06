import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../core/db/database_helper.dart';
import '../../core/models/models.dart';
import '../../core/models/transaction_model.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/providers/refresh_provider.dart';
import '../../widgets/shared/create_category_dialog.dart';
import '../../core/services/transaction_service.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  final TransactionModel? existing;
  const AddTransactionScreen({super.key, this.existing});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _amountFocusNode = FocusNode();

  String _type = 'EXPENSE';
  String? _selectedCategoryId;
  String _selectedAccountId = 'acc_cash';
  String? _selectedToAccountId;
  DateTime _selectedDate = DateTime.now();
  bool _isRecurring = false;
  String _recurrenceRule = 'MONTHLY';
  String? _receiptPath;
  String? _tripId;
  bool _saving = false;

  List<AccountModel> _accounts = [];
  List<CategoryModel> _sortedTypeCategories = [];
  List<TripModel> _trips = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    if (widget.existing != null) {
      _populateExisting();
    } else {
      // Auto focus the keyboard on load
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _amountFocusNode.requestFocus();
      });
    }
  }

  void _populateExisting() {
    final tx = widget.existing!;
    _type = tx.type;
    _amountController.text = tx.amount.toStringAsFixed(2);
    _noteController.text = tx.note ?? '';
    _selectedCategoryId = tx.categoryId;
    _selectedAccountId = tx.accountId;
    _selectedToAccountId = tx.toAccountId;
    _selectedDate = tx.date;
    _isRecurring = tx.isRecurring;
    _recurrenceRule = tx.recurrenceRule ?? 'MONTHLY';
    _tripId = tx.tripId;
    _receiptPath = tx.receiptPath;
  }

  Future<void> _loadData() async {
    final db = DatabaseHelper.instance;
    final accMaps = await db.query('accounts', orderBy: 'created_at');
    final catMaps = await db.query('categories', orderBy: 'type, name');
    final tripMaps = await db.query('trips', orderBy: 'start_date DESC');

    final typeFilter = _type == 'TRANSFER' ? 'EXPENSE' : _type;

    // Preselect last-used values if creating new
    String accountId = _selectedAccountId;
    String? categoryId = _selectedCategoryId;

    if (widget.existing == null) {
      final lastTxResult = await db.rawQuery('''
        SELECT account_id, category_id FROM transactions
        WHERE type = ? AND is_template = 0
        ORDER BY date DESC LIMIT 1
      ''', [_type]);
      
      if (lastTxResult.isNotEmpty) {
        accountId = lastTxResult.first['account_id'] as String;
        categoryId = lastTxResult.first['category_id'] as String?;
      }
    }

    // Query frequent categories first
    final recentResult = await db.rawQuery('''
      SELECT t.category_id, COUNT(*) as cnt FROM transactions t
      WHERE t.type = ? AND t.category_id IS NOT NULL AND t.is_template = 0
      GROUP BY t.category_id ORDER BY cnt DESC LIMIT 8
    ''', [typeFilter]);

    final List<String> frequentIds = recentResult.map((r) => r['category_id'] as String).toList();
    
    final allCats = catMaps.map(CategoryModel.fromMap).toList();
    final matchingCats = allCats.where((c) => c.type == typeFilter).toList();
    
    matchingCats.sort((a, b) {
      final aIdx = frequentIds.indexOf(a.id);
      final bIdx = frequentIds.indexOf(b.id);
      if (aIdx != -1 && bIdx != -1) return aIdx.compareTo(bIdx);
      if (aIdx != -1) return -1;
      if (bIdx != -1) return 1;
      return a.name.compareTo(b.name);
    });

    if (mounted) {
      setState(() {
        _accounts = accMaps.map(AccountModel.fromMap).toList();
        _sortedTypeCategories = matchingCats;
        _trips = tripMaps.map(TripModel.fromMap).toList();
        
        _selectedAccountId = accountId;
        _selectedCategoryId = categoryId;
        
        if (_accounts.isNotEmpty && !_accounts.any((a) => a.id == _selectedAccountId)) {
          _selectedAccountId = _accounts.first.id;
        }
        if (_selectedToAccountId == null && _accounts.length > 1) {
          _selectedToAccountId = _accounts.firstWhere((a) => a.id != _selectedAccountId, orElse: () => _accounts.first).id;
        }
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  void _onTypeChanged(String newType) {
    setState(() {
      _type = newType;
    });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final typeColor = _typeColor(_type);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add Transaction' : 'Edit Transaction'),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.expense),
              onPressed: _deleteTransaction,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Large focused Amount Field at the top
                  TextField(
                    controller: _amountController,
                    focusNode: _amountFocusNode,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: typeColor,
                    ),
                    decoration: InputDecoration(
                      hintText: '0.00',
                      hintStyle: TextStyle(color: typeColor.withOpacity(0.3)),
                      border: InputBorder.none,
                      prefixText: '₹',
                      prefixStyle: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: typeColor),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Segmented control for Expense / Income / Transfer
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        _buildTypeSegment('EXPENSE', 'Expense'),
                        _buildTypeSegment('INCOME', 'Income'),
                        _buildTypeSegment('TRANSFER', 'Transfer'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Category Chips Title
                  if (_type != 'TRANSFER') ...[
                    const Text('Category', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.lightTextSecondary)),
                    const SizedBox(height: 8),
                    _buildCategoryChips(),
                    const SizedBox(height: 20),
                  ],

                  // Account Selector Fields
                  const Text('Account Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.lightTextSecondary)),
                  const SizedBox(height: 8),
                  
                  // From Account
                  _FieldCard(
                    icon: Icons.account_balance_wallet_outlined,
                    label: _type == 'TRANSFER' ? 'From Account' : 'Account',
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedAccountId,
                        isExpanded: true,
                        items: _accounts
                            .map((a) => DropdownMenuItem(
                                  value: a.id,
                                  child: Text(a.name),
                                ))
                            .toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedAccountId = v!;
                            if (_selectedToAccountId == _selectedAccountId && _accounts.isNotEmpty) {
                              _selectedToAccountId = _accounts.firstWhere((a) => a.id != _selectedAccountId, orElse: () => _accounts.first).id;
                            }
                          });
                        },
                      ),
                    ),
                  ),

                  // To Account (for Transfers)
                  if (_type == 'TRANSFER') ...[
                    const SizedBox(height: 12),
                    _FieldCard(
                      icon: Icons.login_outlined,
                      label: 'To Account',
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedToAccountId,
                          isExpanded: true,
                          items: _accounts
                              .where((a) => a.id != _selectedAccountId)
                              .map((a) => DropdownMenuItem(
                                    value: a.id,
                                    child: Text(a.name),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedToAccountId = v),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Expandable More Details area for optional parameters
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      leading: Icon(Icons.tune_outlined, color: typeColor),
                      title: const Text('More details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      childrenPadding: const EdgeInsets.only(top: 8),
                      children: [
                        // Date picker
                        _FieldCard(
                          icon: Icons.calendar_today_outlined,
                          label: 'Date',
                          onTap: _pickDate,
                          child: Text(DateFormatter.formatDateTime(_selectedDate),
                              style: const TextStyle(fontWeight: FontWeight.w500)),
                        ),
                        const SizedBox(height: 12),

                        // Note text field
                        _FieldCard(
                          icon: Icons.notes_outlined,
                          label: 'Note',
                          child: TextField(
                            controller: _noteController,
                            decoration: const InputDecoration.collapsed(hintText: 'Add a note...'),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Trip selection
                        if (_trips.isNotEmpty) ...[
                          _FieldCard(
                            icon: Icons.map_outlined,
                            label: 'Tag to Trip',
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                value: _tripId,
                                hint: const Text('None'),
                                isExpanded: true,
                                items: [
                                  const DropdownMenuItem<String?>(value: null, child: Text('None')),
                                  ..._trips.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))),
                                ],
                                onChanged: (v) => setState(() => _tripId = v),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Image / Receipt attachment
                        _FieldCard(
                          icon: Icons.receipt_outlined,
                          label: 'Receipt Image',
                          onTap: _pickReceipt,
                          child: Text(
                            _receiptPath != null ? '📷 Receipt attached' : 'Tap to attach photo',
                            style: TextStyle(color: _receiptPath != null ? AppColors.success : null, fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Recurring transaction settings
                        _FieldCard(
                          icon: Icons.loop,
                          label: 'Recurring Payment',
                          child: Row(
                            children: [
                              Expanded(child: Text(_isRecurring ? _recurrenceRule : 'One-time')),
                              Switch(
                                value: _isRecurring,
                                onChanged: (v) => setState(() => _isRecurring = v),
                                activeThumbColor: AppColors.primary,
                              ),
                            ],
                          ),
                        ),
                        if (_isRecurring) ...[
                          const SizedBox(height: 12),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'DAILY', label: Text('Daily')),
                              ButtonSegment(value: 'WEEKLY', label: Text('Weekly')),
                              ButtonSegment(value: 'MONTHLY', label: Text('Monthly')),
                              ButtonSegment(value: 'YEARLY', label: Text('Yearly')),
                            ],
                            selected: {_recurrenceRule},
                            onSelectionChanged: (s) => setState(() => _recurrenceRule = s.first),
                            style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Main Action Save button at the bottom
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveTransaction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: typeColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(widget.existing == null ? 'Save Transaction' : 'Update Transaction', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSegment(String value, String label) {
    final isSelected = _type == value;
    final color = _typeColor(value);

    return Expanded(
      child: GestureDetector(
        onTap: () => _onTypeChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : AppColors.lightTextSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ..._sortedTypeCategories.map((cat) {
            final isSelected = _selectedCategoryId == cat.id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${_emoji(cat.icon)} ${cat.name}'),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() => _selectedCategoryId = selected ? cat.id : null);
                },
                selectedColor: _typeColor(_type).withOpacity(0.08),
                backgroundColor: Colors.transparent,
                labelStyle: TextStyle(
                  color: isSelected ? _typeColor(_type) : null,
                  fontWeight: isSelected ? FontWeight.bold : null,
                  fontSize: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isSelected ? _typeColor(_type) : Colors.grey.withOpacity(0.2),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
              ),
            );
          }),
          // Add Category chip
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('Add Category'),
              onPressed: () async {
                final newCatId = await showDialog<String>(
                  context: context,
                  builder: (ctx) => CreateCategoryDialog(
                    initialType: _type == 'TRANSFER' ? 'EXPENSE' : _type,
                    transactionMonth: _selectedDate.month,
                    transactionYear: _selectedDate.year,
                  ),
                );
                if (newCatId != null) {
                  await _loadData();
                  setState(() {
                    _selectedCategoryId = newCatId;
                  });
                }
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
              labelStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Color _typeColor(String type) => switch (type) {
        'INCOME' => AppColors.success,
        'EXPENSE' => AppColors.expense,
        _ => AppColors.primary,
      };

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      if (!mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDate),
      );
      if (mounted) {
        setState(() => _selectedDate = DateTime(
              picked.year,
              picked.month,
              picked.day,
              time?.hour ?? _selectedDate.hour,
              time?.minute ?? _selectedDate.minute,
            ));
      }
    }
  }

  Future<void> _pickReceipt() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        setState(() => _receiptPath = picked.path);
      }
    } catch (_) {}
  }

  Future<void> _saveTransaction() async {
    final amtText = _amountController.text.trim();
    final amount = double.tryParse(amtText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    if (_type != 'TRANSFER' && _selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      // Save category mapping for self-learning
      final note = _noteController.text.trim();
      if (note.isNotEmpty && _selectedCategoryId != null && _type == 'EXPENSE') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('merchant_cat_${note.toLowerCase()}', _selectedCategoryId!);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = widget.existing?.id ?? const Uuid().v4();

      final newTx = TransactionModel(
        id: id,
        accountId: _selectedAccountId,
        toAccountId: _type == 'TRANSFER' ? _selectedToAccountId : null,
        categoryId: _type == 'TRANSFER' ? null : _selectedCategoryId,
        amount: amount,
        type: _type,
        date: _selectedDate,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        receiptPath: _receiptPath,
        isRecurring: _isRecurring,
        isTemplate: _isRecurring,
        nextDueDate: _isRecurring ? _selectedDate : null,
        recurrenceRule: _isRecurring ? _recurrenceRule : null,
        tripId: _tripId,
        isSmsImported: widget.existing?.isSmsImported ?? false,
        createdAt: widget.existing?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(now),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
        parentRecurringId: widget.existing?.parentRecurringId,
      );

      if (widget.existing == null) {
        await TransactionService.instance.createTransaction(newTx);
      } else {
        await TransactionService.instance.updateTransaction(widget.existing!, newTx);
      }

      // Refresh screens
      ref.read(transactionUpdateProvider.notifier).state++;

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.existing == null ? 'Added' : 'Updated'}: ₹${amount.toStringAsFixed(2)}'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteTransaction() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.expense),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true && widget.existing != null) {
      await TransactionService.instance.deleteTransaction(widget.existing!);
      ref.read(transactionUpdateProvider.notifier).state++;
      if (mounted) Navigator.pop(context, true);
    }
  }

  String _emoji(String icon) {
    const map = {
      'food': '🍔',
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
    return map[icon] ?? icon;
  }
}

class _FieldCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;
  final VoidCallback? onTap;

  const _FieldCard({required this.icon, required this.label, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
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
}
