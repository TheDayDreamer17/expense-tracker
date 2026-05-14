import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import '../../core/db/database_helper.dart';
import '../../core/models/models.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';

class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key});
  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen> {
  List<TripModel> _trips = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.rawQuery('''
      SELECT tr.*, 
        COALESCE(SUM(t.amount), 0) as total_spent,
        COUNT(t.id) as transaction_count
      FROM trips tr
      LEFT JOIN transactions t ON t.trip_id = tr.id AND t.type = 'EXPENSE'
      GROUP BY tr.id ORDER BY tr.start_date DESC
    ''');
    if (mounted) setState(() { _trips = rows.map(TripModel.fromMap).toList(); _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trips'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _showTripSheet)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _trips.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _trips.length,
                    itemBuilder: (_, i) => _TripCard(trip: _trips[i], onTap: () => _openTrip(_trips[i]))
                        .animate().fadeIn(delay: (i * 60).ms),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('✈️', style: TextStyle(fontSize: 64)),
      const SizedBox(height: 16),
      const Text('No trips yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text('Track expenses for your next trip!', style: TextStyle(color: AppColors.lightTextSecondary)),
      const SizedBox(height: 24),
      ElevatedButton.icon(icon: const Icon(Icons.add), label: const Text('Create Trip'), onPressed: _showTripSheet),
    ]));
  }

  void _showTripSheet({TripModel? trip}) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _TripFormSheet(trip: trip, onSaved: _load),
    );
  }

  void _openTrip(TripModel trip) => Navigator.push(context, MaterialPageRoute(builder: (_) => _TripDetailScreen(trip: trip)));
}

class _TripCard extends StatelessWidget {
  final TripModel trip;
  final VoidCallback onTap;
  const _TripCard({required this.trip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Color(trip.color);
    final spent = trip.totalSpent ?? 0;
    final budget = trip.budget;
    final usagePct = budget != null && budget > 0 ? (spent / budget).clamp(0.0, 1.0) : 0.0;
    final budgetColor = usagePct < 0.8 ? AppColors.income : usagePct < 1 ? AppColors.warning : AppColors.expense;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                  child: const Text('✈️', style: TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(trip.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(trip.destination, style: const TextStyle(fontSize: 13, color: AppColors.lightTextSecondary)),
                  Text(
                    '${DateFormatter.formatDateShort(trip.startDate)}${trip.endDate != null ? ' – ${DateFormatter.formatDateShort(trip.endDate!)}' : ''}',
                    style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary),
                  ),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(CurrencyFormatter.formatCompact(spent), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: color)),
                  if (budget != null) Text('of ${CurrencyFormatter.formatCompact(budget)}', style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                  Text('${trip.transactionCount ?? 0} txns', style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                ]),
              ]),
              if (budget != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: usagePct, minHeight: 6,
                    backgroundColor: budgetColor.withOpacity(0.15),
                    valueColor: AlwaysStoppedAnimation(budgetColor),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TripDetailScreen extends StatefulWidget {
  final TripModel trip;
  const _TripDetailScreen({required this.trip});

  @override
  State<_TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<_TripDetailScreen> {
  List<dynamic> _transactions = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.rawQuery('''
      SELECT t.*, c.name as category_name, c.color as category_color
      FROM transactions t LEFT JOIN categories c ON t.category_id = c.id
      WHERE t.trip_id = ? ORDER BY t.date DESC
    ''', [widget.trip.id]);
    if (mounted) setState(() => _transactions = rows);
  }

  double get _totalSpent => _transactions.fold(0.0, (s, t) => s + (t['amount'] as num).toDouble());

  @override
  Widget build(BuildContext context) {
    final color = Color(widget.trip.color);
    return Scaffold(
      appBar: AppBar(title: Text(widget.trip.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, color.withOpacity(0.7)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.trip.destination, style: const TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 4),
              Text(CurrencyFormatter.format(_totalSpent), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
              if (widget.trip.budget != null)
                Text('Budget: ${CurrencyFormatter.format(widget.trip.budget!)}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 16),
          ..._transactions.map((t) => ListTile(
            title: Text(t['category_name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(DateFormatter.formatDate(DateTime.fromMillisecondsSinceEpoch(t['date'] as int))),
            trailing: Text('-${CurrencyFormatter.formatCompact((t['amount'] as num).toDouble())}',
                style: const TextStyle(color: AppColors.expense, fontWeight: FontWeight.w700)),
          )),
        ],
      ),
    );
  }
}

class _TripFormSheet extends StatefulWidget {
  final TripModel? trip;
  final VoidCallback onSaved;
  const _TripFormSheet({this.trip, required this.onSaved});
  @override
  State<_TripFormSheet> createState() => _TripFormSheetState();
}

class _TripFormSheetState extends State<_TripFormSheet> {
  final _nameCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  int _color = 0xFF6C63FF;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.trip != null) {
      _nameCtrl.text = widget.trip!.name;
      _destCtrl.text = widget.trip!.destination;
      _startDate = widget.trip!.startDate;
      _endDate = widget.trip!.endDate;
      _color = widget.trip!.color;
      if (widget.trip!.budget != null) _budgetCtrl.text = widget.trip!.budget!.toStringAsFixed(0);
    }
  }

  @override
  void dispose() { _nameCtrl.dispose(); _destCtrl.dispose(); _budgetCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text(widget.trip == null ? 'Create Trip' : 'Edit Trip', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Trip Name', prefixIcon: Icon(Icons.flight_takeoff))),
          const SizedBox(height: 12),
          TextField(controller: _destCtrl, decoration: const InputDecoration(labelText: 'Destination', prefixIcon: Icon(Icons.location_on_outlined))),
          const SizedBox(height: 12),
          TextField(controller: _budgetCtrl, decoration: const InputDecoration(labelText: 'Budget (optional)', prefixText: '₹ '), keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: InkWell(
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _startDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (d != null) setState(() => _startDate = d);
              },
              child: InputDecorator(decoration: const InputDecoration(labelText: 'Start Date'), child: Text(DateFormatter.formatDateShort(_startDate))),
            )),
            const SizedBox(width: 12),
            Expanded(child: InkWell(
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _endDate ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (d != null) setState(() => _endDate = d);
              },
              child: InputDecorator(decoration: const InputDecoration(labelText: 'End Date'), child: Text(_endDate != null ? DateFormatter.formatDateShort(_endDate!) : 'Not set')),
            )),
          ]),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Text(widget.trip == null ? 'Create Trip' : 'Update'),
          )),
        ]),
      ),
    );
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _destCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    await DatabaseHelper.instance.insert('trips', {
      'id': widget.trip?.id ?? const Uuid().v4(),
      'name': _nameCtrl.text.trim(), 'destination': _destCtrl.text.trim(),
      'start_date': _startDate.millisecondsSinceEpoch,
      'end_date': _endDate?.millisecondsSinceEpoch,
      'budget': double.tryParse(_budgetCtrl.text),
      'color': _color, 'created_at': widget.trip?.createdAt.millisecondsSinceEpoch ?? now,
    });
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }
}
