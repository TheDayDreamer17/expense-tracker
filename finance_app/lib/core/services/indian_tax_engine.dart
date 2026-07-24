class TaxSlab {
  final double limit; // Upper boundary of the slab
  final double rate;  // Marginal tax rate (e.g., 0.05 for 5%)

  const TaxSlab({required this.limit, required this.rate});
}

class IndianTaxEngine {
  // Slabs for FY 2024-25 / FY 2025-26 under New Regime (Section 115BAC)
  static const List<TaxSlab> newRegimeSlabs = [
    TaxSlab(limit: 300000, rate: 0.00),
    TaxSlab(limit: 700000, rate: 0.05),
    TaxSlab(limit: 1000000, rate: 0.10),
    TaxSlab(limit: 1200000, rate: 0.15),
    TaxSlab(limit: 1500000, rate: 0.20),
    TaxSlab(limit: double.infinity, rate: 0.30),
  ];

  // Slabs for Old Regime (For individuals below 60 years)
  static const List<TaxSlab> oldRegimeSlabs = [
    TaxSlab(limit: 250000, rate: 0.00),
    TaxSlab(limit: 500000, rate: 0.05),
    TaxSlab(limit: 1000000, rate: 0.20),
    TaxSlab(limit: double.infinity, rate: 0.30),
  ];

  /// Calculates progressive tax for an income given a specific set of slabs
  static double calculateProgressiveTax(double taxableIncome, List<TaxSlab> slabs) {
    double tax = 0.0;
    double previousLimit = 0.0;

    for (final slab in slabs) {
      if (taxableIncome > previousLimit) {
        // Calculate the slice of income that falls into this slab
        final double upperLimit = slab.limit;
        final double taxableInSlab = (taxableIncome < upperLimit ? taxableIncome : upperLimit) - previousLimit;
        tax += taxableInSlab * slab.rate;
        previousLimit = upperLimit;
      } else {
        break;
      }
    }
    return tax;
  }

  /// Calculates tax under the New Regime
  static double computeNewRegime(double grossIncome) {
    const double standardDeduction = 75000.0; // New budget standard deduction
    final double taxableIncome = (grossIncome - standardDeduction).clamp(0.0, double.infinity);
    
    // Section 87A rebate: zero tax if taxable income is <= ₹7,00,000 (New Regime)
    if (taxableIncome <= 700000) {
      return 0.0;
    }

    final double baseTax = calculateProgressiveTax(taxableIncome, newRegimeSlabs);
    final double cess = baseTax * 0.04; // 4% Health and Education Cess
    return baseTax + cess;
  }

  /// Calculates tax under the Old Regime (accounting for manual deductions)
  static double computeOldRegime(double grossIncome, double deductions80C, double deductions80D, double deductions80TTA) {
    const double standardDeduction = 50000.0;
    
    // Deductions limits
    final double total80C = deductions80C.clamp(0.0, 150000.0);
    final double total80D = deductions80D.clamp(0.0, 25000.0); // Basic limit
    final double total80TTA = deductions80TTA.clamp(0.0, 10000.0);

    final double totalDeductions = standardDeduction + total80C + total80D + total80TTA;
    final double taxableIncome = (grossIncome - totalDeductions).clamp(0.0, double.infinity);

    // Section 87A rebate for Old Regime (zero tax if taxable income is <= ₹5,00,000)
    if (taxableIncome <= 500000) {
      return 0.0;
    }

    final double baseTax = calculateProgressiveTax(taxableIncome, oldRegimeSlabs);
    final double cess = baseTax * 0.04;
    return baseTax + cess;
  }
}
