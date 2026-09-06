import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/native_sms_service.dart';
import '../../core/models/models.dart';
import '../../core/db/database_helper.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/services/transaction_service.dart';
import '../../core/models/transaction_model.dart';

enum SmsScanRange { oneDay, fiveDays, thirtyDays, threeMonths, custom }

class SmsScannerScreen extends ConsumerStatefulWidget {
  const SmsScannerScreen({super.key});
  @override
  ConsumerState<SmsScannerScreen> createState() => _SmsScannerScreenState();
}

class _SmsScannerScreenState extends ConsumerState<SmsScannerScreen> {
  SmsScanRange _range = SmsScanRange.fiveDays;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 5));
  DateTime _endDate = DateTime.now();

  bool _scanning = false;
  bool _done = false;
  List<_EditableScanResult> _results = [];
  Set<int> _selected = {};
  bool _importing = false;
  List<AccountModel> _existingAccounts = [];
  List<CategoryModel> _existingCategories = [];

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    final db = DatabaseHelper.instance;
    final accMaps = await db.query('accounts');
    final catMaps = await db.query('categories');
    if (mounted) {
      setState(() {
        _existingAccounts = accMaps.map(AccountModel.fromMap).toList();
        _existingCategories = catMaps.map(CategoryModel.fromMap).toList();
      });
    }
  }

  void _updateRange(SmsScanRange range) {
    final now = DateTime.now();
    setState(() {
      _range = range;
      switch (range) {
        case SmsScanRange.oneDay:
          _startDate = now.subtract(const Duration(days: 1));
          _endDate = now;
          break;
        case SmsScanRange.fiveDays:
          _startDate = now.subtract(const Duration(days: 5));
          _endDate = now;
          break;
        case SmsScanRange.thirtyDays:
          _startDate = now.subtract(const Duration(days: 30));
          _endDate = now;
          break;
        case SmsScanRange.threeMonths:
          _startDate = now.subtract(const Duration(days: 90));
          _endDate = now;
          break;
        case SmsScanRange.custom:
          break;
      }
    });
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _range = SmsScanRange.custom;
        _startDate = picked.start;
        _endDate = picked.end.add(const Duration(hours: 23, minutes: 59));
      });
    }
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _done = false;
      _results = [];
      _selected = {};
    });

    // Determine months needed for native scan call
    final daysDifference = _endDate.difference(_startDate).inDays;
    final monthsNeeded = (daysDifference / 30).ceil().clamp(1, 12);

    final rawParsed = await NativeSmsService.instance.scanInbox(months: monthsNeeded);

    // Filter by exact date range
    final filtered = rawParsed.where((p) {
      return p.date.isAfter(_startDate.subtract(const Duration(minutes: 5))) &&
             p.date.isBefore(_endDate.add(const Duration(minutes: 5)));
    }).toList();

    // Check for duplicates in DB (exact SMS raw string AND amount+type+time signature)
    final db = DatabaseHelper.instance;
    final existingRaw = await db.query('transactions');
    final existingSmsSet = existingRaw
        .map((r) => r['sms_raw'] as String?)
        .whereType<String>()
        .toSet();

    final existingSignatures = existingRaw.map((r) {
      final amt = (r['amount'] as num).toDouble().toStringAsFixed(2);
      final dt = r['date'] as int;
      final type = r['type'] as String;
      final timeBucket = (dt / 60000).floor();
      return '$amt|$type|$timeBucket';
    }).toSet();

    final results = <_EditableScanResult>[];
    for (final p in filtered) {
      final isRawDup = existingSmsSet.contains(p.smsRaw);
      final amtStr = p.amount.toStringAsFixed(2);
      final timeBucket = (p.date.millisecondsSinceEpoch / 60000).floor();
      final sig = '$amtStr|${p.type}|$timeBucket';
      final isSigDup = existingSignatures.contains(sig);

      final isDup = isRawDup || isSigDup;

      results.add(_EditableScanResult(
        original: p,
        amount: p.amount,
        type: p.type,
        merchant: p.merchant ?? 'SMS Transaction',
        categoryId: p.suggestedCategory,
        accountId: _resolveTargetAccountId(p),
        isDuplicate: isDup,
        date: p.date,
      ));
    }

    setState(() {
      _results = results;
      _selected = results
          .asMap()
          .entries
          .where((e) => !e.value.isDuplicate)
          .map((e) => e.key)
          .toSet();
      _scanning = false;
      _done = true;
    });
  }

  String _resolveTargetAccountId(ParsedSmsTransaction p) {
    if (_existingAccounts.isEmpty) return 'acc_bank';
    final last4 = p.accountLast4;
    if (last4 != null && last4.isNotEmpty) {
      final match = _existingAccounts.firstWhere(
        (a) => a.name.toLowerCase().contains(last4.toLowerCase()) || a.id.contains(last4),
        orElse: () => _existingAccounts.first,
      );
      return match.id;
    }
    if (p.isCreditCard) {
      final cc = _existingAccounts.firstWhere((a) => a.type == 'CREDIT_CARD', orElse: () => _existingAccounts.first);
      return cc.id;
    }
    final bank = _existingAccounts.firstWhere((a) => a.type == 'BANK', orElse: () => _existingAccounts.first);
    return bank.id;
  }

  Future<void> _openNativeMessagesApp() async {
    final Uri uri = Uri.parse('sms:');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Messages app automatically.')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to launch SMS messaging app.')),
        );
      }
    }
  }

  void _editItem(int index) {
    final item = _results[index];
    final amountController = TextEditingController(text: item.amount.toStringAsFixed(2));
    final merchantController = TextEditingController(text: item.merchant);
    String selectedType = item.type;
    String selectedCategory = item.categoryId;
    String selectedAccount = item.accountId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Inspect & Edit SMS Transaction',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Type Segmented Toggle
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'EXPENSE', label: Text('Expense'), icon: Icon(Icons.arrow_downward, color: AppColors.expense)),
                        ButtonSegment(value: 'INCOME', label: Text('Income'), icon: Icon(Icons.arrow_upward, color: AppColors.success)),
                      ],
                      selected: {selectedType},
                      onSelectionChanged: (s) => setModalState(() => selectedType = s.first),
                    ),
                    const SizedBox(height: 16),

                    // Amount Field
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Amount (₹)',
                        prefixIcon: Icon(Icons.currency_rupee),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Merchant Field
                    TextField(
                      controller: merchantController,
                      decoration: const InputDecoration(
                        labelText: 'Merchant / Note',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Account Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: _existingAccounts.any((a) => a.id == selectedAccount) ? selectedAccount : (_existingAccounts.isNotEmpty ? _existingAccounts.first.id : null),
                      decoration: const InputDecoration(
                        labelText: 'Account',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                      ),
                      items: _existingAccounts.map((a) {
                        return DropdownMenuItem(
                          value: a.id,
                          child: Text(a.name),
                        );
                      }).toList(),
                      onChanged: (v) => setModalState(() => selectedAccount = v!),
                    ),
                    const SizedBox(height: 12),

                    // Category Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: _existingCategories.any((c) => c.id == selectedCategory) ? selectedCategory : 'cat_other_exp',
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: _existingCategories.map((c) {
                        return DropdownMenuItem(
                          value: c.id,
                          child: Text('${c.icon} ${c.name}'),
                        );
                      }).toList(),
                      onChanged: (v) => setModalState(() => selectedCategory = v!),
                    ),
                    const SizedBox(height: 16),

                    // Raw SMS Box
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Original SMS Text:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.lightTextSecondary)),
                          const SizedBox(height: 4),
                          Text(item.original.smsRaw, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // CTA to open native Messages app
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openNativeMessagesApp();
                      },
                      icon: const Icon(Icons.sms_outlined),
                      label: const Text('Open in Messaging App'),
                    ),
                    const SizedBox(height: 12),

                    // Save Changes Button
                    ElevatedButton(
                      onPressed: () {
                        final parsedAmt = double.tryParse(amountController.text) ?? item.amount;
                        setState(() {
                          item.amount = parsedAmt;
                          item.type = selectedType;
                          item.merchant = merchantController.text.trim();
                          item.categoryId = selectedCategory;
                          item.accountId = selectedAccount;
                          _selected.add(index); // Auto select edited item
                        });
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                      child: const Text('Confirm & Update'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    final now = DateTime.now().millisecondsSinceEpoch;

    int count = 0;

    for (final idx in _selected) {
      final r = _results[idx];
      final id = const Uuid().v4();

      final tx = TransactionModel(
        id: id,
        accountId: r.accountId,
        categoryId: r.categoryId,
        amount: r.amount,
        type: r.type,
        date: r.date,
        note: r.merchant,
        isSmsImported: true,
        smsRaw: r.original.smsRaw,
        createdAt: DateTime.fromMillisecondsSinceEpoch(now),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
      );

      await TransactionService.instance.createTransaction(tx);
      count++;
    }

    if (mounted) {
      setState(() => _importing = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ Imported $count transactions!'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final startStr = DateFormatter.formatDateShort(_startDate);
    final endStr = DateFormatter.formatDateShort(_endDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan SMS Inbox'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sms_outlined),
            tooltip: 'Open Messages App',
            onPressed: _openNativeMessagesApp,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📲 Scan SMS inbox to auto-detect historical transactions.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),

                // Range Selection Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildChip('1 Day', SmsScanRange.oneDay),
                      const SizedBox(width: 8),
                      _buildChip('5 Days', SmsScanRange.fiveDays),
                      const SizedBox(width: 8),
                      _buildChip('30 Days', SmsScanRange.thirtyDays),
                      const SizedBox(width: 8),
                      _buildChip('3 Months', SmsScanRange.threeMonths),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text(_range == SmsScanRange.custom ? '$startStr - $endStr' : 'Custom'),
                        selected: _range == SmsScanRange.custom,
                        onSelected: (_) => _pickCustomDateRange(),
                        selectedColor: AppColors.primary.withOpacity(0.2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _scanning ? null : _scan,
                    icon: _scanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search),
                    label: Text(_scanning ? 'Scanning Inbox...' : 'Start Scan ($startStr - $endStr)'),
                  ),
                ),
              ],
            ),
          ),
          if (_done && _results.isEmpty)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('🔍', style: TextStyle(fontSize: 48)),
                    SizedBox(height: 12),
                    Text('No transaction SMS found in range', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            )
          else if (_results.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_results.length} found · ${_selected.length} selected',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _selected = _selected.length == _results.length
                          ? {}
                          : Set.from(Iterable.generate(_results.length));
                    }),
                    child: Text(_selected.length == _results.length ? 'Deselect All' : 'Select All'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final r = _results[i];
                  final isSelected = _selected.contains(i);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: r.isDuplicate ? Colors.grey.withOpacity(0.05) : null,
                    child: ListTile(
                      onTap: () => _editItem(i),
                      leading: Checkbox(
                        value: isSelected,
                        onChanged: r.isDuplicate
                            ? null
                            : (v) => setState(() => v! ? _selected.add(i) : _selected.remove(i)),
                        activeColor: AppColors.primary,
                      ),
                      title: Row(
                        children: [
                          Text(
                            CurrencyFormatter.format(r.amount),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: r.type == 'EXPENSE' ? AppColors.expense : AppColors.income,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (r.isDuplicate)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('Duplicate', style: TextStyle(fontSize: 10, color: Colors.grey)),
                            ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.merchant, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                          Row(
                            children: [
                              Text(_catName(r.categoryId), style: const TextStyle(fontSize: 11, color: AppColors.primary)),
                              const SizedBox(width: 8),
                              Text('· ${DateFormatter.formatDateShort(r.date)}', style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                            ],
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.lightTextSecondary),
                            onPressed: () => _editItem(i),
                          ),
                        ],
                      ),
                    ),
                  ).animate().fadeIn(delay: (i * 20).ms);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selected.isEmpty || _importing ? null : _import,
                  child: _importing
                      ? const CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                      : Text('Import ${_selected.length} Transactions'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChip(String label, SmsScanRange range) {
    return ChoiceChip(
      label: Text(label),
      selected: _range == range,
      onSelected: (_) => _updateRange(range),
      selectedColor: AppColors.primary.withOpacity(0.2),
    );
  }

  String _catName(String id) {
    const map = {
      'cat_food': '🍕 Food',
      'cat_grocery': '🛒 Groceries',
      'cat_transport': '🚗 Transport',
      'cat_shopping': '🛍️ Shopping',
      'cat_entertainment': '🎬 Entertainment',
      'cat_health': '💊 Health',
      'cat_utilities': '⚡ Utilities',
      'cat_telecom': '📱 Telecom',
      'cat_education': '🎓 Education',
      'cat_other_exp': '❓ Other'
    };
    return map[id] ?? '❓ Other';
  }
}

class _EditableScanResult {
  final ParsedSmsTransaction original;
  double amount;
  String type;
  String merchant;
  String categoryId;
  String accountId;
  final bool isDuplicate;
  final DateTime date;

  _EditableScanResult({
    required this.original,
    required this.amount,
    required this.type,
    required this.merchant,
    required this.categoryId,
    required this.accountId,
    required this.isDuplicate,
    required this.date,
  });
}
