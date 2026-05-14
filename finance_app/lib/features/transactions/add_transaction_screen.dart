import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../core/db/database_helper.dart';
import '../../core/models/models.dart';
import '../../core/models/transaction_model.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  final TransactionModel? existing;
  const AddTransactionScreen({super.key, this.existing});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _typeController;
  final _noteController = TextEditingController();
  final _amountController = TextEditingController();

  String _type = 'EXPENSE';
  String? _selectedCategoryId;
  String _selectedAccountId = 'acc_cash';
  DateTime _selectedDate = DateTime.now();
  bool _isRecurring = false;
  String _recurrenceRule = 'MONTHLY';
  String? _receiptPath;
  String? _tripId;
  bool _saving = false;
  String _calcDisplay = '0';
  List<AccountModel> _accounts = [];
  List<CategoryModel> _categories = [];
  List<TripModel> _trips = [];

  @override
  void initState() {
    super.initState();
    _typeController = TabController(length: 3, vsync: this, initialIndex: 1);
    _typeController.addListener(() {
      final types = ['INCOME', 'EXPENSE', 'TRANSFER'];
      setState(() => _type = types[_typeController.index]);
    });
    _loadData();
    if (widget.existing != null) _populateExisting();
  }

  void _populateExisting() {
    final tx = widget.existing!;
    _type = tx.type;
    _typeController.index = ['INCOME', 'EXPENSE', 'TRANSFER'].indexOf(tx.type);
    _amountController.text = tx.amount.toStringAsFixed(2);
    _calcDisplay = tx.amount.toStringAsFixed(2);
    _noteController.text = tx.note ?? '';
    _selectedCategoryId = tx.categoryId;
    _selectedAccountId = tx.accountId;
    _selectedDate = tx.date;
    _isRecurring = tx.isRecurring;
    _tripId = tx.tripId;
  }

  Future<void> _loadData() async {
    final db = DatabaseHelper.instance;
    final accMaps = await db.query('accounts', orderBy: 'created_at');
    final catMaps = await db.query('categories', orderBy: 'type, name');
    final tripMaps = await db.query('trips', orderBy: 'start_date DESC');
    if (mounted) {
      setState(() {
        _accounts = accMaps.map(AccountModel.fromMap).toList();
        _categories = catMaps.map(CategoryModel.fromMap).toList();
        _trips = tripMaps.map(TripModel.fromMap).toList();
        _selectedAccountId = _accounts.isNotEmpty ? _accounts.first.id : 'acc_cash';
      });
    }
  }

  @override
  void dispose() {
    _typeController.dispose();
    _noteController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add Transaction' : 'Edit Transaction'),
        actions: [
          if (widget.existing != null)
            IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.expense), onPressed: _deleteTransaction),
        ],
      ),
      body: Column(
        children: [
          // Type tab bar
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightBorder,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _typeController,
              indicator: BoxDecoration(
                color: _typeColor(_type),
                borderRadius: BorderRadius.circular(10),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              tabs: const [Tab(text: 'Income'), Tab(text: 'Expense'), Tab(text: 'Transfer')],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  _buildAmountField(),
                  const SizedBox(height: 12),
                  _buildCalculatorPad(),
                  const SizedBox(height: 16),
                  _buildFormFields(),
                ],
              ),
            ),
          ),

          // Save button
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveTransaction,
                style: ElevatedButton.styleFrom(backgroundColor: _typeColor(_type)),
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(widget.existing == null ? 'Save Transaction' : 'Update Transaction'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _typeColor(String type) => switch (type) {
    'INCOME' => AppColors.income,
    'EXPENSE' => AppColors.expense,
    _ => AppColors.transfer,
  };

  Widget _buildAmountField() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_typeColor(_type), _typeColor(_type).withOpacity(0.7)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text('Amount', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            '₹ $_calcDisplay',
            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildCalculatorPad() {
    final buttons = [
      '7', '8', '9', '⌫',
      '4', '5', '6', '÷',
      '1', '2', '3', '×',
      '.', '0', '00', '=',
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      mainAxisSpacing: 8, crossAxisSpacing: 8,
      childAspectRatio: 1.5,
      children: buttons.map((b) => _CalcButton(
        label: b,
        color: ['÷', '×', '='].contains(b) ? AppColors.primary : null,
        onTap: () => _onCalcTap(b),
      )).toList(),
    );
  }

  void _onCalcTap(String btn) {
    setState(() {
      if (btn == '⌫') {
        _calcDisplay = _calcDisplay.length > 1 ? _calcDisplay.substring(0, _calcDisplay.length - 1) : '0';
      } else if (btn == '=') {
        // Basic eval (replace operators and evaluate)
        _calcDisplay = _calcDisplay.replaceAll(',', '');
      } else if (_calcDisplay == '0' && btn != '.') {
        _calcDisplay = btn;
      } else {
        _calcDisplay += btn;
      }
    });
  }

  Widget _buildFormFields() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldCategories = _categories.where((c) => c.type == (_type == 'INCOME' ? 'INCOME' : 'EXPENSE')).toList();

    return Column(
      children: [
        // Category
        _FieldCard(
          icon: Icons.category_outlined,
          label: 'Category',
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedCategoryId,
              hint: const Text('Select category'),
              isExpanded: true,
              items: fieldCategories.map((c) => DropdownMenuItem(
                value: c.id,
                child: Text(c.name),
              )).toList(),
              onChanged: (v) => setState(() => _selectedCategoryId = v),
            ),
          ),
        ),

        // Account
        _FieldCard(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Account',
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedAccountId,
              isExpanded: true,
              items: _accounts.map((a) => DropdownMenuItem(
                value: a.id,
                child: Text(a.name),
              )).toList(),
              onChanged: (v) => setState(() => _selectedAccountId = v!),
            ),
          ),
        ),

        // Date
        _FieldCard(
          icon: Icons.calendar_today_outlined,
          label: 'Date',
          onTap: _pickDate,
          child: Text(DateFormatter.formatDateTime(_selectedDate),
              style: const TextStyle(fontWeight: FontWeight.w500)),
        ),

        // Note
        _FieldCard(
          icon: Icons.notes_outlined,
          label: 'Note',
          child: TextField(
            controller: _noteController,
            decoration: const InputDecoration.collapsed(hintText: 'Add a note...'),
            style: const TextStyle(fontSize: 14),
          ),
        ),

        // Trip tag
        if (_trips.isNotEmpty)
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

        // Receipt
        _FieldCard(
          icon: Icons.receipt_outlined,
          label: 'Receipt',
          onTap: _pickReceipt,
          child: Text(
            _receiptPath != null ? '📷 Receipt attached' : 'Tap to attach photo',
            style: TextStyle(color: _receiptPath != null ? AppColors.success : null),
          ),
        ),

        // Recurring
        _FieldCard(
          icon: Icons.loop,
          label: 'Recurring',
          child: Row(
            children: [
              Expanded(child: Text(_isRecurring ? _recurrenceRule : 'One-time')),
              Switch(
                value: _isRecurring,
                onChanged: (v) => setState(() => _isRecurring = v),
                activeColor: AppColors.primary,
              ),
            ],
          ),
        ),
        if (_isRecurring)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'DAILY', label: Text('Daily')),
                ButtonSegment(value: 'WEEKLY', label: Text('Weekly')),
                ButtonSegment(value: 'MONTHLY', label: Text('Monthly')),
                ButtonSegment(value: 'YEARLY', label: Text('Yearly')),
              ],
              selected: {_recurrenceRule},
              onSelectionChanged: (s) => setState(() => _recurrenceRule = s.first),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((s) =>
                  s.contains(WidgetState.selected) ? AppColors.primary : null),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context, initialDate: _selectedDate,
      firstDate: DateTime(2000), lastDate: DateTime(2100),
    );
    if (picked != null) {
      final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_selectedDate));
      if (mounted) {
        setState(() => _selectedDate = DateTime(
          picked.year, picked.month, picked.day,
          time?.hour ?? _selectedDate.hour, time?.minute ?? _selectedDate.minute,
        ));
      }
    }
  }

  Future<void> _pickReceipt() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (file != null && mounted) setState(() => _receiptPath = file.path);
  }

  Future<void> _saveTransaction() async {
    final amount = double.tryParse(_calcDisplay.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    setState(() => _saving = true);
    try {
      final db = DatabaseHelper.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = widget.existing?.id ?? const Uuid().v4();

      final tx = {
        'id': id,
        'account_id': _selectedAccountId,
        'category_id': _selectedCategoryId,
        'amount': amount,
        'type': _type,
        'date': _selectedDate.millisecondsSinceEpoch,
        'note': _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        'receipt_path': _receiptPath,
        'is_recurring': _isRecurring ? 1 : 0,
        'recurrence_rule': _isRecurring ? _recurrenceRule : null,
        'trip_id': _tripId,
        'is_sms_imported': 0,
        'created_at': widget.existing?.createdAt.millisecondsSinceEpoch ?? now,
        'updated_at': now,
      };

      if (widget.existing == null) {
        await db.insert('transactions', tx);
        // Audit log
        await db.insert('audit_logs', {
          'id': const Uuid().v4(),
          'transaction_id': id,
          'action': 'CREATE',
          'after_data': tx.toString(),
          'created_at': now,
        });
      } else {
        await db.update('transactions', tx, where: 'id = ?', whereArgs: [id]);
        await db.insert('audit_logs', {
          'id': const Uuid().v4(),
          'transaction_id': id,
          'action': 'UPDATE',
          'after_data': tx.toString(),
          'created_at': now,
        });
      }

      // Update account balance
      await _updateAccountBalance(_selectedAccountId, amount, _type);

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

  Future<void> _updateAccountBalance(String accountId, double amount, String type) async {
    final db = DatabaseHelper.instance;
    final rows = await db.query('accounts', where: 'id = ?', whereArgs: [accountId]);
    if (rows.isEmpty) return;
    final current = (rows.first['balance'] as num).toDouble();
    final newBalance = type == 'INCOME' ? current + amount : current - amount;
    await db.update('accounts', {
      'balance': newBalance,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id = ?', whereArgs: [accountId]);
  }

  Future<void> _deleteTransaction() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.expense),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true && widget.existing != null) {
      final db = DatabaseHelper.instance;
      await db.delete('transactions', where: 'id = ?', whereArgs: [widget.existing!.id]);
      await db.insert('audit_logs', {
        'id': const Uuid().v4(),
        'transaction_id': widget.existing!.id,
        'action': 'DELETE',
        'before_data': widget.existing!.toMap().toString(),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      if (mounted) Navigator.pop(context, true);
    }
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
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
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

class _CalcButton extends StatelessWidget {
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _CalcButton({required this.label, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          color: color ?? (isDark ? AppColors.darkCard : AppColors.lightBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600,
              color: color != null ? Colors.white : null,
            ),
          ),
        ),
      ),
    );
  }
}
