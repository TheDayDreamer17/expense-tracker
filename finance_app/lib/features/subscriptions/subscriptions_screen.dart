import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import '../../core/db/database_helper.dart';
import '../../core/models/models.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/services/notification_service.dart';

class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});
  @override
  ConsumerState<SubscriptionsScreen> createState() =>
      _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen> {
  List<SubscriptionModel> _subs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance
        .query('subscriptions', orderBy: 'next_billing_date ASC');
    if (mounted)
      setState(() {
        _subs = rows.map(SubscriptionModel.fromMap).toList();
        _loading = false;
      });
  }

  double get _monthlyTotal => _subs.fold(0, (s, sub) {
        return s +
            (sub.billingCycle == 'YEARLY' ? sub.amount / 12 : sub.amount);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subscriptions'), actions: [
        IconButton(icon: const Icon(Icons.add), onPressed: _showSubSheet)
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Monthly total card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)]),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(children: [
                      const Text('🔄', style: TextStyle(fontSize: 32)),
                      const SizedBox(width: 12),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Monthly Subscriptions',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                            Text(CurrencyFormatter.format(_monthlyTotal),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700)),
                            Text('${_subs.length} active subscriptions',
                                style: const TextStyle(
                                    color: Colors.white60, fontSize: 12)),
                          ]),
                    ]),
                  ).animate().fadeIn(),
                  const SizedBox(height: 16),

                  // Unused alert
                  ..._subs.where((s) => s.isUnused).map((s) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.warning.withOpacity(0.4)),
                        ),
                        child: Row(children: [
                          const Text('⚠️', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                            "${s.name}: unused for ${s.daysSinceLastUsed} days (₹${s.amount.toStringAsFixed(0)}/mo)",
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                          )),
                        ]),
                      )),

                  if (_subs.isEmpty)
                    const Center(
                        child: Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Column(children: [
                        Text('💳', style: TextStyle(fontSize: 48)),
                        SizedBox(height: 12),
                        Text('No subscriptions tracked',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ]),
                    ))
                  else
                    ..._subs.asMap().entries.map((e) => _SubCard(
                          sub: e.value,
                          onTap: () => _showSubSheet(sub: e.value),
                          onMarkUsed: () => _markUsed(e.value),
                        ).animate().fadeIn(delay: (e.key * 60).ms)),
                ],
              ),
            ),
    );
  }

  void _showSubSheet({SubscriptionModel? sub}) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _SubFormSheet(sub: sub, onSaved: _load));
  }

  Future<void> _markUsed(SubscriptionModel sub) async {
    await DatabaseHelper.instance.update('subscriptions',
        {'last_used_date': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [sub.id]);
    _load();
  }
}

class _SubCard extends StatelessWidget {
  final SubscriptionModel sub;
  final VoidCallback onTap;
  final VoidCallback onMarkUsed;
  const _SubCard(
      {required this.sub, required this.onTap, required this.onMarkUsed});

  @override
  Widget build(BuildContext context) {
    final daysUntil = sub.daysUntilBilling;
    final billingColor = daysUntil <= 3
        ? AppColors.expense
        : daysUntil <= 7
            ? AppColors.warning
            : AppColors.income;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12)),
          child: Center(
              child: Text(sub.icon, style: const TextStyle(fontSize: 22))),
        ),
        title: Row(children: [
          Text(sub.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          if (sub.isUnused)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Text('${sub.daysSinceLastUsed}d unused',
                  style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600)),
            ),
        ]),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(sub.category,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.lightTextSecondary)),
          Text(
            daysUntil == 0
                ? '⚡ Billing today!'
                : daysUntil < 0
                    ? 'Overdue'
                    : 'Bills in $daysUntil days',
            style: TextStyle(
                fontSize: 11, color: billingColor, fontWeight: FontWeight.w600),
          ),
        ]),
        trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹${sub.amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              Text(sub.billingCycle == 'YEARLY' ? '/yr' : '/mo',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.lightTextSecondary)),
            ]),
        onTap: onTap,
        onLongPress: onMarkUsed,
      ),
    );
  }
}

