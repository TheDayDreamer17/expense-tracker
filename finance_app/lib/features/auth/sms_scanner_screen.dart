import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/services/native_sms_service.dart';
import '../../core/models/models.dart';
import '../../core/db/database_helper.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SmsScannerScreen extends ConsumerStatefulWidget {
  const SmsScannerScreen({super.key});
  @override
  ConsumerState<SmsScannerScreen> createState() => _SmsScannerScreenState();
}

class _SmsScannerScreenState extends ConsumerState<SmsScannerScreen> {
  int _months = 3;
  bool _scanning = false;
  bool _done = false;
  List<_ScanResult> _results = [];
  Set<int> _selected = {};
  bool _importing = false;

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _done = false;
      _results = [];
      _selected = {};
    });
    final parsed = await NativeSmsService.instance.scanInbox(months: _months);

    // Check for duplicates in DB
    final db = DatabaseHelper.instance;
    final existingRaw = await db.query('transactions');
    final existingSms = existingRaw
        .map((r) => r['sms_raw'] as String?)
        .whereType<String>()
        .toSet();

    final results = <_ScanResult>[];
    for (final p in parsed) {
      final isDup = existingSms.contains(p.smsRaw);
      results.add(_ScanResult(parsed: p, isDuplicate: isDup));
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

  Future<void> _import() async {
    setState(() => _importing = true);
    final db = DatabaseHelper.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    
    final accMaps = await db.query('accounts');
    final accounts = accMaps.map(AccountModel.fromMap).toList();
    
    int count = 0;

    for (final idx in _selected) {
      final r = _results[idx];
      final id = const Uuid().v4();
      
      String targetAccountId = 'acc_bank';
      final last4 = r.parsed.accountLast4;
      if (last4 != null && last4.isNotEmpty) {
        for (final a in accounts) {
          final suffix = prefs.getString('account_suffix_${a.id}');
          if (suffix == last4) {
            targetAccountId = a.id;
            break;
          }
        }
        
        if (targetAccountId == 'acc_bank') {
          for (final a in accounts) {
            if (r.parsed.isCreditCard && a.type != 'CREDIT_CARD') continue;
            if (a.name.toLowerCase().contains(last4.toLowerCase()) ||
                a.id.toLowerCase().contains(last4.toLowerCase())) {
              targetAccountId = a.id;
              break;
            }
          }
        }
      }
      
      if (targetAccountId == 'acc_bank') {
        if (r.parsed.isCreditCard) {
          final anyCc = accounts.firstWhere((a) => a.type == 'CREDIT_CARD', orElse: () => accounts.first);
          targetAccountId = anyCc.id;
        } else {
          final anyBank = accounts.firstWhere((a) => a.type == 'BANK', orElse: () => accounts.first);
          targetAccountId = anyBank.id;
        }
      }

      await db.insert('transactions', {
        'id': id,
        'account_id': targetAccountId,
        'category_id': r.parsed.suggestedCategory,
        'amount': r.parsed.amount,
        'type': r.parsed.type,
        'date': now - (idx * 60000), // approximate
        'note': r.parsed.merchant,
        'is_sms_imported': 1,
        'is_recurring': 0,
        'sms_raw': r.parsed.smsRaw,
        'created_at': now,
        'updated_at': now,
      });

      // Update Account Balance
      final rows = await db.query('accounts', where: 'id = ?', whereArgs: [targetAccountId]);
      if (rows.isNotEmpty) {
        final current = (rows.first['balance'] as num).toDouble();
        final newBalance = r.parsed.type == 'INCOME' ? current + r.parsed.amount : current - r.parsed.amount;
        await db.update('accounts', {'balance': newBalance, 'updated_at': now}, where: 'id = ?', whereArgs: [targetAccountId]);
      }
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
    return Scaffold(
      appBar: AppBar(title: const Text('Scan SMS Inbox')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📲 Scan your SMS inbox to import historical transactions automatically.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  const Text('Scan last: ',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  ...([1, 3, 6, 12].map((m) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          label: Text('${m}M'),
                          selected: _months == m,
                          onSelected: (_) => setState(() => _months = m),
                          selectedColor: AppColors.primary.withOpacity(0.2),
                        ),
                      ))),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _scanning ? null : _scan,
                    icon: _scanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.search),
                    label: Text(_scanning ? 'Scanning...' : 'Start Scan'),
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
                  Text('No transaction SMS found',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ])))
          else if (_results.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        '${_results.length} found · ${_selected.length} selected',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextButton(
                      onPressed: () => setState(() {
                        _selected = _selected.length == _results.length
                            ? {}
                            : Set.from(Iterable.generate(_results.length));
                      }),
                      child: Text(_selected.length == _results.length
                          ? 'Deselect All'
                          : 'Select All'),
                    ),
                  ]),
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
                      leading: Checkbox(
                        value: isSelected,
                        onChanged: r.isDuplicate
                            ? null
                            : (v) => setState(() =>
                                v! ? _selected.add(i) : _selected.remove(i)),
                        activeColor: AppColors.primary,
                      ),
                      title: Row(children: [
                        Text(CurrencyFormatter.format(r.parsed.amount),
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: r.parsed.type == 'EXPENSE'
                                    ? AppColors.expense
                                    : AppColors.income)),
                        const SizedBox(width: 8),
                        if (r.isDuplicate)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8)),
                            child: const Text('Duplicate',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey)),
                          ),
                      ]),
                      subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (r.parsed.merchant != null)
                              Text(r.parsed.merchant!,
                                  style: const TextStyle(fontSize: 12)),
                            Text(_catName(r.parsed.suggestedCategory),
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.primary)),
                          ]),
                      trailing: Text(r.parsed.type == 'EXPENSE' ? '🔴' : '🟢',
                          style: const TextStyle(fontSize: 18)),
                    ),
                  ).animate().fadeIn(delay: (i * 30).ms);
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
                      ? const CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white)
                      : Text('Import ${_selected.length} Transactions'),
                ),
              ),
            ),
          ],
        ],
      ),
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

class _ScanResult {
  final ParsedSmsTransaction parsed;
  final bool isDuplicate;
  const _ScanResult({required this.parsed, required this.isDuplicate});
}
