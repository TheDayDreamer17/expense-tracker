import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/core/services/indian_tax_engine.dart';
import 'package:finance_app/core/services/zerodha_csv_parser.dart';

void main() {
  group('IndianTaxEngine Tests', () {
    test('New Regime - Zero Tax up to 7 Lakhs taxable income', () {
      // Under New Regime: Standard Deduction is 75000.
      // Gross 775000 - 75000 = 700000 taxable. Taxable <= 700000 is 0 tax due to 87A.
      expect(IndianTaxEngine.computeNewRegime(775000), 0.0);
      expect(IndianTaxEngine.computeNewRegime(500000), 0.0);
    });

    test('New Regime - Section 87A Marginal Relief for income slightly above 7 Lakhs', () {
      // Gross 7,85,000. Standard deduction = 75,000. Taxable income = 7,10,000.
      // Normal base tax would be: 20,000 (3L-7L @ 5%) + 1,000 (7L-7.1L @ 10%) = 21,000.
      // Excess income over 7,00,000 = 10,000.
      // Marginal relief caps base tax to 10,000.
      // Total tax with 4% cess = 10,000 + 400 = 10,400.
      expect(IndianTaxEngine.computeNewRegime(785000), 10400.0);
    });

    test('New Regime - Progressive taxation above rebate limit', () {
      // Gross 10,75,000. Less 75,000 standard deduction = 10,00,000 taxable.
      // Slabs:
      // 0 to 3,00,000: 0% = 0
      // 3,00,000 to 7,00,000: 5% of 4,00,000 = 20,000
      // 7,00,000 to 10,00,000: 10% of 3,00,000 = 30,000
      // Total Base Tax = 50,000. Plus 4% Cess = 52,000.
      expect(IndianTaxEngine.computeNewRegime(1075000), 52000.0);
    });

    test('Old Regime - Zero Tax up to 5 Lakhs taxable income', () {
      // Under Old Regime: Standard Deduction is 50000.
      // Gross 550000 - 50000 (SD) = 500000 taxable. Taxable <= 500000 is 0 tax due to 87A.
      expect(IndianTaxEngine.computeOldRegime(550000, 0, 0, 0), 0.0);
    });

    test('Old Regime - Progressive taxation with deduction overrides', () {
      // Gross 12,00,000.
      // Deductions: 1,50,000 (80C), 25,000 (80D), 10,000 (80TTA).
      // Standard deduction: 50,000.
      // Total Deductions = 2,35,000. Taxable Income = 9,65,000.
      // Slabs:
      // 0 to 2,50,000: 0% = 0
      // 2,50,000 to 5,00,000: 5% of 2,50,000 = 12,500
      // 5,00,000 to 9,65,000: 20% of 4,65,000 = 93,000
      // Total Base Tax = 1,05,500. Plus 4% Cess = 1,09,720.
      expect(
        IndianTaxEngine.computeOldRegime(1200000, 150000, 25000, 10000),
        109720.0,
      );
    });
  });

  group('ZerodhaCsvParser Tests', () {
    test('Parse standard Zerodha Capital Gains format', () {
      const csv = '''
Symbol,ISIN,Quantity,Buy Date,Buy Price,Sell Date,Sell Price,Realized P&L,STCG,LTCG,Dividend
INFY,INE009A01021,10,2023-01-01,1500.00,2024-05-01,1600.00,1000.00,1000.00,0.00,150.00
RELIANCE,INE002A01018,5,2022-01-01,2000.00,2024-05-01,2500.00,2500.00,0.00,2500.00,0.00
''';
      final gains = ZerodhaCsvParser.parse(csv);
      expect(gains.count, 2);
      expect(gains.stcg, 1000.00);
      expect(gains.ltcg, 2500.00);
      expect(gains.dividends, 150.00);
    });

    test('Parse alternative/legacy formats positionally', () {
      const csv = '''
Realized STCG,5000.00
Realized LTCG,12000.00
Dividends Received,250.00
''';
      final gains = ZerodhaCsvParser.parse(csv);
      expect(gains.stcg, 5000.00);
      expect(gains.ltcg, 12000.00);
      expect(gains.dividends, 250.00);
    });
  });
}
