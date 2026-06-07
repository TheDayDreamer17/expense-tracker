import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/core/utils/sms_parser.dart';

void main() {
  group('SmsParser Logic Tests', () {
    test('Parses a Food/Dining debit transaction correctly', () {
      const body = 'Rs. 450.00 debited from A/c **1234 towards Zomato on 17 May.';
      const sender = 'HDFCBK'; // Must be a known bank sender

      final result = SmsParser.parse(sender, body);

      expect(result, isNotNull);
      expect(result!.amount, 450.00);
      expect(result.type, 'EXPENSE');
      expect(result.suggestedCategory, 'cat_food');
      expect(result.accountLast4, '1234');
    });

    test('Parses a Grocery credit card transaction correctly', () {
      const body = 'INR 1,200 spent on your Credit Card xx8901 at BIGBASKET.';
      const sender = 'AXISBK';

      final result = SmsParser.parse(sender, body);

      expect(result, isNotNull);
      expect(result!.amount, 1200.00);
      expect(result.type, 'EXPENSE');
      expect(result.suggestedCategory, 'cat_grocery');
    });

    test('Parses Income/Credited amounts correctly', () {
      const body = 'Your A/C XX7777 is credited with INR 5,000.00 on 10 May.';
      const sender = 'SBIINB';

      final result = SmsParser.parse(sender, body);

      expect(result, isNotNull);
      expect(result!.amount, 5000.00);
      expect(result.type, 'INCOME');
    });

    test('Ignores normal text messages (not from a bank)', () {
      const body = 'Your Zomato order of Rs. 450 is on the way!';
      const sender = 'ZOMATO'; // Not in the bank list

      final result = SmsParser.parse(sender, body);

      expect(result, isNull);
    });
  });
}
