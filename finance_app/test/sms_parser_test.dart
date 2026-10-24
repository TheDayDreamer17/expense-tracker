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

    test('Parses Scapia Federal credit card debit as EXPENSE (not INCOME)', () {
      const body = 'Hi! Your txn of ₹859.00 at Jio on your Scapia Federal Bank Credit card XX1234 was successful.';
      const sender = 'SCAPIA';

      final result = SmsParser.parse(sender, body);

      expect(result, isNotNull);
      expect(result!.amount, 859.00);
      expect(result.type, 'EXPENSE');
      expect(result.suggestedCategory, 'cat_telecom');
      expect(result.isCreditCard, isTrue);
    });

    test('Parses ICICI Bank spent SMS with on-date-on-merchant format', () {
      const body = 'INR 395.00 spent using ICICI Bank Card XX8004 on 09-Sep-26 on MUNCHMART TECHN. Avl Limit: INR 82,111.53.';
      const sender = 'JD-ICICIT-S';

      final result = SmsParser.parse(sender, body);

      expect(result, isNotNull);
      expect(result!.amount, 395.00);
      expect(result.type, 'EXPENSE');
      expect(result.merchant, 'MUNCHMART TECHN');
      expect(result.suggestedCategory, 'cat_food');
      expect(result.accountLast4, '8004');
    });

    test('Rejects OTP messages containing Credit Card and amounts', () {
      const body = '601828 is One-Time Password for INR 395.00 transaction towards MUNCHMART using ICICI Bank Credit Card XX8004. OTPs are SECRET. DO NOT disclose';
      const sender = 'AD-ICICIO-T';

      final result = SmsParser.parse(sender, body);

      expect(result, isNull);
    });

    test('Rejects credit limit extension promotional offers', () {
      const body = 'Dear Customer, enjoy more spending power! Increase limit on HDFC Bank Credit Card 8163 to Rs.597000 for FREE https://1.hdfc.bank.in/HDFCBK/s/AAZa5qjk';
      const sender = 'JM-HDFCBK-P';

      final result = SmsParser.parse(sender, body);

      expect(result, isNull);
    });

    test('Rejects upcoming EMI debit reminders', () {
      const body = 'penal charges and Rs 500 bounce charges. EMI will be debited on holidays too. Access your loan related services on iMobile.';
      const sender = 'JD-ICICIT-S';

      final result = SmsParser.parse(sender, body);

      expect(result, isNull);
    });
  });
}
