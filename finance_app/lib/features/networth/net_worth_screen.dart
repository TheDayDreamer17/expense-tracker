import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import '../../core/db/database_helper.dart';
import '../../core/models/models.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';

class NetWorthScreen extends ConsumerStatefulWidget {
  const NetWorthScreen({super.key});
  @override
  ConsumerState<NetWorthScreen> createState() => _NetWorthScreenState();
}

class _NetWorthScreenState extends ConsumerState<NetWorthScreen> {
  List<NetWorthEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance
        .query('net_worth_entries', orderBy: 'date DESC');
    if (mounted)
      setState(() {
        _entries = rows.map(NetWorthEntry.fromMap).toList();
        _loading = false;
      });
  }

  // Latest value per name
  Map<String, NetWorthEntry> get _latestEntries {
    final map = <String, NetWorthEntry>{};
    for (final e in _entries) {
      if (!map.containsKey(e.name)) map[e.name] = e;
    }
    return map;
  }

  double get _totalAssets => _latestEntries.values
      .where((e) => e.isAsset)
      .fold(0, (s, e) => s + e.amount);
  double get _totalLiabilities => _latestEntries.values
      .where((e) => e.isLiability)
      .fold(0, (s, e) => s + e.amount);
  double get _netWorth => _totalAssets - _totalLiabilities;

  @override
  Widget build(BuildContext context) {
    final latest = _latestEntries;
    final assets = latest.values.where((e) => e.isAsset).toList();
    final liabilities = latest.values.where((e) => e.isLiability).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Net Worth'), actions: [
        IconButton(icon: const Icon(Icons.add), onPressed: _showAddSheet)
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Net worth card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _netWorth >= 0
                            ? [AppColors.income, const Color(0xFF00A878)]
                            : [AppColors.expense, const Color(0xFFD32F2F)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(children: [
                      const Text('Net Worth',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 14)),
                      const SizedBox(height: 8),
                      Text(CurrencyFormatter.format(_netWorth),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _NWStatChip(
                                label: 'Assets',
                                value: _totalAssets,
                                color: Colors.white),
                            Container(
                                width: 1, height: 30, color: Colors.white30),
                            _NWStatChip(
                                label: 'Liabilities',
                                value: _totalLiabilities,
                                color: Colors.white),
                          ]),
                    ]),
                  ).animate().fadeIn(),
                  const SizedBox(height: 20),

                  // Assets
                  _buildSection('💰 Assets', assets, isAsset: true),
                  const SizedBox(height: 16),
                  // Liabilities
                  _buildSection('🔴 Liabilities', liabilities, isAsset: false),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildSection(String title, List<NetWorthEntry> entries,
      {required bool isAsset}) {
    final subTypes = <String, List<NetWorthEntry>>{};
    for (final e in entries) {
      subTypes.putIfAbsent(e.subType, () => []).add(e);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text(
              CurrencyFormatter.formatCompact(
                  isAsset ? _totalAssets : _totalLiabilities),
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isAsset ? AppColors.income : AppColors.expense)),
        ]),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12)),
            child: Center(
                child: Text('No ${isAsset ? 'assets' : 'liabilities'} added',
                    style:
                        const TextStyle(color: AppColors.lightTextSecondary))),
          )
        else
          ...entries.asMap().entries.map((e) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Text(_subTypeEmoji(e.value.subType),
                      style: const TextStyle(fontSize: 24)),
                  title: Text(e.value.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(e.value.subType),
                  trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(CurrencyFormatter.formatCompact(e.value.amount),
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: isAsset
                                    ? AppColors.income
                                    : AppColors.expense)),
                        TextButton(
                          onPressed: () => _showUpdateSheet(e.value),
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 20)),
                          child: const Text('Update',
                              style: TextStyle(fontSize: 11)),
                        ),
                      ]),
                  onTap: () => _showUpdateSheet(e.value),
                ),
              ).animate().fadeIn(delay: (e.key * 40).ms)),
      ],
    );
  }

  String _subTypeEmoji(String type) {
    const map = {
      'Bank': '🏦',
      'FD': '🏛',
      'MF': '📊',
      'Stocks': '📈',
      'Gold': '🥇',
      'Real Estate': '🏠',
      'Cash': '💵',
      'Loan': '🏠',
      'Credit Card': '💳',
      'Other': '💼'
    };
    return map[type] ?? '💰';
  }

  void _showAddSheet() {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _NWEntrySheet(onSaved: _load));
  }

  void _showUpdateSheet(NetWorthEntry entry) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _NWEntrySheet(existing: entry, onSaved: _load));
  }
}

class _NWStatChip extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _NWStatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label,
            style: TextStyle(color: color.withOpacity(0.7), fontSize: 12)),
        Text(CurrencyFormatter.formatCompact(value),
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 16)),
      ]);
}

class _NWEntrySheet extends StatefulWidget {
  final NetWorthEntry? existing;
  final VoidCallback onSaved;
  const _NWEntrySheet({this.existing, required this.onSaved});
  @override
  State<_NWEntrySheet> createState() => _NWEntrySheetState();
}

class _NWEntrySheetState extends State<_NWEntrySheet> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _type = 'ASSET';
  String _subType = 'Bank';
  bool _saving = false;

  static const _assetSubTypes = [
    'Bank',
    'FD',
    'MF',
    'Stocks',
    'Gold',
    'Real Estate',
    'Cash',
    'Other'
  ];
  static const _liabilitySubTypes = ['Loan', 'Credit Card', 'Other'];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameCtrl.text = widget.existing!.name;
      _amountCtrl.text = widget.existing!.amount.toStringAsFixed(0);
      _type = widget.existing!.entryType;
      _subType = widget.existing!.subType;
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
    final subTypes = _type == 'ASSET' ? _assetSubTypes : _liabilitySubTypes;
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
            Text(widget.existing == null ? 'Add Entry' : 'Update Entry',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ASSET', label: Text('Asset')),
                ButtonSegment(value: 'LIABILITY', label: Text('Liability'))
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                _subType =
                    (_type == 'ASSET' ? _assetSubTypes : _liabilitySubTypes)
                        .first;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue:
                  subTypes.contains(_subType) ? _subType : subTypes.first,
              decoration: const InputDecoration(labelText: 'Type'),
              items: subTypes
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _subType = v!),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Name (e.g. SBI FD, Zerodha)')),
            const SizedBox(height: 12),
            TextField(
                controller: _amountCtrl,
                decoration: const InputDecoration(
                    labelText: 'Current Value', prefixText: '₹ '),
                keyboardType: TextInputType.number),
            const SizedBox(height: 20),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: Text(widget.existing == null ? 'Add' : 'Update'))),
          ]),
    );
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _amountCtrl.text.isEmpty) return;
    setState(() => _saving = true);
    await DatabaseHelper.instance.insert('net_worth_entries', {
      'id': const Uuid().v4(),
      'entry_type': _type,
      'sub_type': _subType,
      'name': _nameCtrl.text.trim(),
      'amount': double.tryParse(_amountCtrl.text) ?? 0,
      'date': DateTime.now().millisecondsSinceEpoch,
    });
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }
}
