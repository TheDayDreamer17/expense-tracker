class TransactionModel {
  final String id;
  final String accountId;
  final String? categoryId;
  final double amount;
  final String type; // INCOME | EXPENSE | TRANSFER
  final DateTime date;
  final String? note;
  final String? receiptPath;
  final bool isRecurring;
  final String? recurrenceRule;
  final String? tripId;
  final String? smsRaw;
  final bool isSmsImported;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined fields (not stored in transactions table)
  final String? categoryName;
  final String? categoryIcon;
  final int? categoryColor;
  final String? accountName;
  final String? tripName;

  const TransactionModel({
    required this.id,
    required this.accountId,
    this.categoryId,
    required this.amount,
    required this.type,
    required this.date,
    this.note,
    this.receiptPath,
    this.isRecurring = false,
    this.recurrenceRule,
    this.tripId,
    this.smsRaw,
    this.isSmsImported = false,
    required this.createdAt,
    required this.updatedAt,
    this.categoryName,
    this.categoryIcon,
    this.categoryColor,
    this.accountName,
    this.tripName,
  });

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'] as String,
      accountId: map['account_id'] as String,
      categoryId: map['category_id'] as String?,
      amount: (map['amount'] as num).toDouble(),
      type: map['type'] as String,
      date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
      note: map['note'] as String?,
      receiptPath: map['receipt_path'] as String?,
      isRecurring: (map['is_recurring'] as int) == 1,
      recurrenceRule: map['recurrence_rule'] as String?,
      tripId: map['trip_id'] as String?,
      smsRaw: map['sms_raw'] as String?,
      isSmsImported: (map['is_sms_imported'] as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      categoryName: map['category_name'] as String?,
      categoryIcon: map['category_icon'] as String?,
      categoryColor: map['category_color'] as int?,
      accountName: map['account_name'] as String?,
      tripName: map['trip_name'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'account_id': accountId,
      'category_id': categoryId,
      'amount': amount,
      'type': type,
      'date': date.millisecondsSinceEpoch,
      'note': note,
      'receipt_path': receiptPath,
      'is_recurring': isRecurring ? 1 : 0,
      'recurrence_rule': recurrenceRule,
      'trip_id': tripId,
      'sms_raw': smsRaw,
      'is_sms_imported': isSmsImported ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  TransactionModel copyWith({
    String? id,
    String? accountId,
    String? categoryId,
    double? amount,
    String? type,
    DateTime? date,
    String? note,
    String? receiptPath,
    bool? isRecurring,
    String? recurrenceRule,
    String? tripId,
    String? smsRaw,
    bool? isSmsImported,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? categoryName,
    String? categoryIcon,
    int? categoryColor,
    String? accountName,
    String? tripName,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      categoryId: categoryId ?? this.categoryId,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      date: date ?? this.date,
      note: note ?? this.note,
      receiptPath: receiptPath ?? this.receiptPath,
      isRecurring: isRecurring ?? this.isRecurring,
      recurrenceRule: recurrenceRule ?? this.recurrenceRule,
      tripId: tripId ?? this.tripId,
      smsRaw: smsRaw ?? this.smsRaw,
      isSmsImported: isSmsImported ?? this.isSmsImported,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      categoryName: categoryName ?? this.categoryName,
      categoryIcon: categoryIcon ?? this.categoryIcon,
      categoryColor: categoryColor ?? this.categoryColor,
      accountName: accountName ?? this.accountName,
      tripName: tripName ?? this.tripName,
    );
  }

  bool get isExpense => type == 'EXPENSE';
  bool get isIncome => type == 'INCOME';
  bool get isTransfer => type == 'TRANSFER';
}
