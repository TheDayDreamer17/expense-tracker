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
    await ensureStandardCategoriesExist(_database!);
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

  static List<Map<String, dynamic>> getStandardCategories() {
    final list = <Map<String, dynamic>>[];
    
    void addGroup(String id, String name, String type, String icon, int color, List<String> children) {
      list.add({
        'id': id,
        'name': name,
        'type': type,
        'icon': icon,
        'color': color,
        'parent_id': null,
      });
      for (final child in children) {
        final childId = '${id}_${child.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
        list.add({
          'id': childId,
          'name': child,
          'type': type,
          'icon': icon,
          'color': color,
          'parent_id': id,
        });
      }
    }

    // EXPENSES
    addGroup('cat_housing', 'Housing', 'EXPENSE', 'home', 0xFF795548, [
      'Rent', 'Home Loan EMI', 'Maintenance Charges', 'Property Tax',
      'Repairs & Renovation', 'Furniture', 'Appliances'
    ]);
    addGroup('cat_utilities', 'Utilities', 'EXPENSE', 'flash', 0xFFFF9800, [
      'Electricity', 'Water', 'Gas', 'Internet/WiFi', 'Mobile Recharge', 'DTH/Cable'
    ]);
    addGroup('cat_food', 'Food & Dining', 'EXPENSE', 'food', 0xFFFF5722, [
      'Groceries', 'Vegetables & Fruits', 'Milk & Dairy', 'Restaurants', 'Fast Food', 'Cafes', 'Food Delivery (Swiggy/Zomato)'
    ]);
    addGroup('cat_transport', 'Transportation', 'EXPENSE', 'car', 0xFF2196F3, [
      'Fuel/Petrol', 'Public Transport', 'Metro', 'Bus', 'Auto/Rickshaw',
      'Taxi/Uber/Ola', 'Parking', 'Toll Charges', 'Vehicle Maintenance', 'Vehicle Insurance'
    ]);
    addGroup('cat_health', 'Health & Fitness', 'EXPENSE', 'heart', 0xFFE91E63, [
      'Doctor Consultation', 'Medicines', 'Health Insurance', 'Lab Tests',
      'Gym Membership', 'Yoga', 'Supplements', 'Protein Powder'
    ]);
    addGroup('cat_shopping', 'Shopping', 'EXPENSE', 'bag', 0xFF9C27B0, [
      'Clothing', 'Footwear', 'Accessories', 'Electronics', 'Gadgets', 'Home Decor', 'Gifts'
    ]);
    addGroup('cat_entertainment', 'Entertainment', 'EXPENSE', 'tv', 0xFF673AB7, [
      'Movies', 'OTT Subscriptions', 'Gaming', 'Books', 'Music', 'Hobbies'
    ]);
    addGroup('cat_travel', 'Travel', 'EXPENSE', 'plane', 0xFF009688, [
      'Flights', 'Hotels', 'Local Transport', 'Sightseeing', 'Travel Insurance'
    ]);
    addGroup('cat_education', 'Education', 'EXPENSE', 'book', 0xFF3F51B5, [
      'Courses', 'Certifications', 'Books', 'Workshops', 'Coaching'
    ]);
    addGroup('cat_pets', 'Pets', 'EXPENSE', 'dog', 0xFF4CAF50, [
      'Pet Food', 'Vet Expenses', 'Grooming', 'Accessories'
    ]);
    addGroup('cat_family', 'Family', 'EXPENSE', 'people', 0xFF00BCD4, [
      'Parents Support', 'Child Education', 'Child Care', 'Family Medical'
    ]);
    addGroup('cat_financial', 'Financial', 'EXPENSE', 'card', 0xFF607D8B, [
      'Credit Card Bill', 'Loan EMI', 'Bank Charges', 'Interest Paid', 'Late Fees'
    ]);
    addGroup('cat_personal', 'Personal', 'EXPENSE', 'face', 0xFFFFC107, [
      'Grooming', 'Salon', 'Spa', 'Cosmetics', 'Personal Care'
    ]);
    addGroup('cat_donations', 'Donations', 'EXPENSE', 'heart', 0xFF8BC34A, [
      'Charity', 'Religious Donations', 'Crowdfunding'
    ]);
    addGroup('cat_other_exp', 'Miscellaneous', 'EXPENSE', 'dots', 0xFF9E9E9E, [
      'Unknown', 'Misc Expense', 'Cash Withdrawal'
    ]);

    // INCOMES
    addGroup('cat_salary', 'Salary', 'INCOME', 'money', 0xFF4CAF50, [
      'Salary', 'Bonus', 'Incentives', 'Overtime', 'Joining Bonus'
    ]);
    addGroup('cat_freelance', 'Freelancing', 'INCOME', 'laptop', 0xFF2196F3, [
      'Consulting', 'Freelance Projects', 'Side Hustle'
    ]);
    addGroup('cat_investments_inc', 'Investments', 'INCOME', 'chart', 0xFFFF9800, [
      'Dividends', 'Interest Income', 'Capital Gains', 'Mutual Fund Redemption', 'Stock Profit'
    ]);
    addGroup('cat_rental_inc', 'Rental Income', 'INCOME', 'home', 0xFF795548, [
      'House Rent Received', 'Commercial Rent'
    ]);
    addGroup('cat_other_inc', 'Other Income', 'INCOME', 'dots', 0xFF9E9E9E, [
      'Gift Received', 'Cashback', 'Rewards', 'Referral Bonus', 'Tax Refund'
    ]);
    addGroup('cat_family_inc', 'Family', 'INCOME', 'people', 0xFF00BCD4, [
      'Family Support', 'Pocket Money'
    ]);
    addGroup('cat_business_inc', 'Business', 'INCOME', 'briefcase', 0xFF9C27B0, [
      'Business Revenue', 'Commission', 'Royalties'
    ]);

    // TRANSFERS
    addGroup('cat_transfer', 'Transfer', 'TRANSFER', 'refresh', 0xFF607D8B, [
      'Bank to Bank Transfer', 'Savings Transfer', 'Investment Transfer', 'Wallet Top-up',
      'Credit Card Payment', 'Cash Deposit', 'Cash Withdrawal', 'UPI Wallet Transfer'
    ]);

    return list;
  }

  Future<void> ensureStandardCategoriesExist(Database db) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seeded = prefs.getBool('seeded_detailed_categories') ?? false;
      if (!seeded) {
        final list = getStandardCategories();
        final batch = db.batch();
        for (final cat in list) {
          batch.insert('categories', cat, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
        await prefs.setBool('seeded_detailed_categories', true);
      }
    } catch (_) {}
  }

  Future<void> _insertDefaultData(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Default accounts
    final accounts = [
      {'id': 'acc_cash', 'name': 'Cash', 'type': 'CASH', 'balance': 0.0, 'currency': 'INR', 'color': 0xFF4CAF50, 'icon': 'wallet', 'created_at': now, 'updated_at': now},
      {'id': 'acc_sbi', 'name': 'SBI', 'type': 'BANK', 'balance': 0.0, 'currency': 'INR', 'color': 0xFF2196F3, 'icon': 'bank', 'created_at': now, 'updated_at': now},
      {'id': 'acc_hdfc', 'name': 'HDFC', 'type': 'BANK', 'balance': 0.0, 'currency': 'INR', 'color': 0xFF3F51B5, 'icon': 'bank', 'created_at': now, 'updated_at': now},
      {'id': 'acc_icici', 'name': 'ICICI', 'type': 'BANK', 'balance': 0.0, 'currency': 'INR', 'color': 0xFF00BCD4, 'icon': 'bank', 'created_at': now, 'updated_at': now},
      {'id': 'acc_pnb', 'name': 'PNB', 'type': 'BANK', 'balance': 0.0, 'currency': 'INR', 'color': 0xFFFF5722, 'icon': 'bank', 'created_at': now, 'updated_at': now},
      {'id': 'acc_cc', 'name': 'Credit Card', 'type': 'CREDIT_CARD', 'balance': 0.0, 'currency': 'INR', 'color': 0xFFE91E63, 'icon': 'card', 'created_at': now, 'updated_at': now},
      {'id': 'acc_investments', 'name': 'Investments', 'type': 'INVESTMENT', 'balance': 0.0, 'currency': 'INR', 'color': 0xFF4CAF50, 'icon': 'chart', 'created_at': now, 'updated_at': now},
    ];
    for (final a in accounts) {
      await db.insert('accounts', a);
    }

    final list = getStandardCategories();
    for (final c in list) {
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
