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
      expect(result.isCreditCard, isTrue);
      expect(result.cardName, 'Axis Card');
    });

    test('Parses Income/Credited amounts correctly', () {
      const body = 'Your A/C XX7777 is credited with INR 5,000.00 on 10 May.';
      const sender = 'SBIINB';

      final result = SmsParser.parse(sender, body);

      expect(result, isNotNull);
      expect(result!.amount, 5000.00);
      expect(result.type, 'INCOME');
    });

    test('Parses Credited income SMS with from-merchant pattern (Tanmay Kumar)', () {
      const body = 'Dear Customer, Acct XX907 is credited with Rs 425.00 on 05-Jun-26 from TANMAY KUMAR. UPI:071908363245-ICICI Bank.';
      const sender = 'ICICIB';

      final result = SmsParser.parse(sender, body);

      expect(result, isNotNull);
      expect(result!.amount, 425.00);
      expect(result.type, 'INCOME');
      expect(result.accountLast4, '907');
      expect(result.merchant, 'TANMAY KUMAR');
    });

    test('Parses Credited income SMS with from-merchant pattern (Raj Kumar Mogor)', () {
      const body = 'Dear Customer, Acct XX907 is credited with Rs 32.00 on 06-Jun-26 from RAJ KUMAR MOGOR. UPI:124322087415-ICICI Bank.';
      const sender = 'ICICIB';

      final result = SmsParser.parse(sender, body);

      expect(result, isNotNull);
      expect(result!.amount, 32.00);
      expect(result.type, 'INCOME');
      expect(result.accountLast4, '907');
      expect(result.merchant, 'RAJ KUMAR MOGOR');
    });

    test('Ignores normal text messages (not from a bank)', () {
      const body = 'Your Zomato order of Rs. 450 is on the way!';
      const sender = 'ZOMATO'; // Not in the bank list

      final result = SmsParser.parse(sender, body);

      expect(result, isNull);
    });
  });
}
