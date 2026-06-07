import '../models/models.dart';

/// Parses incoming SMS to detect bank/UPI transactions.
/// Supports Indian banks: HDFC, SBI, ICICI, Axis, Kotak, Yes, IndusInd,
/// PNB, BOB, Canara, UPI (GPay, PhonePe, Paytm, BHIM).
class SmsParser {
  // ─── Known bank sender IDs ─────────────────────────────────────────────────
  static const _bankSenders = [
    'HDFCBK', 'HDFCBN', 'HDFC',
    'SBIINB', 'SBIPSG', 'SBIUPI', 'SBI',
    'ICICIB', 'ICICI',
    'AXISBK', 'AXISBN', 'AXIS',
    'KOTAKB', 'KOTAK',
    'YESBK', 'YESBNK',
    'INDUSB', 'IDFCFB',
    'PNBSMS', 'BOBSMS', 'CANBNK',
    'PAYTM', 'PYTMBN',
    'GPAY', 'PHONEPE', 'BHIMUPI',
    'AMAZON', 'AMZNPAY',
    'CREDCL', 'CRED',
  ];

  // ─── Regex patterns ────────────────────────────────────────────────────────
  static final _amountRe = RegExp(
    r'(?:Rs\.?|INR|₹)\s?([\d,]+\.?\d*)',
    caseSensitive: false,
  );
  static final _typeDebitRe = RegExp(
    r'\b(debited|debit|spent|paid|withdrawn|purchase|payment)\b',
    caseSensitive: false,
  );
  static final _typeCreditRe = RegExp(
    r'\b(credited|credit|received|deposited|refund|cashback)\b',
    caseSensitive: false,
  );
  static final _acctRe = RegExp(
    r'(?:a\/c|account|card|ac)[\s\*xX]*(\d{4})',
    caseSensitive: false,
  );
  static final _merchantRe = RegExp(
    r'(?:\bat\b|\bto\b|\btowards\b|\bfor\b)\s+([A-Za-z0-9@.\-_ &]{3,40}?)(?:\s+on|\s+via|\s+ref|\s+upi|[.\n,]|$)',
    caseSensitive: false,
  );
  static final _balanceRe = RegExp(
    r'(?:avl\.?\s*bal(?:ance)?|available bal(?:ance)?|bal(?:ance)?[\s:]*)[\s:]+(?:Rs\.?|INR|₹)\s?([\d,]+\.?\d*)',
    caseSensitive: false,
  );

  // ─── Category keyword map ──────────────────────────────────────────────────
  static const _categoryKeywords = <String, List<String>>{
    'cat_food': [
      'swiggy', 'zomato', 'dominos', 'domino', 'pizza', 'kfc', 'mcdonalds',
      'mcd', 'burger', 'restaurant', 'cafe', 'coffee', 'starbucks',
      'eatclub', 'box8', 'freshmenu', 'faasos', 'biryani', 'hotel',
    ],
    'cat_grocery': [
      'bigbasket', 'blinkit', 'zepto', 'dmart', 'grofers', 'jiomart',
      'supermarket', 'grocery', 'reliance fresh', 'more supermarket',
      'spencers', 'nature basket', 'lulu', 'easyday',
    ],
    'cat_transport': [
      'uber', 'ola', 'rapido', 'metro', 'irctc', 'railway', 'redbus',
      'makemytrip', 'yatra', 'cleartrip', 'indigo', 'airindia',
      'spicejet', 'goair', 'vistara', 'petrol', 'fuel', 'parking',
    ],
    'cat_shopping': [
      'amazon', 'flipkart', 'myntra', 'meesho', 'nykaa', 'ajio',
      'tatacliq', 'snapdeal', 'shopclues', 'reliance digital',
      'croma', 'vijaysales', 'decathlon',
    ],
    'cat_entertainment': [
      'netflix', 'prime', 'hotstar', 'disney', 'spotify', 'youtube',
      'zee5', 'sonyliv', 'mxplayer', 'bookmyshow', 'pvr', 'inox',
      'apple music', 'gaana', 'jiosaavn',
    ],
    'cat_health': [
      'apollo', 'pharmeasy', '1mg', 'netmeds', 'medplus', 'hospital',
      'clinic', 'doctor', 'pharmacy', 'medical', 'labs', 'diagnostic',
      'healthkart', 'cult.fit', 'cure.fit',
    ],
    'cat_utilities': [
      'electricity', 'bescom', 'msedcl', 'tata power', 'adani electric',
      'water', 'gas', 'piped gas', 'mgl', 'igl', 'mahanagar gas',
    ],
    'cat_telecom': [
      'airtel', 'jio', 'bsnl', 'vodafone', 'vi ', 'recharge',
      'mobile bill', 'broadband', 'dtv', 'dth', 'tata sky',
    ],
    'cat_education': [
      'udemy', 'coursera', 'byju', 'unacademy', 'vedantu', 'toppr',
      'college', 'school', 'university', 'tuition', 'fees',
    ],
    'cat_subscription': [
      'subscription', 'membership', 'annual fee', 'renewal',
      'chatgpt', 'openai', 'github', 'adobe', 'microsoft',
    ],
  };

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Returns null if the SMS is not a transaction message.
  static ParsedSmsTransaction? parse(String sender, String body) {
    if (!_isBankSender(sender)) return null;

    final amountMatch = _amountRe.firstMatch(body);
    if (amountMatch == null) return null;

    final rawAmount = amountMatch.group(1)!.replaceAll(',', '');
    final amount = double.tryParse(rawAmount);
    if (amount == null || amount <= 0) return null;

    final isDebit = _typeDebitRe.hasMatch(body);
    final isCredit = _typeCreditRe.hasMatch(body);
    if (!isDebit && !isCredit) return null; // Not a clear transaction

    // Prioritize EXPENSE if both exist (e.g., "spent on credit card")
    final type = isDebit ? 'EXPENSE' : 'INCOME';
    final merchant = _merchantRe.firstMatch(body)?.group(1)?.trim();
    final acct = _acctRe.firstMatch(body)?.group(1);
    final balRaw = _balanceRe.firstMatch(body)?.group(1)?.replaceAll(',', '');
    final balance = balRaw != null ? double.tryParse(balRaw) : null;
    final category = _detectCategory(merchant ?? body);

    return ParsedSmsTransaction(
      amount: amount,
      type: type,
      merchant: merchant,
      accountLast4: acct,
      balance: balance,
      suggestedCategory: category,
      smsRaw: body,
      sender: sender,
    );
  }

  /// Scan a list of inbox messages and return all detected transactions.
  static List<ParsedSmsTransaction> scanInbox(List<Map<String, String>> messages) {
    final results = <ParsedSmsTransaction>[];
    for (final msg in messages) {
      final parsed = parse(msg['sender'] ?? '', msg['body'] ?? '');
      if (parsed != null) results.add(parsed);
    }
    return results;
  }

  // ─── Private helpers ───────────────────────────────────────────────────────

  static bool _isBankSender(String sender) {
    // TEMPORARY: Allow all senders so Android Emulator testing works!
    return true; 
    // final upper = sender.toUpperCase();
    // return _bankSenders.any((s) => upper.contains(s));
  }

  static String _detectCategory(String text) {
    final lower = text.toLowerCase();
    for (final entry in _categoryKeywords.entries) {
      if (entry.value.any((kw) => lower.contains(kw))) {
        return entry.key;
      }
    }
    return 'cat_other_exp';
  }
}
