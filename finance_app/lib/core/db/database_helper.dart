import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'finance_app.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE transactions ADD COLUMN is_template INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE transactions ADD COLUMN next_due_date INTEGER');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE transactions ADD COLUMN parent_recurring_id TEXT');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE accounts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        balance REAL NOT NULL DEFAULT 0,
        currency TEXT NOT NULL DEFAULT 'INR',
        color INTEGER NOT NULL,
        icon TEXT NOT NULL,
        credit_limit REAL,
        statement_day INTEGER,
        payment_day INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        icon TEXT NOT NULL,
        color INTEGER NOT NULL,
        parent_id TEXT,
        FOREIGN KEY (parent_id) REFERENCES categories(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        category_id TEXT,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        date INTEGER NOT NULL,
        note TEXT,
        receipt_path TEXT,
        is_recurring INTEGER NOT NULL DEFAULT 0,
        is_template INTEGER NOT NULL DEFAULT 0,
        next_due_date INTEGER,
        recurrence_rule TEXT,
        trip_id TEXT,
        sms_raw TEXT,
        is_sms_imported INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        parent_recurring_id TEXT,
        FOREIGN KEY (account_id) REFERENCES accounts(id),
        FOREIGN KEY (category_id) REFERENCES categories(id),
        FOREIGN KEY (trip_id) REFERENCES trips(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE audit_logs (
        id TEXT PRIMARY KEY,
        transaction_id TEXT NOT NULL,
        action TEXT NOT NULL,
        before_data TEXT,
        after_data TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (transaction_id) REFERENCES transactions(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE budgets (
        id TEXT PRIMARY KEY,
        category_id TEXT NOT NULL,
        month INTEGER NOT NULL,
        year INTEGER NOT NULL,
        amount REAL NOT NULL,
        FOREIGN KEY (category_id) REFERENCES categories(id),
        UNIQUE(category_id, month, year)
      )
    ''');

    await db.execute('''
      CREATE TABLE trips (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        destination TEXT NOT NULL,
        start_date INTEGER NOT NULL,
        end_date INTEGER,
        budget REAL,
        color INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE goals (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        target_amount REAL NOT NULL,
        saved_amount REAL NOT NULL DEFAULT 0,
        target_date INTEGER,
        monthly_contribution REAL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE subscriptions (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        billing_cycle TEXT NOT NULL,
        next_billing_date INTEGER NOT NULL,
        last_used_date INTEGER,
        icon TEXT NOT NULL,
        category TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE net_worth_entries (
        id TEXT PRIMARY KEY,
        entry_type TEXT NOT NULL,
        sub_type TEXT NOT NULL,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        date INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE streaks (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL UNIQUE,
        current_count INTEGER NOT NULL DEFAULT 0,
        best_count INTEGER NOT NULL DEFAULT 0,
        last_date INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE badges (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL UNIQUE,
        unlocked_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await _insertDefaultData(db);
  }

  Future<void> _insertDefaultData(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Default accounts
    final accounts = [
      {'id': 'acc_cash', 'name': 'Cash', 'type': 'CASH', 'balance': 0.0, 'currency': 'INR', 'color': 0xFF4CAF50, 'icon': 'wallet', 'created_at': now, 'updated_at': now},
      {'id': 'acc_bank', 'name': 'Bank Account', 'type': 'BANK', 'balance': 0.0, 'currency': 'INR', 'color': 0xFF2196F3, 'icon': 'bank', 'created_at': now, 'updated_at': now},
    ];
    for (final a in accounts) {
      await db.insert('accounts', a);
    }

    // Default expense categories
    final expenseCategories = [
      {'id': 'cat_food', 'name': 'Food & Dining', 'type': 'EXPENSE', 'icon': 'food', 'color': 0xFFFF5722},
      {'id': 'cat_grocery', 'name': 'Groceries', 'type': 'EXPENSE', 'icon': 'cart', 'color': 0xFF4CAF50},
      {'id': 'cat_transport', 'name': 'Transport', 'type': 'EXPENSE', 'icon': 'car', 'color': 0xFF2196F3},
      {'id': 'cat_shopping', 'name': 'Shopping', 'type': 'EXPENSE', 'icon': 'bag', 'color': 0xFF9C27B0},
      {'id': 'cat_entertainment', 'name': 'Entertainment', 'type': 'EXPENSE', 'icon': 'tv', 'color': 0xFFE91E63},
      {'id': 'cat_health', 'name': 'Health', 'type': 'EXPENSE', 'icon': 'heart', 'color': 0xFFF44336},
      {'id': 'cat_utilities', 'name': 'Utilities', 'type': 'EXPENSE', 'icon': 'flash', 'color': 0xFFFF9800},
      {'id': 'cat_telecom', 'name': 'Telecom', 'type': 'EXPENSE', 'icon': 'mobile', 'color': 0xFF00BCD4},
      {'id': 'cat_education', 'name': 'Education', 'type': 'EXPENSE', 'icon': 'book', 'color': 0xFF3F51B5},
      {'id': 'cat_subscription', 'name': 'Subscriptions', 'type': 'EXPENSE', 'icon': 'refresh', 'color': 0xFF607D8B},
      {'id': 'cat_travel', 'name': 'Travel', 'type': 'EXPENSE', 'icon': 'plane', 'color': 0xFF009688},
      {'id': 'cat_other_exp', 'name': 'Others', 'type': 'EXPENSE', 'icon': 'dots', 'color': 0xFF9E9E9E},
    ];

    // Default income categories
    final incomeCategories = [
      {'id': 'cat_salary', 'name': 'Salary', 'type': 'INCOME', 'icon': 'money', 'color': 0xFF4CAF50},
      {'id': 'cat_freelance', 'name': 'Freelance', 'type': 'INCOME', 'icon': 'laptop', 'color': 0xFF2196F3},
      {'id': 'cat_business', 'name': 'Business', 'type': 'INCOME', 'icon': 'briefcase', 'color': 0xFF9C27B0},
      {'id': 'cat_investment', 'name': 'Investment', 'type': 'INCOME', 'icon': 'chart', 'color': 0xFFFF9800},
      {'id': 'cat_gift', 'name': 'Gift', 'type': 'INCOME', 'icon': 'gift', 'color': 0xFFE91E63},
      {'id': 'cat_other_inc', 'name': 'Others', 'type': 'INCOME', 'icon': 'dots', 'color': 0xFF9E9E9E},
    ];

    for (final c in [...expenseCategories, ...incomeCategories]) {
      await db.insert('categories', c);
    }

    // Default settings
    final settings = [
      {'key': 'theme', 'value': 'system'},
      {'key': 'currency', 'value': 'INR'},
      {'key': 'currency_symbol', 'value': '₹'},
      {'key': 'default_account', 'value': 'acc_cash'},
      {'key': 'income_reminder_enabled', 'value': 'true'},
      {'key': 'income_reminder_time', 'value': '09:00'},
      {'key': 'pin_enabled', 'value': 'false'},
      {'key': 'biometric_enabled', 'value': 'false'},
      {'key': 'onboarding_done', 'value': 'false'},
    ];
    for (final s in settings) {
      await db.insert('settings', s);
    }

    // Default streaks
    final streaks = [
      {'id': 'streak_nospend', 'type': 'NO_SPEND', 'current_count': 0, 'best_count': 0},
      {'id': 'streak_saving', 'type': 'SAVING', 'current_count': 0, 'best_count': 0},
    ];
    for (final s in streaks) {
      await db.insert('streaks', s);
    }
  }

  // ─── Generic helpers ───────────────────────────────────────
  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    final db = await database;
    return db.query(table, where: where, whereArgs: whereArgs, orderBy: orderBy, limit: limit);
  }

  Future<int> insert(String table, Map<String, dynamic> values) async {
    final db = await database;
    final res = await db.insert(table, values, conflictAlgorithm: ConflictAlgorithm.replace);
    _triggerAutoBackup();
    return res;
  }

  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    required String where,
    required List<dynamic> whereArgs,
  }) async {
    final db = await database;
    final res = await db.update(table, values, where: where, whereArgs: whereArgs);
    _triggerAutoBackup();
    return res;
  }

  Future<int> delete(
    String table, {
    required String where,
    required List<dynamic> whereArgs,
  }) async {
    final db = await database;
    final res = await db.delete(table, where: where, whereArgs: whereArgs);
    _triggerAutoBackup();
    return res;
  }

  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<dynamic>? args]) async {
    final db = await database;
    return db.rawQuery(sql, args);
  }

  bool _isBackupScheduled = false;

  void _triggerAutoBackup() {
    if (_isBackupScheduled) return;
    _isBackupScheduled = true;

    Future.delayed(const Duration(seconds: 5), () async {
      _isBackupScheduled = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        final enabled = prefs.getBool('local_auto_backup_enabled') ?? true;
        if (!enabled) return;

        final data = {
          'exported_at': DateTime.now().toIso8601String(),
          'version': '1.0.0',
          'accounts': await query('accounts'),
          'categories': await query('categories'),
          'transactions': await query('transactions'),
          'budgets': await query('budgets'),
          'trips': await query('trips'),
          'goals': await query('goals'),
          'subscriptions': await query('subscriptions'),
          'net_worth_entries': await query('net_worth_entries'),
        };
        final json = const JsonEncoder().convert(data);

        await const MethodChannel('com.example.finance_app/sms_methods')
            .invokeMethod('saveBackupToDownloads', {
          'json': json,
          'fileName': 'smart_money_backup.json',
        });
      } catch (_) {}
    });
  }
}
