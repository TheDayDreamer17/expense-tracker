import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import 'dart:math' as math;
import '../../core/db/database_helper.dart';
import '../../core/utils/app_theme.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/refresh_provider.dart';
import '../../core/services/notification_service.dart';

class BifurcationScreen extends ConsumerStatefulWidget {
  const BifurcationScreen({super.key});

  @override
  ConsumerState<BifurcationScreen> createState() => _BifurcationScreenState();
}

class _BifurcationScreenState extends ConsumerState<BifurcationScreen> {
  // Tab 1: Split Planner state
  final _incomeCtrl = TextEditingController(text: '50000');
  String _selectedRule = '50_30_20'; // '50_30_20' | '70_20_10' | 'custom'
  double _customNeedsPct = 50.0;
  double _customWantsPct = 30.0;
  double _customSavingsPct = 20.0;

  // Tab 2: SIP Calculator state
  final _sipNameCtrl = TextEditingController(text: 'New Car Fund');
  final _sipTargetCtrl = TextEditingController(text: '500000');
  final _sipMonthsCtrl = TextEditingController(text: '36');
  final _sipReturnCtrl = TextEditingController(text: '12');

  // Tab 2: Emergency Fund state
  final _monthlyExpenseCtrl = TextEditingController();
  double _detectedAvgExpense = 0.0;
  double _bufferMonths = 6.0;
  bool _loadingExpense = true;

  @override
  void initState() {
    super.initState();
    _loadAverageExpense();
  }

