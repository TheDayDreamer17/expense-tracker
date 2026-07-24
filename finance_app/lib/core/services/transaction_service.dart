import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import '../db/database_helper.dart';
import '../models/transaction_model.dart';

class TransactionService {
  static final TransactionService instance = TransactionService._();
  TransactionService._();

  /// Creates a transaction and atomically updates affected account balances.
  Future<void> createTransaction(TransactionModel tx) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // 1. Insert transaction row
      await txn.insert('transactions', tx.toMap(), conflictAlgorithm: ConflictAlgorithm.fail);
      
      // 2. Insert audit log
      await txn.insert('audit_logs', {
        'id': const Uuid().v4(),
        'transaction_id': tx.id,
        'action': 'CREATE',
        'after_data': tx.toMap().toString(),
        'created_at': now,
      });
      
      // 3. Update account balances
      if (tx.isTemplate) {
        // Templates do not affect active balances!
        return;
      }
      
      if (tx.isTransfer) {
        await _adjustBalance(txn, tx.accountId, -tx.amount);
        if (tx.toAccountId != null) {
          await _adjustBalance(txn, tx.toAccountId!, tx.amount);
        }
      } else if (tx.isExpense) {
        await _adjustBalance(txn, tx.accountId, -tx.amount);
      } else if (tx.isIncome) {
        await _adjustBalance(txn, tx.accountId, tx.amount);
      }
    });
  }

  /// Updates an existing transaction by reversing the old balance first,
  /// then applying the new parameters.
  Future<void> updateTransaction(TransactionModel oldTx, TransactionModel newTx) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Reverse old transaction balances (if old transaction was not a template)
      if (!oldTx.isTemplate) {
        if (oldTx.isTransfer) {
          await _adjustBalance(txn, oldTx.accountId, oldTx.amount);
          if (oldTx.toAccountId != null) {
            await _adjustBalance(txn, oldTx.toAccountId!, -oldTx.amount);
          }
        } else if (oldTx.isExpense) {
          await _adjustBalance(txn, oldTx.accountId, oldTx.amount);
        } else if (oldTx.isIncome) {
          await _adjustBalance(txn, oldTx.accountId, -oldTx.amount);
        }
      }

      // 2. Update transaction row
      await txn.update('transactions', newTx.toMap(), where: 'id = ?', whereArgs: [newTx.id]);

      // 3. Insert audit log
      await txn.insert('audit_logs', {
        'id': const Uuid().v4(),
        'transaction_id': newTx.id,
        'action': 'UPDATE',
        'before_data': oldTx.toMap().toString(),
        'after_data': newTx.toMap().toString(),
        'created_at': now,
      });

      // 4. Apply new transaction balances (if new transaction is not a template)
      if (!newTx.isTemplate) {
        if (newTx.isTransfer) {
          await _adjustBalance(txn, newTx.accountId, -newTx.amount);
          if (newTx.toAccountId != null) {
            await _adjustBalance(txn, newTx.toAccountId!, newTx.amount);
          }
        } else if (newTx.isExpense) {
          await _adjustBalance(txn, newTx.accountId, -newTx.amount);
        } else if (newTx.isIncome) {
          await _adjustBalance(txn, newTx.accountId, newTx.amount);
        }
      }
    });
  }

  /// Deletes a transaction and reverses its balance adjustments.
  Future<void> deleteTransaction(TransactionModel tx) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Delete row
      await txn.delete('transactions', where: 'id = ?', whereArgs: [tx.id]);

      // 2. Insert audit log
      await txn.insert('audit_logs', {
        'id': const Uuid().v4(),
        'transaction_id': tx.id,
        'action': 'DELETE',
        'before_data': tx.toMap().toString(),
        'created_at': now,
      });

      // 3. Reverse balances (if not template)
      if (!tx.isTemplate) {
        if (tx.isTransfer) {
          await _adjustBalance(txn, tx.accountId, tx.amount);
          if (tx.toAccountId != null) {
            await _adjustBalance(txn, tx.toAccountId!, -tx.amount);
          }
        } else if (tx.isExpense) {
          await _adjustBalance(txn, tx.accountId, tx.amount);
        } else if (tx.isIncome) {
          await _adjustBalance(txn, tx.accountId, -tx.amount);
        }
      }
    });
  }

  /// Rebuilds all cached account balances from the transaction ledger.
  /// Used for verification, reconciliation, and database upgrades.
  Future<void> rebuildBalances() async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      // 1. Reset all balances to 0
      await txn.update('accounts', {'balance': 0.0});
      
      // 2. Fetch all non-template transactions
      final txs = await txn.query('transactions', where: 'is_template = 0');
      
      // 3. Re-calculate and apply
      for (final row in txs) {
        final tx = TransactionModel.fromMap(row);
        if (tx.isTransfer) {
          await _adjustBalance(txn, tx.accountId, -tx.amount);
          if (tx.toAccountId != null) {
            await _adjustBalance(txn, tx.toAccountId!, tx.amount);
          }
        } else if (tx.isExpense) {
          await _adjustBalance(txn, tx.accountId, -tx.amount);
        } else if (tx.isIncome) {
          await _adjustBalance(txn, tx.accountId, tx.amount);
        }
      }
    });
  }

  Future<void> _adjustBalance(Transaction txn, String accountId, double adjustment) async {
    final List<Map<String, dynamic>> rows = await txn.query('accounts', where: 'id = ?', whereArgs: [accountId]);
    if (rows.isEmpty) return;
    final current = (rows.first['balance'] as num).toDouble();
    await txn.update(
      'accounts',
      {'balance': current + adjustment, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [accountId],
    );
  }
}
