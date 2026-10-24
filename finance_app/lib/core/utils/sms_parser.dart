import '../models/models.dart';

/// Parses incoming SMS to detect bank/UPI transactions.
/// Supports Indian banks: HDFC, SBI, ICICI, Axis, Kotak, Yes, IndusInd,
/// PNB, BOB, Canara, UPI (GPay, PhonePe, Paytm, BHIM).
class SmsParser {
  // ─── Known bank sender IDs ─────────────────────────────────────────────────
  static const _bankSenders = [
    'HDFCBK', 'HDFCBN', 'HDFC',
    'SBIINB', 'SBIPSG', 'SBIUPI', 'SBI',
    'ICICIB', 'ICICI', 'ICICIT', 'ICICIO',
    'AXISBK', 'AXISBN', 'AXIS',
    'KOTAKB', 'KOTAK',
    'YESBK', 'YESBNK',
    'INDUSB', 'IDFCFB', 'IDFC',
    'PNBSMS', 'BOBSMS', 'CANBNK',
    'FDRL', 'FEDERAL', 'SCAPIA',
    'RBLBNK', 'RBL', 'AUBANK',
    'PAYTM', 'PYTMBN',
    'GPAY', 'PHONEPE', 'BHIMUPI',
    'AMAZON', 'AMZNPAY',
    'CREDCL', 'CRED',
    'ONECRD', 'JIO',
  ];

  // ─── Regex patterns ────────────────────────────────────────────────────────
  static final _amountRe = RegExp(
    r'(?:Rs\.?|INR|₹)\s?([\d,]+\.?\d*)',
    caseSensitive: false,
  );
  static final _typeDebitRe = RegExp(
    r'\b(debited|debit|spent|paid|withdrawn|purchase|payment|charged|used\s+for|txn\s+of|transaction\s+of|sent\s+to|sent)\b',
    caseSensitive: false,
  );
  static final _typeCreditRe = RegExp(
    r'(?:\bcredited\b|\breceived\b|\bdeposited\b|\brefund\b|\bcashback\b|\bcredit\s+(?:of|to|with|in)\b|\bcredited\s+with\b|\bcredit\b(?!\s*(?:card|limit|line|score|points|rating|facility|account)))',
    caseSensitive: false,
  );
  static final _acctRe = RegExp(
    r'(?:a\/c|acct|account|card|ac)(?:\s+no\.?|\s+num\.?|\s+number)?[\s\*xX]*(\d{3,4})',
    caseSensitive: false,
  );
  static final _merchantRe = RegExp(
    r'(?:\bat\b|\bto\b|\btowards\b|\bfrom\b|\bby\b)\s+([A-Za-z0-9@.\-_ &]{2,40}?)(?:\s+on|\s+via|\s+ref|\s+upi|[.\n,]|$)',
    caseSensitive: false,
  );
  static final _iciciMerchantRe = RegExp(
    r'\bon\s+\d{1,2}-[A-Za-z]{3}-\d{2,4}\s+on\s+([A-Za-z0-9@.\-_ &]{2,40}?)(?:\.|\s+avl|\s+limit|\s+if\b|$)',
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
      'swish', 'munchmart', 'eatery', 'bakery', 'tea', 'chai',
    ],
    'cat_grocery': [
      'bigbasket', 'blinkit', 'zepto', 'dmart', 'grofers', 'jiomart',
      'supermarket', 'grocery', 'reliance fresh', 'more supermarket',
      'spencers', 'nature basket', 'lulu', 'easyday', 'instamart',
      'avenue e commer', 'avenue supermarts',
    ],
    'cat_telecom': [
      'airtel', 'jio', 'bsnl', 'vodafone', 'vi ', 'recharge',
      'mobile bill', 'broadband', 'dtv', 'dth', 'tata sky', 'act fibernet',
    ],
    'cat_transport': [
      'uber', 'ola', 'rapido', 'metro', 'irctc', 'railway', 'redbus',
      'makemytrip', 'yatra', 'cleartrip', 'indigo', 'airindia',
      'spicejet', 'goair', 'vistara', 'petrol', 'fuel', 'parking', 'toll',
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
    'cat_subscription': [
      'subscription', 'membership', 'annual fee', 'renewal',
      'chatgpt', 'openai', 'github', 'adobe', 'microsoft',
    ],
    'cat_education': [
      'udemy', 'coursera', 'byju', 'unacademy', 'vedantu', 'toppr',
      'college', 'school', 'university', 'tuition', 'fees',
    ],
    'cat_financial': [
      'emi', 'loan', 'interest', 'late fee', 'bounce', 'penal',
      'credit card bill', 'billdesk', 'cred',
    ],
  };

  // ─── Public API ────────────────────────────────────────────────────────────

  static final _nonTransactionRe = RegExp(
    r'\b(one[- ]time password|one[- ]time passcode|otps?|verification code|secret\.? do not disclose|never share|do not share|valid for \d+ min)\b|'
    r'\b(increase limit|spending power|for free|pre[- ]approved|apply now|upgrade (?:your )?limit|loan offer|eligible for|enjoy more spending power)\b|'
    r'\b(ensure sufficient balance|maintain balance|will be debited on|scheduled for|scheduled on|reminder for|is due on|due on|auto debit reminder|payment due|upcoming payment)\b',
    caseSensitive: false,
  );

