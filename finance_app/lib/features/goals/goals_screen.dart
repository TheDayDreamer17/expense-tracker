import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import '../../core/db/database_helper.dart';
import '../../core/models/models.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';

class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});
  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  List<GoalModel> _goals = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.query('goals', orderBy: 'created_at DESC');
    if (mounted) setState(() { _goals = rows.map(GoalModel.fromMap).toList(); _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Savings Goals'), actions: [IconButton(icon: const Icon(Icons.add), onPressed: _showGoalSheet)]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _goals.isEmpty ? _buildEmpty()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _goals.length,
                itemBuilder: (_, i) => _GoalCard(goal: _goals[i],
                  onTap: () => _showGoalSheet(goal: _goals[i]),
                  onAddSaving: () => _addSaving(_goals[i]),
                ).animate().fadeIn(delay: (i * 60).ms),
              ),
            ),
    );
  }

  Widget _buildEmpty() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('🎯', style: TextStyle(fontSize: 64)),
      const SizedBox(height: 16),
      const Text('No goals set', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text('Set a goal and track your progress!', style: TextStyle(color: AppColors.lightTextSecondary)),
      const SizedBox(height: 24),
      ElevatedButton.icon(icon: const Icon(Icons.add), label: const Text('Add Goal'), onPressed: _showGoalSheet),
    ]));
  }

  void _showGoalSheet({GoalModel? goal}) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _GoalFormSheet(goal: goal, onSaved: _load));
  }

  void _addSaving(GoalModel goal) async {
    final ctrl = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Add to ${goal.name}'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '), keyboardType: TextInputType.number, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, double.tryParse(ctrl.text)), child: const Text('Add')),
        ],
      ),
    );
    if (amount != null && amount > 0) {
      final newSaved = goal.savedAmount + amount;
      await DatabaseHelper.instance.update('goals', {'saved_amount': newSaved},
          where: 'id = ?', whereArgs: [goal.id]);
      _load();
    }
  }
}

class _GoalCard extends StatelessWidget {
  final GoalModel goal;
  final VoidCallback onTap;
  final VoidCallback onAddSaving;
  const _GoalCard({required this.goal, required this.onTap, required this.onAddSaving});

  @override
  Widget build(BuildContext context) {
    final pct = goal.progressPercent;
    final color = pct >= 1.0 ? AppColors.success : AppColors.primary;
    final months = goal.monthsToGoal;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(goal.icon, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(goal.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              if (goal.targetDate != null)
                Text('Target: ${DateFormatter.formatDate(goal.targetDate!)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
            ])),
            if (pct >= 1.0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.success.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                child: const Text('🎉 Done!', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(CurrencyFormatter.formatCompact(goal.savedAmount), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: color)),
            Text('/ ${CurrencyFormatter.formatCompact(goal.targetAmount)}', style: const TextStyle(color: AppColors.lightTextSecondary)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct, minHeight: 10,
              backgroundColor: color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${(pct * 100).toInt()}% achieved', style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
            if (months != null && months > 0)
              Text('~$months months to go', style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: onTap, child: const Text('Edit'))),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.add, size: 16), label: const Text('Add'), onPressed: onAddSaving)),
          ]),
        ]),
      ),
    );
  }
}

class _GoalFormSheet extends StatefulWidget {
  final GoalModel? goal;
  final VoidCallback onSaved;
  const _GoalFormSheet({this.goal, required this.onSaved});
  @override
  State<_GoalFormSheet> createState() => _GoalFormSheetState();
}

class _GoalFormSheetState extends State<_GoalFormSheet> {
  final _nameCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  final _monthlyCtrl = TextEditingController();
  String _icon = '🎯';
  DateTime? _targetDate;
  bool _saving = false;

  final _icons = ['🎯', '🏠', '🚗', '🏍', '✈️', '💍', '🎓', '💼', '🏖', '🚀', '💻', '📱', '🏋️', '🐾', '💰'];

  @override
  void initState() {
    super.initState();
    if (widget.goal != null) {
      _nameCtrl.text = widget.goal!.name;
      _targetCtrl.text = widget.goal!.targetAmount.toStringAsFixed(0);
      _icon = widget.goal!.icon;
      _targetDate = widget.goal!.targetDate;
      if (widget.goal!.monthlyContribution != null) _monthlyCtrl.text = widget.goal!.monthlyContribution!.toStringAsFixed(0);
    }
  }

  @override
  void dispose() { _nameCtrl.dispose(); _targetCtrl.dispose(); _monthlyCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text(widget.goal == null ? 'New Goal' : 'Edit Goal', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          // Icon picker
          SizedBox(height: 60, child: ListView(scrollDirection: Axis.horizontal, children: _icons.map((ic) =>
            GestureDetector(
              onTap: () => setState(() => _icon = ic),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _icon == ic ? AppColors.primary.withOpacity(0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _icon == ic ? AppColors.primary : Colors.transparent),
                ),
                child: Text(ic, style: const TextStyle(fontSize: 24)),
              ),
            ),
          ).toList())),
          const SizedBox(height: 12),
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Goal Name')),
          const SizedBox(height: 12),
          TextField(controller: _targetCtrl, decoration: const InputDecoration(labelText: 'Target Amount', prefixText: '₹ '), keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          TextField(controller: _monthlyCtrl, decoration: const InputDecoration(labelText: 'Monthly Contribution (optional)', prefixText: '₹ '), keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _targetDate ?? DateTime.now().add(const Duration(days: 365)), firstDate: DateTime.now(), lastDate: DateTime(2100));
              if (d != null) setState(() => _targetDate = d);
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Target Date (optional)'),
              child: Text(_targetDate != null ? DateFormatter.formatDate(_targetDate!) : 'Select date'),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Text(widget.goal == null ? 'Create Goal' : 'Update'),
          )),
        ]),
      ),
    );
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _targetCtrl.text.isEmpty) return;
    setState(() => _saving = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    await DatabaseHelper.instance.insert('goals', {
      'id': widget.goal?.id ?? const Uuid().v4(),
      'name': _nameCtrl.text.trim(), 'icon': _icon,
      'target_amount': double.tryParse(_targetCtrl.text) ?? 0,
      'saved_amount': widget.goal?.savedAmount ?? 0,
      'target_date': _targetDate?.millisecondsSinceEpoch,
      'monthly_contribution': double.tryParse(_monthlyCtrl.text),
      'created_at': widget.goal?.createdAt.millisecondsSinceEpoch ?? now,
    });
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }
}