  @override
  void dispose() {
    _incomeCtrl.dispose();
    _sipNameCtrl.dispose();
    _sipTargetCtrl.dispose();
    _sipMonthsCtrl.dispose();
    _sipReturnCtrl.dispose();
    _monthlyExpenseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAverageExpense() async {
    try {
      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      final sixtyDaysAgo = now.subtract(const Duration(days: 60)).millisecondsSinceEpoch;
      
      final rows = await db.rawQuery('''
        SELECT SUM(amount) as total FROM transactions
        WHERE type = 'EXPENSE' AND date >= ?
      ''', [sixtyDaysAgo]);

      final totalExp = (rows.first['total'] as num?)?.toDouble() ?? 0.0;
      // division by 2 to get monthly average over 60 days. If 0, use standard fallback
      final avg = totalExp > 0 ? (totalExp / 2.0) : 25000.0;

      if (mounted) {
        setState(() {
          _detectedAvgExpense = avg;
          _monthlyExpenseCtrl.text = avg.toStringAsFixed(0);
          _loadingExpense = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _detectedAvgExpense = 25000.0;
          _monthlyExpenseCtrl.text = '25000';
          _loadingExpense = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bifurcation & Calculators'),
          bottom: const TabBar(
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.lightTextSecondary,
            tabs: [
              Tab(icon: Icon(Icons.donut_large_rounded), text: 'Split Planner'),
              Tab(icon: Icon(Icons.calculate_outlined), text: 'Calculators'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildSplitPlannerTab(),
            _buildCalculatorsTab(),
          ],
        ),
      ),
    );
  }

  // ─── TAB 1: SPLIT PLANNER ──────────────────────────────────────────────────
  Widget _buildSplitPlannerTab() {
    final income = double.tryParse(_incomeCtrl.text) ?? 0.0;

    double needsPct = 50.0;
    double wantsPct = 30.0;
    double savingsPct = 20.0;

    if (_selectedRule == '70_20_10') {
      needsPct = 70.0;
      wantsPct = 10.0;
      savingsPct = 20.0;
    } else if (_selectedRule == 'custom') {
      needsPct = _customNeedsPct;
      wantsPct = _customWantsPct;
      savingsPct = _customSavingsPct;
    }

    final totalPct = needsPct + wantsPct + savingsPct;
    final isValidsSum = totalPct == 100.0;

    final needsAmount = income * (needsPct / 100.0);
    final wantsAmount = income * (wantsPct / 100.0);
    final savingsAmount = income * (savingsPct / 100.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Income Input Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Monthly Income Source',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _incomeCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixText: '₹ ',
                      hintText: 'Enter monthly income',
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 300.ms),

          const SizedBox(height: 16),

          // Plan Selection
          const Text(
            'Bifurcation Models',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          _buildRuleCard(
            id: '50_30_20',
            title: '50 / 30 / 20 Rule (Standard)',
            subtitle: '50% Needs, 30% Wants, 20% Savings. Great for most wealth plans.',
            current: _selectedRule,
          ),
          _buildRuleCard(
            id: '70_20_10',
            title: '70 / 20 / 10 Rule (Aggressive/Tight)',
            subtitle: '70% Needs, 20% Savings, 10% Wants. Best for high inflation/debt recovery.',
            current: _selectedRule,
          ),
          _buildRuleCard(
            id: 'custom',
            title: 'Custom Split Strategy',
            subtitle: 'Choose your own percentage allocations for your funds.',
            current: _selectedRule,
          ),

          if (_selectedRule == 'custom') ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Needs Allocations', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        Text('${_customNeedsPct.toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                      ],
                    ),
                    Slider(
                      value: _customNeedsPct,
                      min: 0, max: 100,
                      divisions: 20,
                      onChanged: (v) => setState(() => _customNeedsPct = v),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Wants Allocations', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        Text('${_customWantsPct.toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent)),
                      ],
                    ),
                    Slider(
                      value: _customWantsPct,
                      min: 0, max: 100,
                      divisions: 20,
                      onChanged: (v) => setState(() => _customWantsPct = v),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Savings & Goals', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        Text('${_customSavingsPct.toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.income)),
                      ],
                    ),
                    Slider(
                      value: _customSavingsPct,
                      min: 0, max: 100,
                      divisions: 20,
                      onChanged: (v) => setState(() => _customSavingsPct = v),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Total Allocation: ${totalPct.toInt()}% (Must equal 100%)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isValidsSum ? AppColors.income : AppColors.expense,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Allocation Results Cards
          if (isValidsSum && income > 0) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Monthly Bifurcation Allocation',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    
                    // visual stacked bar representation
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 24,
                        decoration: const BoxDecoration(),
                        child: Row(
                          children: [
                            if (needsPct > 0)
                              Expanded(
                                flex: needsPct.toInt(),
                                child: Container(
                                  color: AppColors.primary,
                                  child: Center(child: Text('${needsPct.toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                                ),
                              ),
                            if (wantsPct > 0)
                              Expanded(
                                flex: wantsPct.toInt(),
                                child: Container(
                                  color: AppColors.accent,
                                  child: Center(child: Text('${wantsPct.toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                                ),
                              ),
                            if (savingsPct > 0)
                              Expanded(
                                flex: savingsPct.toInt(),
                                child: Container(
                                  color: AppColors.income,
                                  child: Center(child: Text('${savingsPct.toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Allocations breakdown rows
                    _buildAllocationRow(
                      title: '🏠 Needs & Fixed Commitments',
                      description: 'Rent, EMIs, Bills, Groceries, Meds',
                      amount: needsAmount,
                      pct: needsPct,
                      color: AppColors.primary,
                    ),
                    const Divider(height: 24),
                    _buildAllocationRow(
                      title: '🛍️ Wants & Lifestyle',
                      description: 'Dining out, shopping, OTT, hobbies',
                      amount: wantsAmount,
                      pct: wantsPct,
                      color: AppColors.accent,
                    ),
                    const Divider(height: 24),
                    _buildAllocationRow(
                      title: '💰 Savings, SIPs & Investments',
                      description: 'Emergency funds, Mutual Funds, Gold',
                      amount: savingsAmount,
                      pct: savingsPct,
                      color: AppColors.income,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // Set Reminder CTA
            ElevatedButton.icon(
              icon: const Icon(Icons.alarm_add_rounded),
              label: const Text('Set Split Allocation Reminder'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: _setSplitReminder,
            ),
          ] else if (income > 0) ...[
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  '⚠️ Custom percentages must total 100% to calculate splits.',
                  style: TextStyle(color: AppColors.expense, fontWeight: FontWeight.bold, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildRuleCard({
    required String id,
    required String title,
    required String subtitle,
    required String current,
  }) {
    final selected = id == current;
    return GestureDetector(
      onTap: () => setState(() => _selectedRule = id),
      child: Card(
        color: selected ? AppColors.primary.withOpacity(0.08) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? AppColors.primary : Theme.of(context).dividerColor.withOpacity(0.3),
            width: selected ? 2 : 1,
          ),
        ),
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppColors.primary : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllocationRow({
    required String title,
    required String description,
    required double amount,
    required double pct,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8, height: 48,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 2),
              Text(description, style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${amount.toStringAsFixed(0)}',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
            ),
            Text('${pct.toInt()}% of income', style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
          ],
        ),
      ],
    );
  }

  Future<void> _setSplitReminder() async {
    final settings = ref.read(settingsProvider);
    final timeParts = settings.incomeReminderTime.split(':');
    final initialHour = int.tryParse(timeParts[0]) ?? 9;
    final initialMin = int.tryParse(timeParts[1]) ?? 0;

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMin),
    );

    if (selectedTime != null) {
      final timeStr = '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
      
      // Update settings
      await ref.read(settingsProvider.notifier).update(
        settings.copyWith(
          incomeReminderEnabled: true,
          incomeReminderTime: timeStr,
        ),
      );

      // Schedule notification
      await NotificationService.instance.scheduleMonthlyIncomeReminder(
        hour: selectedTime.hour,
        minute: selectedTime.minute,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Monthly split allocation reminder scheduled at $timeStr for the 1st of every month!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  // ─── TAB 2: CALCULATORS ────────────────────────────────────────────────────
  Widget _buildCalculatorsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // SIP Calculator Header
          _buildSIPCalculatorCard(),
          const SizedBox(height: 20),

          // Emergency Fund Header
          _buildEmergencyCalculatorCard(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSIPCalculatorCard() {
    final target = double.tryParse(_sipTargetCtrl.text) ?? 0.0;
    final months = int.tryParse(_sipMonthsCtrl.text) ?? 0;
    final annualReturn = double.tryParse(_sipReturnCtrl.text) ?? 0.0;

    double requiredMonthly = 0.0;
    if (months > 0) {
      final monthlyRate = (annualReturn / 12.0) / 100.0;
      if (monthlyRate == 0) {
        requiredMonthly = target / months;
      } else {
        // Formula: M = Target * i / ((1 + i)^n - 1)
        requiredMonthly = target * monthlyRate / (math.pow(1 + monthlyRate, months) - 1);
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.trending_up, color: AppColors.primary, size: 22),
                SizedBox(width: 8),
                Text(
                  'SIP / Savings Target Calculator',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sipNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Target Goal Name',
                hintText: 'e.g. New Car, Europe Trip',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sipTargetCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Target Amount',
                      prefixText: '₹ ',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _sipMonthsCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Duration (Months)',
                      hintText: 'e.g. 36',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sipReturnCtrl,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Expected Return Rate (Annual %)',
                hintText: 'e.g. 12',
                suffixText: '%',
              ),
            ),
            const SizedBox(height: 20),

            // SIP calculation result banner
            if (target > 0 && months > 0) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    const Text('Required Monthly Savings / SIP', style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
                    const SizedBox(height: 4),
                    Text(
                      '₹${requiredMonthly.toStringAsFixed(0)} / month',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: AppColors.primary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'For $months months at $annualReturn% interest to reach ₹${target.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 10, color: AppColors.lightTextSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.save_alt_rounded),
                label: const Text('Save as Savings Goal'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: () => _saveSipGoal(requiredMonthly, target, months),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyCalculatorCard() {
    final expense = double.tryParse(_monthlyExpenseCtrl.text) ?? 0.0;
    final emergencyFundSize = expense * _bufferMonths;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.shield_outlined, color: AppColors.income, size: 22),
                SizedBox(width: 8),
                Text(
                  'Emergency Buffer Fund Calculator',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingExpense)
              const Center(child: CircularProgressIndicator())
            else ...[
              Text(
                'Estimated Monthly Expense (based on last 60 days): ₹${_detectedAvgExpense.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _monthlyExpenseCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Adjust Monthly Expense',
                  prefixText: '₹ ',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Buffer Duration', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  Text('${_bufferMonths.toInt()} Months', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.income)),
                ],
              ),
              Slider(
                value: _bufferMonths,
                min: 3, max: 12,
                divisions: 9,
                activeColor: AppColors.income,
                onChanged: (v) => setState(() => _bufferMonths = v),
              ),
              const SizedBox(height: 16),

              // Emergency fund result banner
              if (expense > 0) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.income.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.income.withOpacity(0.2)),
                  ),
                  child: Column(
                    children: [
                      const Text('Target Emergency Fund Size', style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
                      const SizedBox(height: 4),
                      Text(
                        '₹${emergencyFundSize.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: AppColors.income),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ensures a security buffer of ${_bufferMonths.toInt()} months of living expenses.',
                        style: const TextStyle(fontSize: 10, color: AppColors.lightTextSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save_alt_rounded),
                  label: const Text('Save as Emergency Goal'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.income),
                  onPressed: () => _saveEmergencyGoal(emergencyFundSize),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _saveSipGoal(double monthlyContribution, double targetAmount, int months) async {
    try {
      final name = _sipNameCtrl.text.trim();
      if (name.isEmpty) return;

      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      final targetDate = now.add(Duration(days: months * 30));

      await db.insert('goals', {
        'id': const Uuid().v4(),
        'name': name,
        'icon': '🚗',
        'target_amount': targetAmount,
        'saved_amount': 0.0,
        'target_date': targetDate.millisecondsSinceEpoch,
        'monthly_contribution': monthlyContribution,
        'created_at': now.millisecondsSinceEpoch,
      });

      ref.read(transactionUpdateProvider.notifier).state++;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎯 Goal "$name" with monthly SIP ₹${monthlyContribution.toStringAsFixed(0)} saved successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save goal: $e')),
        );
      }
    }
  }

  Future<void> _saveEmergencyGoal(double targetAmount) async {
    try {
      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      final targetDate = now.add(const Duration(days: 365)); // Default 1 year timeline to achieve buffer

      await db.insert('goals', {
        'id': const Uuid().v4(),
        'name': 'Emergency Fund',
        'icon': '💰',
        'target_amount': targetAmount,
        'saved_amount': 0.0,
        'target_date': targetDate.millisecondsSinceEpoch,
        'monthly_contribution': targetAmount / 12.0, // Prefill monthly contribution based on 1 year
        'created_at': now.millisecondsSinceEpoch,
      });

      ref.read(transactionUpdateProvider.notifier).state++;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎯 Emergency Fund goal saved successfully! Tracking has started.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save emergency fund: $e')),
        );
      }
    }
  }
}
