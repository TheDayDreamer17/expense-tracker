import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/db/database_helper.dart';
import '../../core/services/indian_tax_engine.dart';
import '../../core/services/zerodha_csv_parser.dart';
import '../../core/services/ai_service.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';

class TaxPlannerScreen extends ConsumerStatefulWidget {
  const TaxPlannerScreen({super.key});

  @override
  ConsumerState<TaxPlannerScreen> createState() => _TaxPlannerScreenState();
}

class _TaxPlannerScreenState extends ConsumerState<TaxPlannerScreen> {
  // Income Inputs
  final _salaryController = TextEditingController(text: '0.00');
  final _rentalController = TextEditingController(text: '0.00');
  final _interestController = TextEditingController(text: '0.00');
  final _otherIncomeController = TextEditingController(text: '0.00');
  final _stcgController = TextEditingController(text: '0.00');
  final _ltcgController = TextEditingController(text: '0.00');

  // Deductions Inputs
  double _deductions80C = 0.0;
  double _deductions80D = 0.0;
  double _deductions80TTA = 0.0;

  bool _loadingLedger = true;
  String? _importedFileName;
  int _importedTradeCount = 0;
  double _importedDividends = 0.0;

  @override
  void initState() {
    super.initState();
    _loadFromLedger();
    _salaryController.addListener(_recalc);
    _rentalController.addListener(_recalc);
    _interestController.addListener(_recalc);
    _otherIncomeController.addListener(_recalc);
    _stcgController.addListener(_recalc);
    _ltcgController.addListener(_recalc);
  }

  @override
  void dispose() {
    _salaryController.dispose();
    _rentalController.dispose();
    _interestController.dispose();
    _otherIncomeController.dispose();
    _stcgController.dispose();
    _ltcgController.dispose();
    super.dispose();
  }

  void _recalc() {
    setState(() {});
  }

