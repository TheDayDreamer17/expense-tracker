import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/transaction_model.dart';
import 'transaction_service.dart';

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

      // Create the actual transaction occurrence
      final newId = const Uuid().v4();
      final ts = now.millisecondsSinceEpoch;
      
      final newTx = TransactionModel(
        id: newId,
        accountId: t['account_id'] as String,
        toAccountId: t['to_account_id'] as String?,
        categoryId: t['category_id'] as String?,
        amount: (t['amount'] as num).toDouble(),
        type: t['type'] as String,
        date: nextDue,
        note: t['note'] as String?,
        isRecurring: false,
        isTemplate: false,
        tripId: t['trip_id'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(ts),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(ts),
        parentRecurringId: t['id'] as String?,
      );

      await TransactionService.instance.createTransaction(newTx);

      // Advance the next_due_date on the template row in the db
      final rule = t['recurrence_rule'] as String? ?? 'MONTHLY';
      final nextDate = _nextDate(nextDue, rule);
      final rawDb = await DatabaseHelper.instance.database;
      await rawDb.update(
        'transactions',
        {'next_due_date': nextDate.millisecondsSinceEpoch, 'updated_at': ts},
        where: 'id = ?',
        whereArgs: [t['id']],
      );

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
}