  /// Returns null if the SMS is not a transaction message.
  static ParsedSmsTransaction? parse(String sender, String body) {
    if (!_isBankSender(sender)) return null;

    if (_nonTransactionRe.hasMatch(body)) return null;

    final amountMatch = _amountRe.firstMatch(body);
    if (amountMatch == null) return null;

    final rawAmount = amountMatch.group(1)!.replaceAll(',', '');
    final amount = double.tryParse(rawAmount);
    if (amount == null || amount <= 0) return null;

    final isDebit = _typeDebitRe.hasMatch(body);
    final isCredit = _typeCreditRe.hasMatch(body);
    if (!isDebit && !isCredit) return null; // Not a clear transaction

    final String type;
    if (isDebit && isCredit) {
      final lower = body.toLowerCase();
      if (lower.contains('refund') || lower.contains('cashback') || lower.contains('credited')) {
        type = 'INCOME';
      } else {
        type = 'EXPENSE';
      }
    } else if (isDebit) {
      type = 'EXPENSE';
    } else {
      type = 'INCOME';
    }

    final acct = _acctRe.firstMatch(body)?.group(1);
    final balRaw = _balanceRe.firstMatch(body)?.group(1)?.replaceAll(',', '');
    final balance = balRaw != null ? double.tryParse(balRaw) : null;

    String? merchant = _iciciMerchantRe.firstMatch(body)?.group(1)?.trim() ??
        _merchantRe.firstMatch(body)?.group(1)?.trim();

    if (merchant != null) {
      final clean = merchant.trim();
      final lower = clean.toLowerCase();
      if (RegExp(r'^(?:inr|rs|₹)?\s*[\d,.]+$').hasMatch(lower) ||
          lower.contains('block') ||
          lower.contains('no.') ||
          lower.startsWith('avl') ||
          lower.startsWith('bal') ||
          clean.length < 2) {
        merchant = null;
      } else {
        merchant = clean;
      }
    }

    if (merchant == null || merchant.isEmpty) {
      final lines = body.split('\n').map((l) => l.trim()).toList();
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.toLowerCase().contains('limit') || line.toLowerCase().contains('bal')) {
          if (i > 0) {
            final prevLine = lines[i - 1];
            final lowerPrev = prevLine.toLowerCase();
            final isDateTime = RegExp(r'\d{2}-\d{2}-\d{2}').hasMatch(prevLine) || 
                               RegExp(r'\d{4}-\d{2}-\d{2}').hasMatch(prevLine) ||
                               lowerPrev.contains('ist') || 
                               lowerPrev.contains('gmt') ||
                               lowerPrev.contains('pm') ||
                               lowerPrev.contains('am');
            final isCardOrSpent = lowerPrev.contains('card') || 
                                  lowerPrev.contains('spent') || 
                                  lowerPrev.contains('rs.') || 
                                  lowerPrev.contains('inr') || 
                                  lowerPrev.contains('₹');
            if (!isDateTime && !isCardOrSpent && prevLine.isNotEmpty && prevLine.length > 2) {
              merchant = prevLine;
              break;
            }
          }
        }
      }
    }

    final category = _detectCategory(merchant ?? body);

    final lowerBody = body.toLowerCase();
    final lowerSender = sender.toLowerCase();
    final isCreditCard = lowerBody.contains('credit card') ||
        lowerBody.contains('spent on card') ||
        lowerBody.contains('card ending') ||
        lowerSender.contains('card') ||
        lowerSender.contains('crd') ||
        (lowerBody.contains('card') && type == 'EXPENSE');

    String? cardName;
    if (isCreditCard) {
      if (lowerSender.contains('sbi') || lowerBody.contains('sbi')) {
        cardName = 'SBI Card';
      } else if (lowerSender.contains('hdfc') || lowerBody.contains('hdfc')) {
        cardName = 'HDFC Card';
      } else if (lowerSender.contains('icici') || lowerBody.contains('icici')) {
        cardName = 'ICICI Card';
      } else if (lowerSender.contains('axis') || lowerBody.contains('axis')) {
        cardName = 'Axis Card';
      } else if (lowerSender.contains('scapia') || lowerBody.contains('scapia')) {
        cardName = 'Scapia Federal Card';
      } else {
        cardName = 'Credit Card';
      }
    }

    return ParsedSmsTransaction(
      amount: amount,
      type: type,
      merchant: merchant,
      accountLast4: acct,
      balance: balance,
      suggestedCategory: category,
      smsRaw: body,
      sender: sender,
      isCreditCard: isCreditCard,
      cardName: cardName,
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
    if (sender.isEmpty) return true; // Allow local testing without sender
    final upper = sender.toUpperCase();
    // Exclude direct commercial delivery apps so order tracking SMS are not parsed as bank debits
    if (upper.contains('ZOMATO') || upper.contains('SWIGGY') || upper.contains('ZEPTO') || upper.contains('BLINKIT')) {
      return false;
    }
    // Allow test phone numbers from emulator
    if (RegExp(r'^\+?\d+$').hasMatch(sender)) return true;
    return _bankSenders.any((s) => upper.contains(s));
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
