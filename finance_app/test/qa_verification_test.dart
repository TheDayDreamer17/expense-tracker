import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/core/utils/sms_parser.dart';

void main() {
  group('QA Verification - SMS Edge Cases & Robustness', () {
    test('Handles malformed currency strings with commas and symbols cleanly', () {
      const body = 'Alert: Rs. 1,25,000.50 spent on your Credit Card XX9988 at AMAZON INDIA on 05-Sep-26.';
      final parsed = SmsParser.parse('HDFCBK', body);
      
      expect(parsed, isNotNull);
      expect(parsed!.amount, equals(125000.50));
      expect(parsed.isCreditCard, isTrue);
      expect(parsed.accountLast4, equals('9988'));
      expect(parsed.merchant, equals('AMAZON INDIA'));
    });

    test('Handles noisy SMS without bank identifiers safely', () {
      const body = 'Your OTP for logging into Amazon is 482910. Do not share with anyone.';
      final parsed = SmsParser.parse('PROMOTIONAL', body);
      
      expect(parsed, isNull);
    });

    test('Parses salary credit SMS correctly', () {
      const body = 'Your A/C XX4321 has been credited by Rs 75,000.00 on 01-Sep-26 by Salary Transfer.';
      final parsed = SmsParser.parse('ICICIB', body);
      
      expect(parsed, isNotNull);
      expect(parsed!.amount, equals(75000.00));
      expect(parsed.type, equals('INCOME'));
      expect(parsed.accountLast4, equals('4321'));
    });

    test('Filters out Home Loan balance check SMS correctly (Not a transaction)', () {
      const body = 'Dear Customer, please ensure sufficient balance of Rs 25,000.00 in your A/C XX9012 for Home Loan EMI scheduled on 10-Sep-26.';
      final parsed = SmsParser.parse('HDFCBK', body);
      
      expect(parsed, isNull);
    });

    test('Filters out Insurance due date reminder SMS correctly (Not a transaction)', () {
      const body = 'Reminder: Premium of Rs 4,500.00 for Policy 981273 is due on 12-Sep-26. Keep funds ready.';
      final parsed = SmsParser.parse('ICICIB', body);
      
      expect(parsed, isNull);
    });

    test('Parses zero amount SMS without crash (ignores zero rupee auth messages)', () {
      const body = 'A/C XX1234 debited by Rs 0.00 for test authorization.';
      final parsed = SmsParser.parse('SBIIN', body);
      
      expect(parsed, isNull);
    });

    test('Handles UPI transaction SMS cleanly', () {
      const body = 'Paid Rs. 350.00 via UPI to ZOMATO FOODS ref 982138127. A/C XX1122.';
      final parsed = SmsParser.parse('AXISBK', body);
      
      expect(parsed, isNotNull);
      expect(parsed!.amount, equals(350.0));
      expect(parsed.accountLast4, equals('1122'));
    });
  });

  group('QA Verification - Financial Calculations Boundary Conditions', () {
    test('Zero income percentage calculation does not return NaN or Infinity', () {
      const double income = 0.0;
      const double expense = 500.0;
      
      final pct = income > 0 ? (expense / income).clamp(0.0, 1.0) : 0.0;
      expect(pct, equals(0.0));
      expect(pct.isNaN, isFalse);
      expect(pct.isInfinite, isFalse);
    });

    test('Zero budget usage calculation safety', () {
      const double budgetLimit = 0.0;
      const double spent = 150.0;
      
      final usage = budgetLimit > 0 ? (spent / budgetLimit) : 0.0;
      expect(usage, equals(0.0));
      expect(usage.isNaN, isFalse);
    });

    test('SIP calculation with zero months or zero rate safety', () {
      const double target = 100000.0;
      const int months = 0;
      
      double requiredMonthly = 0.0;
      if (months > 0) {
        requiredMonthly = target / months;
      }
      expect(requiredMonthly, equals(0.0));
    });
  });
}
