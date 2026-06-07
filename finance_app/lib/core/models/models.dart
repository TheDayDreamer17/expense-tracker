class AccountModel {
  final String id;
  final String name;
  final String type; // CASH | BANK | CREDIT_CARD | LOAN | INVESTMENT
  final double balance;
  final String currency;
  final int color;
  final String icon;
  final double? creditLimit;
  final int? statementDay;
  final int? paymentDay;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AccountModel({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    this.currency = 'INR',
    required this.color,
    required this.icon,
    this.creditLimit,
    this.statementDay,
    this.paymentDay,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AccountModel.fromMap(Map<String, dynamic> map) {
    return AccountModel(
      id: map['id'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      balance: (map['balance'] as num).toDouble(),
      currency: map['currency'] as String? ?? 'INR',
      color: map['color'] as int,
      icon: map['icon'] as String,
      creditLimit: map['credit_limit'] != null ? (map['credit_limit'] as num).toDouble() : null,
      statementDay: map['statement_day'] as int?,
      paymentDay: map['payment_day'] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'balance': balance,
      'currency': currency,
      'color': color,
      'icon': icon,
      'credit_limit': creditLimit,
      'statement_day': statementDay,
      'payment_day': paymentDay,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  AccountModel copyWith({
    String? id, String? name, String? type, double? balance,
    String? currency, int? color, String? icon, double? creditLimit,
    int? statementDay, int? paymentDay,
    DateTime? createdAt, DateTime? updatedAt,
  }) {
    return AccountModel(
      id: id ?? this.id, name: name ?? this.name, type: type ?? this.type,
      balance: balance ?? this.balance, currency: currency ?? this.currency,
      color: color ?? this.color, icon: icon ?? this.icon,
      creditLimit: creditLimit ?? this.creditLimit,
      statementDay: statementDay ?? this.statementDay,
      paymentDay: paymentDay ?? this.paymentDay,
      createdAt: createdAt ?? this.createdAt, updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class CategoryModel {
  final String id;
  final String name;
  final String type; // INCOME | EXPENSE
  final String icon;
  final int color;
  final String? parentId;
  final List<CategoryModel> children;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
    this.parentId,
    this.children = const [],
  });

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      icon: map['icon'] as String,
      color: map['color'] as int,
      parentId: map['parent_id'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id, 'name': name, 'type': type,
      'icon': icon, 'color': color, 'parent_id': parentId,
    };
  }

  bool get isExpense => type == 'EXPENSE';
  bool get isIncome => type == 'INCOME';
}

class BudgetModel {
  final String id;
  final String categoryId;
  final int month;
  final int year;
  final double amount;

  // Joined
  final String? categoryName;
  final String? categoryIcon;
  final int? categoryColor;
  final double? spent;

  const BudgetModel({
    required this.id,
    required this.categoryId,
    required this.month,
    required this.year,
    required this.amount,
    this.categoryName,
    this.categoryIcon,
    this.categoryColor,
    this.spent,
  });

  factory BudgetModel.fromMap(Map<String, dynamic> map) {
    return BudgetModel(
      id: map['id'] as String,
      categoryId: map['category_id'] as String,
      month: map['month'] as int,
      year: map['year'] as int,
      amount: (map['amount'] as num).toDouble(),
      categoryName: map['category_name'] as String?,
      categoryIcon: map['category_icon'] as String?,
      categoryColor: map['category_color'] as int?,
      spent: map['spent'] != null ? (map['spent'] as num).toDouble() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id, 'category_id': categoryId,
      'month': month, 'year': year, 'amount': amount,
    };
  }

  double get usagePercent => spent != null && amount > 0 ? (spent! / amount) : 0;
  double get remaining => amount - (spent ?? 0);
}

class TripModel {
  final String id;
  final String name;
  final String destination;
  final DateTime startDate;
  final DateTime? endDate;
  final double? budget;
  final int color;
  final DateTime createdAt;

  // Joined
  final double? totalSpent;
  final int? transactionCount;

  const TripModel({
    required this.id,
    required this.name,
    required this.destination,
    required this.startDate,
    this.endDate,
    this.budget,
    required this.color,
    required this.createdAt,
    this.totalSpent,
    this.transactionCount,
  });

  factory TripModel.fromMap(Map<String, dynamic> map) {
    return TripModel(
      id: map['id'] as String,
      name: map['name'] as String,
      destination: map['destination'] as String,
      startDate: DateTime.fromMillisecondsSinceEpoch(map['start_date'] as int),
      endDate: map['end_date'] != null ? DateTime.fromMillisecondsSinceEpoch(map['end_date'] as int) : null,
      budget: map['budget'] != null ? (map['budget'] as num).toDouble() : null,
      color: map['color'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      totalSpent: map['total_spent'] != null ? (map['total_spent'] as num).toDouble() : null,
      transactionCount: map['transaction_count'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id, 'name': name, 'destination': destination,
      'start_date': startDate.millisecondsSinceEpoch,
      'end_date': endDate?.millisecondsSinceEpoch,
      'budget': budget, 'color': color,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }
}

class GoalModel {
  final String id;
  final String name;
  final String icon;
  final double targetAmount;
  final double savedAmount;
  final DateTime? targetDate;
  final double? monthlyContribution;
  final DateTime createdAt;

  const GoalModel({
    required this.id,
    required this.name,
    required this.icon,
    required this.targetAmount,
    required this.savedAmount,
    this.targetDate,
    this.monthlyContribution,
    required this.createdAt,
  });

  factory GoalModel.fromMap(Map<String, dynamic> map) {
    return GoalModel(
      id: map['id'] as String,
      name: map['name'] as String,
      icon: map['icon'] as String,
      targetAmount: (map['target_amount'] as num).toDouble(),
      savedAmount: (map['saved_amount'] as num).toDouble(),
      targetDate: map['target_date'] != null ? DateTime.fromMillisecondsSinceEpoch(map['target_date'] as int) : null,
      monthlyContribution: map['monthly_contribution'] != null ? (map['monthly_contribution'] as num).toDouble() : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id, 'name': name, 'icon': icon,
      'target_amount': targetAmount, 'saved_amount': savedAmount,
      'target_date': targetDate?.millisecondsSinceEpoch,
      'monthly_contribution': monthlyContribution,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  double get progressPercent => targetAmount > 0 ? (savedAmount / targetAmount).clamp(0, 1) : 0;
  double get remaining => (targetAmount - savedAmount).clamp(0, double.infinity);

  int? get monthsToGoal {
    if (monthlyContribution == null || monthlyContribution! <= 0) return null;
    if (remaining <= 0) return 0;
    return (remaining / monthlyContribution!).ceil();
  }
}

class SubscriptionModel {
  final String id;
  final String name;
  final double amount;
  final String billingCycle; // MONTHLY | YEARLY
  final DateTime nextBillingDate;
  final DateTime? lastUsedDate;
  final String icon;
  final String category;
  final DateTime createdAt;

  const SubscriptionModel({
    required this.id,
    required this.name,
    required this.amount,
    required this.billingCycle,
    required this.nextBillingDate,
    this.lastUsedDate,
    required this.icon,
    required this.category,
    required this.createdAt,
  });

  factory SubscriptionModel.fromMap(Map<String, dynamic> map) {
    return SubscriptionModel(
      id: map['id'] as String,
      name: map['name'] as String,
      amount: (map['amount'] as num).toDouble(),
      billingCycle: map['billing_cycle'] as String,
      nextBillingDate: DateTime.fromMillisecondsSinceEpoch(map['next_billing_date'] as int),
      lastUsedDate: map['last_used_date'] != null ? DateTime.fromMillisecondsSinceEpoch(map['last_used_date'] as int) : null,
      icon: map['icon'] as String,
      category: map['category'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id, 'name': name, 'amount': amount,
      'billing_cycle': billingCycle,
      'next_billing_date': nextBillingDate.millisecondsSinceEpoch,
      'last_used_date': lastUsedDate?.millisecondsSinceEpoch,
      'icon': icon, 'category': category,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  int get daysSinceLastUsed {
    if (lastUsedDate == null) return 999;
    return DateTime.now().difference(lastUsedDate!).inDays;
  }

  int get daysUntilBilling => nextBillingDate.difference(DateTime.now()).inDays;
  bool get isUnused => daysSinceLastUsed > 14;
}

class NetWorthEntry {
  final String id;
  final String entryType; // ASSET | LIABILITY
  final String subType;   // FD | MF | STOCK | GOLD | BANK | LOAN | CREDIT_CARD | etc.
  final String name;
  final double amount;
  final DateTime date;

  const NetWorthEntry({
    required this.id,
    required this.entryType,
    required this.subType,
    required this.name,
    required this.amount,
    required this.date,
  });

  factory NetWorthEntry.fromMap(Map<String, dynamic> map) {
    return NetWorthEntry(
      id: map['id'] as String,
      entryType: map['entry_type'] as String,
      subType: map['sub_type'] as String,
      name: map['name'] as String,
      amount: (map['amount'] as num).toDouble(),
      date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id, 'entry_type': entryType, 'sub_type': subType,
      'name': name, 'amount': amount, 'date': date.millisecondsSinceEpoch,
    };
  }

  bool get isAsset => entryType == 'ASSET';
  bool get isLiability => entryType == 'LIABILITY';
}

class ParsedSmsTransaction {
  final String? id;
  final double amount;
  final String type; // INCOME | EXPENSE
  final String? merchant;
  final String? accountLast4;
  final double? balance;
  final String suggestedCategory;
  final String smsRaw;
  final String sender;

  const ParsedSmsTransaction({
    this.id,
    required this.amount,
    required this.type,
    this.merchant,
    this.accountLast4,
    this.balance,
    required this.suggestedCategory,
    required this.smsRaw,
    required this.sender,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'type': type,
      'merchant': merchant,
      'accountLast4': accountLast4,
      'balance': balance,
      'suggestedCategory': suggestedCategory,
      'smsRaw': smsRaw,
      'sender': sender,
    };
  }

  factory ParsedSmsTransaction.fromMap(Map<String, dynamic> map) {
    return ParsedSmsTransaction(
      id: map['id'] as String?,
      amount: (map['amount'] as num).toDouble(),
      type: map['type'] as String,
      merchant: map['merchant'] as String?,
      accountLast4: map['accountLast4'] as String?,
      balance: map['balance'] != null ? (map['balance'] as num).toDouble() : null,
      suggestedCategory: map['suggestedCategory'] as String,
      smsRaw: map['smsRaw'] as String,
      sender: map['sender'] as String,
    );
  }
}
