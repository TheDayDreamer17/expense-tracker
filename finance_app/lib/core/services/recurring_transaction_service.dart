import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';

/// Checks all recurring transactions and creates new ones if their next due date has passed.
/// Call this from main.dart on app startup.
class RecurringTransactionService {
  static final RecurringTransactionService instance = RecurringTransactionService._();
  RecurringTransactionService._();

  Future<int> processOverdue() async {
    final db = DatabaseHelper.instance;
    int count = 0;

    // Find all templates (is_recurring = 1, is_template = 1)
    final templates = await db.query(
      'transactions',
      where: 'is_recurring = 1 AND is_template = 1',
    );

    final now = DateTime.now();

    for (final t in templates) {
      final nextDue = DateTime.fromMillisecondsSinceEpoch(t['next_due_date'] as int? ?? 0);
      if (nextDue.isAfter(now)) continue;

      // Create the actual transaction
      final newId = const Uuid().v4();
      final ts = now.millisecondsSinceEpoch;
      await db.insert('transactions', {
        'id': newId,
        'account_id': t['account_id'],
        'category_id': t['category_id'],
        'amount': t['amount'],
        'type': t['type'],
        'date': nextDue.millisecondsSinceEpoch,
        'note': t['note'],
        'is_recurring': 0,
        'is_template': 0,
        'is_sms_imported': 0,
        'trip_id': t['trip_id'],
        'created_at': ts,
        'updated_at': ts,
        'parent_recurring_id': t['id'],
      });

      // Advance the next_due_date on the template
      final rule = t['recurrence_rule'] as String? ?? 'MONTHLY';
      final nextDate = _nextDate(nextDue, rule);
      await db.update(
        'transactions',
        {'next_due_date': nextDate.millisecondsSinceEpoch, 'updated_at': ts},
        where: 'id = ?',
        whereArgs: [t['id']],
      );

      // Update account balance
      await _updateBalance(t['account_id'] as String, (t['amount'] as num).toDouble(), t['type'] as String);

      count++;
    }

    return count;
  }

  DateTime _nextDate(DateTime from, String rule) {
    return switch (rule) {
      'DAILY'   => from.add(const Duration(days: 1)),
      'WEEKLY'  => from.add(const Duration(days: 7)),
      'MONTHLY' => DateTime(from.year, from.month + 1, from.day, from.hour, from.minute),
      'YEARLY'  => DateTime(from.year + 1, from.month, from.day, from.hour, from.minute),
      _         => from.add(const Duration(days: 30)),
    };
  }

  Future<void> _updateBalance(String accountId, double amount, String type) async {
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
}
