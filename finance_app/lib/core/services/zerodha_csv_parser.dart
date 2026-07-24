class ParsedZerodhaGains {
  final double stcg;
  final double ltcg;
  final double dividends;
  final int count;

  ParsedZerodhaGains({
    required this.stcg,
    required this.ltcg,
    required this.dividends,
    required this.count,
  });
}

class ZerodhaCsvParser {
  /// Parses a Zerodha CSV capital gains or P&L report and returns aggregated gains.
  static ParsedZerodhaGains parse(String csvContent) {
    double stcg = 0.0;
    double ltcg = 0.0;
    double dividends = 0.0;
    int count = 0;

    final lines = csvContent.split('\n');
    if (lines.isEmpty) {
      return ParsedZerodhaGains(stcg: 0, ltcg: 0, dividends: 0, count: 0);
    }

    // Find headers row
    List<String> headers = [];
    int headerIndex = -1;

    for (int i = 0; i < lines.length; i++) {
      final cells = _splitCsvLine(lines[i]);
      if (cells.length >= 3 &&
          cells.any((c) => c.toLowerCase().contains('isin') || 
                           c.toLowerCase().contains('symbol') || 
                           c.toLowerCase().contains('stcg') || 
                           c.toLowerCase().contains('ltcg'))) {
        headers = cells.map((c) => c.trim().toLowerCase()).toList();
        headerIndex = i;
        break;
      }
    }

    // Fallback: If no ISIN/symbol header found, try to locate headers containing STCG/LTCG
    if (headerIndex == -1) {
      for (int i = 0; i < lines.length; i++) {
        final cells = _splitCsvLine(lines[i]);
        if (cells.length >= 3 &&
            cells.any((c) => c.toLowerCase() == 'stcg' || c.toLowerCase() == 'ltcg')) {
          headers = cells.map((c) => c.trim().toLowerCase()).toList();
          headerIndex = i;
          break;
        }
      }
    }

    // If still no headers, we will try to match columns positionally or return zero
    if (headerIndex == -1) {
      // Let's also scan the whole file for raw key-value lines like "Realized STCG, 15000.00"
      for (final line in lines) {
        final cells = _splitCsvLine(line);
        if (cells.length >= 2) {
          final label = cells[0].toLowerCase();
          final val = double.tryParse(cells[1].replaceAll(RegExp(r'[^\d.-]'), '')) ?? 0.0;
          if (label.contains('stcg') || label.contains('short term')) {
            stcg += val;
          } else if (label.contains('ltcg') || label.contains('long term')) {
            ltcg += val;
          } else if (label.contains('dividend')) {
            dividends += val;
          }
        }
      }
      return ParsedZerodhaGains(
        stcg: stcg,
        ltcg: ltcg,
        dividends: dividends,
        count: stcg > 0 || ltcg > 0 || dividends > 0 ? 1 : 0,
      );
    }

    // Map column names to indexes
    final stcgIdx = headers.indexWhere((h) => h.contains('stcg') || h.contains('short term'));
    final ltcgIdx = headers.indexWhere((h) => h.contains('ltcg') || h.contains('long term'));
    final divIdx = headers.indexWhere((h) => h.contains('dividend'));
    final realizedIdx = headers.indexWhere((h) => h == 'realized p&l' || h == 'realized pnl' || h == 'realized gain');

    for (int i = headerIndex + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final cells = _splitCsvLine(line);
      if (cells.length <= headers.length / 2) continue; // Skip totals or empty divider rows

      double rowStcg = 0.0;
      double rowLtcg = 0.0;
      double rowDiv = 0.0;

      if (stcgIdx != -1 && stcgIdx < cells.length) {
        rowStcg = double.tryParse(cells[stcgIdx].replaceAll(RegExp(r'[^\d.-]'), '')) ?? 0.0;
      }
      if (ltcgIdx != -1 && ltcgIdx < cells.length) {
        rowLtcg = double.tryParse(cells[ltcgIdx].replaceAll(RegExp(r'[^\d.-]'), '')) ?? 0.0;
      }
      if (divIdx != -1 && divIdx < cells.length) {
        rowDiv = double.tryParse(cells[divIdx].replaceAll(RegExp(r'[^\d.-]'), '')) ?? 0.0;
      }

      // If there are no specific STCG/LTCG columns but there is a general Realized P&L column,
      // treat positive values as STCG by default (conservative tax calculation)
      if (stcgIdx == -1 && ltcgIdx == -1 && realizedIdx != -1 && realizedIdx < cells.length) {
        final val = double.tryParse(cells[realizedIdx].replaceAll(RegExp(r'[^\d.-]'), '')) ?? 0.0;
        if (val > 0) rowStcg = val;
      }

      if (rowStcg != 0 || rowLtcg != 0 || rowDiv != 0) {
        stcg += rowStcg;
        ltcg += rowLtcg;
        dividends += rowDiv;
        count++;
      }
    }

    return ParsedZerodhaGains(stcg: stcg, ltcg: ltcg, dividends: dividends, count: count);
  }

  /// Parses CSV line properly handling quoted commas.
  static List<String> _splitCsvLine(String line) {
    final List<String> result = [];
    final StringBuffer currentCell = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(currentCell.toString());
        currentCell.clear();
      } else {
        currentCell.write(char);
      }
    }
    result.add(currentCell.toString());
    return result;
  }
}