class _SubFormSheet extends StatefulWidget {
  final SubscriptionModel? sub;
  final VoidCallback onSaved;
  const _SubFormSheet({this.sub, required this.onSaved});
  @override
  State<_SubFormSheet> createState() => _SubFormSheetState();
}

class _SubFormSheetState extends State<_SubFormSheet> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _cycle = 'MONTHLY';
  String _icon = '🔄';
  String _category = 'Entertainment';
  DateTime _nextDate = DateTime.now().add(const Duration(days: 30));
  bool _saving = false;

  static const _presets = [
    {'name': 'Netflix', 'icon': '🎬', 'category': 'Entertainment'},
    {'name': 'Spotify', 'icon': '🎵', 'category': 'Entertainment'},
    {'name': 'Amazon Prime', 'icon': '📦', 'category': 'Entertainment'},
    {'name': 'Disney+', 'icon': '🏰', 'category': 'Entertainment'},
    {'name': 'YouTube Premium', 'icon': '▶️', 'category': 'Entertainment'},
    {'name': 'ChatGPT Plus', 'icon': '🤖', 'category': 'Software'},
    {'name': 'GitHub', 'icon': '💻', 'category': 'Software'},
    {'name': 'Adobe CC', 'icon': '🎨', 'category': 'Software'},
    {'name': 'Gym', 'icon': '🏋️', 'category': 'Health'},
    {'name': 'iCloud', 'icon': '☁️', 'category': 'Cloud'},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.sub != null) {
      _nameCtrl.text = widget.sub!.name;
      _amountCtrl.text = widget.sub!.amount.toStringAsFixed(0);
      _cycle = widget.sub!.billingCycle;
      _icon = widget.sub!.icon;
      _category = widget.sub!.category;
      _nextDate = widget.sub!.nextBillingDate;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
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
      child: SingleChildScrollView(
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
            Text(widget.sub == null ? 'Add Subscription' : 'Edit Subscription',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            // Quick presets
            SizedBox(
                height: 40,
                child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: _presets
                        .map(
                          (p) => GestureDetector(
                            onTap: () => setState(() {
                              _nameCtrl.text = p['name']!;
                              _icon = p['icon']!;
                              _category = p['category']!;
                            }),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text('${p['icon']} ${p['name']}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.primary)),
                            ),
                          ),
                        )
                        .toList())),
            const SizedBox(height: 12),
            TextField(
                controller: _nameCtrl,
                decoration:
                    const InputDecoration(labelText: 'Subscription Name')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _amountCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Amount', prefixText: '₹ '),
                      keyboardType: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(
                  child: DropdownButtonFormField<String>(
                initialValue: _cycle,
                decoration: const InputDecoration(labelText: 'Billing Cycle'),
                items: const [
                  DropdownMenuItem(value: 'MONTHLY', child: Text('Monthly')),
                  DropdownMenuItem(value: 'YEARLY', child: Text('Yearly'))
                ],
                onChanged: (v) => setState(() => _cycle = v!),
              )),
            ]),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: _nextDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2100));
                if (d != null) setState(() => _nextDate = d);
              },
              child: InputDecorator(
                  decoration:
                      const InputDecoration(labelText: 'Next Billing Date'),
                  child: Text(DateFormatter.formatDate(_nextDate))),
            ),
            const SizedBox(height: 20),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: Text(
                        widget.sub == null ? 'Add Subscription' : 'Update'))),
          ])),
    );
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _amountCtrl.text.isEmpty) return;
    setState(() => _saving = true);
    await DatabaseHelper.instance.insert('subscriptions', {
      'id': widget.sub?.id ?? const Uuid().v4(),
      'name': _nameCtrl.text.trim(),
      'amount': double.tryParse(_amountCtrl.text) ?? 0,
      'billing_cycle': _cycle,
      'next_billing_date': _nextDate.millisecondsSinceEpoch,
      'last_used_date': widget.sub?.lastUsedDate?.millisecondsSinceEpoch,
      'icon': _icon,
      'category': _category,
      'created_at': widget.sub?.createdAt.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch,
    });
    // Reschedule all alerts when a subscription is added or updated
    await NotificationService.instance.scheduleAllSubscriptionAlerts();
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }
}