  Future<void> _loadFromLedger() async {
    try {
      final db = DatabaseHelper.instance;

      // 1. Calculate Salary (Income type matching salary subcategories)
      final salResult = await db.rawQuery('''
        SELECT SUM(amount) as total FROM transactions
        WHERE type = 'INCOME' AND category_id LIKE 'cat_salary%' AND is_template = 0
      ''');
      final salTotal = (salResult.first['total'] as num?)?.toDouble() ?? 0.0;

      // 2. Calculate Rental Income
      final rentResult = await db.rawQuery('''
        SELECT SUM(amount) as total FROM transactions
        WHERE type = 'INCOME' AND category_id LIKE 'cat_rental_inc%' AND is_template = 0
      ''');
      final rentTotal = (rentResult.first['total'] as num?)?.toDouble() ?? 0.0;

      // 3. Calculate Interest / Investment Income
      final intResult = await db.rawQuery('''
        SELECT SUM(amount) as total FROM transactions
        WHERE type = 'INCOME' AND category_id LIKE 'cat_investments_inc%' AND is_template = 0
      ''');
      final intTotal = (intResult.first['total'] as num?)?.toDouble() ?? 0.0;

      // 4. Calculate Other Income
      final otherResult = await db.rawQuery('''
        SELECT SUM(amount) as total FROM transactions
        WHERE type = 'INCOME' AND category_id NOT LIKE 'cat_salary%' 
          AND category_id NOT LIKE 'cat_rental_inc%' 
          AND category_id NOT LIKE 'cat_investments_inc%' AND is_template = 0
      ''');
      final otherTotal = (otherResult.first['total'] as num?)?.toDouble() ?? 0.0;

      // 5. Calculate Deductions 80C based on transactions tagged to ELSS/investments
      final ded80CResult = await db.rawQuery('''
        SELECT SUM(amount) as total FROM transactions
        WHERE (category_id LIKE '%investment%' OR category_id LIKE '%education%') AND type = 'EXPENSE' AND is_template = 0
      ''');
      final ded80C = ((ded80CResult.first['total'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 150000.0);

      // 6. Calculate Deductions 80D based on Health insurance premiums
      final ded80DResult = await db.rawQuery('''
        SELECT SUM(amount) as total FROM transactions
        WHERE category_id LIKE '%health%' AND type = 'EXPENSE' AND note LIKE '%insurance%' AND is_template = 0
      ''');
      final ded80D = ((ded80DResult.first['total'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 25000.0);

      if (mounted) {
        setState(() {
          _salaryController.text = salTotal.toStringAsFixed(2);
          _rentalController.text = rentTotal.toStringAsFixed(2);
          _interestController.text = intTotal.toStringAsFixed(2);
          _otherIncomeController.text = otherTotal.toStringAsFixed(2);
          _deductions80C = ded80C;
          _deductions80D = ded80D;
          _deductions80TTA = (intTotal < 10000.0 ? intTotal : 10000.0);
          _loadingLedger = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingLedger = false);
    }
  }

  Future<void> _pickZerodhaCsv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        final gains = ZerodhaCsvParser.parse(content);

        setState(() {
          _importedFileName = result.files.single.name;
          _importedTradeCount = gains.count;
          _importedDividends = gains.dividends;
          _stcgController.text = gains.stcg.toStringAsFixed(2);
          _ltcgController.text = gains.ltcg.toStringAsFixed(2);
          
          if (gains.dividends > 0) {
            final currentOther = double.tryParse(_otherIncomeController.text) ?? 0.0;
            _otherIncomeController.text = (currentOther + gains.dividends).toStringAsFixed(2);
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('📊 Zerodha file imported! STCG: ₹${gains.stcg.toStringAsFixed(2)}, LTCG: ₹${gains.ltcg.toStringAsFixed(2)}'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing statement: $e'), backgroundColor: AppColors.expense),
        );
      }
    }
  }

  void _getAiAdvice() {
    final sal = double.tryParse(_salaryController.text) ?? 0.0;
    final rent = double.tryParse(_rentalController.text) ?? 0.0;
    final interest = double.tryParse(_interestController.text) ?? 0.0;
    final other = double.tryParse(_otherIncomeController.text) ?? 0.0;
    final stcg = double.tryParse(_stcgController.text) ?? 0.0;
    final ltcg = double.tryParse(_ltcgController.text) ?? 0.0;

    final gross = sal + rent + interest + other + stcg + ltcg;
    final oldRegimeTax = IndianTaxEngine.computeOldRegime(gross, _deductions80C, _deductions80D, _deductions80TTA);
    final newRegimeTax = IndianTaxEngine.computeNewRegime(gross);

    final taxReport = '''
Gross Income: ₹${gross.toStringAsFixed(2)}
- Salary Income: ₹${sal.toStringAsFixed(2)}
- Rental Income: ₹${rent.toStringAsFixed(2)}
- Interest Income: ₹${interest.toStringAsFixed(2)}
- Other Incomes: ₹${other.toStringAsFixed(2)}
- Short-Term Capital Gains (STCG): ₹${stcg.toStringAsFixed(2)}
- Long-Term Capital Gains (LTCG): ₹${ltcg.toStringAsFixed(2)}

Deductions Applied (Old Regime):
- Section 80C: ₹${_deductions80C.toStringAsFixed(2)}
- Section 80D (Health): ₹${_deductions80D.toStringAsFixed(2)}
- Section 80TTA (Interest): ₹${_deductions80TTA.toStringAsFixed(2)}

Calculated Liabilities:
- Old Regime Estimated Tax: ₹${oldRegimeTax.toStringAsFixed(2)}
- New Regime Estimated Tax: ₹${newRegimeTax.toStringAsFixed(2)}
''';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AiAdviceSheet(taxReportText: taxReport),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : Colors.white;

    final sal = double.tryParse(_salaryController.text) ?? 0.0;
    final rent = double.tryParse(_rentalController.text) ?? 0.0;
    final interest = double.tryParse(_interestController.text) ?? 0.0;
    final other = double.tryParse(_otherIncomeController.text) ?? 0.0;
    final stcg = double.tryParse(_stcgController.text) ?? 0.0;
    final ltcg = double.tryParse(_ltcgController.text) ?? 0.0;

    final gross = sal + rent + interest + other + stcg + ltcg;
    final oldRegimeTax = IndianTaxEngine.computeOldRegime(gross, _deductions80C, _deductions80D, _deductions80TTA);
    final newRegimeTax = IndianTaxEngine.computeNewRegime(gross);

    final taxSavings = (oldRegimeTax - newRegimeTax).abs();
    final recommendedRegime = oldRegimeTax < newRegimeTax ? 'Old Tax Regime' : 'New Tax Regime';
    final recommendedColor = oldRegimeTax < newRegimeTax ? AppColors.primary : AppColors.success;

    return Scaffold(
      appBar: AppBar(title: const Text('Tax Planner & Advisor')),
      body: _loadingLedger
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Slabs Regime Comparator Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [AppColors.primary.withOpacity(0.2), AppColors.success.withOpacity(0.1)]
                            : [AppColors.primary.withOpacity(0.08), AppColors.success.withOpacity(0.05)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Estimated Tax Comparison',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.lightTextSecondary),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Column(children: [
                              const Text('Old Regime', style: TextStyle(fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(CurrencyFormatter.format(oldRegimeTax),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: oldRegimeTax < newRegimeTax ? AppColors.success : AppColors.expense,
                                  )),
                            ]),
                            Container(width: 1, height: 40, color: Colors.grey.withOpacity(0.3)),
                            Column(children: [
                              const Text('New Regime', style: TextStyle(fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(CurrencyFormatter.format(newRegimeTax),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: newRegimeTax < oldRegimeTax ? AppColors.success : AppColors.expense,
                                  )),
                            ]),
                          ],
                        ),
                        const Divider(height: 24),
                        Text(
                          'Optimal Choice: $recommendedRegime',
                          style: TextStyle(fontWeight: FontWeight.w700, color: recommendedColor, fontSize: 14),
                        ),
                        if (taxSavings > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Saves you ${CurrencyFormatter.format(taxSavings)} in taxes!',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  const SizedBox(height: 16),

                  // Income Card
                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Annual Gross Incomes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const Divider(),
                          _buildIncomeField('Salary Income', _salaryController),
                          _buildIncomeField('Rental Income', _rentalController),
                          _buildIncomeField('Interest Income', _interestController),
                          _buildIncomeField('Other Incomes', _otherIncomeController),
                          _buildIncomeField('Short-Term Gains (STCG)', _stcgController),
                          _buildIncomeField('Long-Term Gains (LTCG)', _ltcgController),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Deductions Card
                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Old Regime Deductions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const Divider(),
                          _buildSliderField(
                            'Section 80C (ELSS, PPF, Life Insurance)',
                            _deductions80C,
                            150000.0,
                            (v) => setState(() => _deductions80C = v),
                          ),
                          _buildSliderField(
                            'Section 80D (Health Insurance Premium)',
                            _deductions80D,
                            25000.0,
                            (v) => setState(() => _deductions80D = v),
                          ),
                          _buildSliderField(
                            'Section 80TTA (Savings Interest Deduction)',
                            _deductions80TTA,
                            10000.0,
                            (v) => setState(() => _deductions80TTA = v),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // AI Advisor trigger button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _getAiAdvice,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.psychology_outlined),
                      label: const Text('Ask AI Tax Copilot', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildIncomeField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  prefixText: '₹',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderField(String label, double val, double max, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
              Text(
                '₹ ${val.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
            ],
          ),
          Slider(
            value: val,
            min: 0,
            max: max,
            divisions: (max / 1000).round(),
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _AiAdviceSheet extends ConsumerStatefulWidget {
  final String taxReportText;
  const _AiAdviceSheet({required this.taxReportText});

  @override
  ConsumerState<_AiAdviceSheet> createState() => _AiAdviceSheetState();
}

class _AiAdviceSheetState extends ConsumerState<_AiAdviceSheet> {
  String _advice = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchAdvice();
  }

  Future<void> _fetchAdvice() async {
    final service = ref.read(aiServiceProvider);
    final response = await service.getTaxAdvice(widget.taxReportText);
    if (mounted) {
      setState(() {
        _advice = response;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkSurface : Colors.white;

    return Container(
      decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.all(20),
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(Icons.psychology, color: AppColors.primary, size: 24),
              SizedBox(width: 8),
              Text('Orbit Tax Insights', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(height: 24),
          Expanded(
            child: _loading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Analyzing slab parameters...', style: TextStyle(fontSize: 13, color: Colors.grey)),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Text(
                      _advice,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close Insights'),
            ),
          ),
        ],
      ),
    );
  }
}
