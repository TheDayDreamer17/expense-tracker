import 'package:intl/intl.dart';

class CurrencyFormatter {
  static String format(double amount, {String symbol = '₹'}) {
    final formatter = NumberFormat.currency(
      symbol: symbol,
      locale: 'en_IN',
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }

  static String formatCompact(double amount, {String symbol = '₹'}) {
    if (amount >= 10000000) return '$symbol${(amount / 10000000).toStringAsFixed(1)}Cr';
    if (amount >= 100000) return '$symbol${(amount / 100000).toStringAsFixed(1)}L';
    if (amount >= 1000) return '$symbol${(amount / 1000).toStringAsFixed(1)}K';
    return format(amount, symbol: symbol);
  }

  static String formatNoSymbol(double amount) {
    final formatter = NumberFormat('#,##,##0.00', 'en_IN');
    return formatter.format(amount);
  }
}

class DateFormatter {
  static String formatDate(DateTime date) => DateFormat('dd MMM yyyy').format(date);
  static String formatDateShort(DateTime date) => DateFormat('dd MMM').format(date);
  static String formatDateTime(DateTime date) => DateFormat('dd MMM yyyy, hh:mm a').format(date);
  static String formatMonth(DateTime date) => DateFormat('MMMM yyyy').format(date);
  static String formatMonthShort(DateTime date) => DateFormat('MMM yy').format(date);
  static String formatTime(DateTime date) => DateFormat('hh:mm a').format(date);
  static String formatDayOfWeek(DateTime date) => DateFormat('EEEE').format(date);

  static String relativeDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '${diff}d ago';
    return formatDateShort(date);
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;
}
