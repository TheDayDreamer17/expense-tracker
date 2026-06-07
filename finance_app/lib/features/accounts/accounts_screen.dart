import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/db/database_helper.dart';
import '../../core/models/models.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'package:uuid/uuid.dart';
import '../../core/providers/refresh_provider.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});
  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  List<AccountModel> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows =
        await DatabaseHelper.instance.query('accounts', orderBy: 'created_at');
    if (mounted)
      setState(() {
        _accounts = rows.map(AccountModel.fromMap).toList();
        _loading = false;
      });
  }

  double get _netBalance => _accounts.fold(0, (s, a) => s + a.balance);

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(transactionUpdateProvider, (previous, next) {
      _load();
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
              icon: const Icon(Icons.add), onPressed: () => _showAccountSheet())
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Net balance card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryDark]),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Net Balance',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(CurrencyFormatter.format(_netBalance),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('${_accounts.length} accounts',
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                  ).animate().fadeIn(),
                  const SizedBox(height: 20),

                  // Group by type
                  ..._groupedAccounts().entries.map((entry) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8, top: 4),
                            child: Text(entry.key,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.lightTextSecondary)),
                          ),
                          ...entry.value
                              .asMap()
                              .entries
                              .map((e) => _AccountCard(
                                    account: e.value,
                                    onTap: () =>
                                        _showAccountSheet(account: e.value),
                                  ).animate().fadeIn(delay: (e.key * 60).ms)),
                        ],
                      )),
                ],
              ),
            ),
    );
  }

  Map<String, List<AccountModel>> _groupedAccounts() {
    final map = <String, List<AccountModel>>{};
    for (final a in _accounts) {
      final label = _typeLabel(a.type);
      map.putIfAbsent(label, () => []).add(a);
    }
    return map;
  }

  String _typeLabel(String type) => switch (type) {
        'CASH' => '💵 Cash',
        'BANK' => '🏦 Bank',
        'CREDIT_CARD' => '💳 Credit Cards',
        'LOAN' => '🏠 Loans',
        'INVESTMENT' => '📈 Investments',
        _ => '🗂 Other',
      };

  void _showAccountSheet({AccountModel? account}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AccountFormSheet(account: account, onSaved: _load),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final AccountModel account;
  final VoidCallback onTap;
  const _AccountCard({required this.account, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Color(account.color);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12)),
          child: Center(
              child: Text(_typeEmoji(account.type),
                  style: const TextStyle(fontSize: 22))),
        ),
        title: Text(account.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(account.type.replaceAll('_', ' ').toLowerCase(),
            style: const TextStyle(
                fontSize: 12, color: AppColors.lightTextSecondary)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(CurrencyFormatter.formatCompact(account.balance),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: account.balance >= 0
                        ? AppColors.income
                        : AppColors.expense)),
            if (account.creditLimit != null)
              Text(
                  'Limit: ${CurrencyFormatter.formatCompact(account.creditLimit!)}',
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.lightTextSecondary)),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  String _typeEmoji(String type) => switch (type) {
        'CASH' => '💵',
        'BANK' => '🏦',
        'CREDIT_CARD' => '💳',
        'LOAN' => '🏠',
        'INVESTMENT' => '📈',
        _ => '🗂',
      };
}

class _AccountFormSheet extends StatefulWidget {
  final AccountModel? account;
  final VoidCallback onSaved;
  const _AccountFormSheet({this.account, required this.onSaved});

  @override
  State<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends State<_AccountFormSheet> {
  final _nameCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  final _creditLimitCtrl = TextEditingController();
  String _type = 'BANK';
  int _color = 0xFF2196F3;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.account != null) {
      _nameCtrl.text = widget.account!.name;
      _balanceCtrl.text = widget.account!.balance.toStringAsFixed(2);
      _type = widget.account!.type;
      _color = widget.account!.color;
      if (widget.account!.creditLimit != null) {
        _creditLimitCtrl.text = widget.account!.creditLimit!.toStringAsFixed(2);
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    _creditLimitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
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
          Text(widget.account == null ? 'Add Account' : 'Edit Account',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Account Name',
                  prefixIcon: Icon(Icons.account_balance_wallet))),
          const SizedBox(height: 12),
          TextField(
              controller: _balanceCtrl,
              decoration: const InputDecoration(
                  labelText: 'Current Balance',
                  prefixText: '₹ ',
                  prefixIcon: Icon(Icons.currency_rupee)),
              keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(
                labelText: 'Account Type', prefixIcon: Icon(Icons.category)),
            items: const [
              DropdownMenuItem(value: 'CASH', child: Text('💵 Cash')),
              DropdownMenuItem(value: 'BANK', child: Text('🏦 Bank')),
              DropdownMenuItem(
                  value: 'CREDIT_CARD', child: Text('💳 Credit Card')),
              DropdownMenuItem(value: 'LOAN', child: Text('🏠 Loan')),
              DropdownMenuItem(
                  value: 'INVESTMENT', child: Text('📈 Investment')),
            ],
            onChanged: (v) => setState(() => _type = v!),
          ),
          if (_type == 'CREDIT_CARD') ...[
            const SizedBox(height: 12),
            TextField(
                controller: _creditLimitCtrl,
                decoration: const InputDecoration(
                    labelText: 'Credit Limit', prefixText: '₹ '),
                keyboardType: TextInputType.number),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)
                  : Text(widget.account == null ? 'Add Account' : 'Update'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final db = DatabaseHelper.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = widget.account?.id ?? const Uuid().v4();
    await db.insert('accounts', {
      'id': id,
      'name': _nameCtrl.text.trim(),
      'type': _type,
      'balance': double.tryParse(_balanceCtrl.text) ?? 0,
      'currency': 'INR',
      'color': _color,
      'icon': _type.toLowerCase(),
      'credit_limit': _type == 'CREDIT_CARD'
          ? double.tryParse(_creditLimitCtrl.text)
          : null,
      'created_at': widget.account?.createdAt.millisecondsSinceEpoch ?? now,
      'updated_at': now,
    });
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }
}
