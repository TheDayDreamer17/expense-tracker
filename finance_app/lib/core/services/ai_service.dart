import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../db/database_helper.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';

final aiServiceProvider = Provider((ref) {
  final apiKey = ref.watch(settingsProvider).geminiApiKey;
  return AiService(apiKey);
});

class AiService {
  final String? _apiKey;
  AiService(this._apiKey);

  Future<String> askCopilot(String prompt) async {
    if (_apiKey == null || _apiKey.isEmpty) {
      return 'Please configure your Gemini API Key in Settings to use the AI Copilot.';
    }

    try {
      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: _apiKey,
      );

      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      
      // Get last 60 days of transactions for context
      final cutoff = now.subtract(const Duration(days: 60)).millisecondsSinceEpoch;
      final txRows = await db.rawQuery('''
        SELECT t.amount, t.type, t.date, t.note, c.name as category 
        FROM transactions t LEFT JOIN categories c ON t.category_id = c.id
        WHERE t.date >= ? ORDER BY t.date DESC
      ''', [cutoff]);

      // Format them nicely
      final txContext = txRows.map((r) {
        final d = DateTime.fromMillisecondsSinceEpoch(r['date'] as int);
        return '${DateFormatter.formatDateShort(d)} | ${r['type']} | ₹${r['amount']} | ${r['category']} | ${r['note']}';
      }).join('\n');

      // Get account balances
      final accRows = await db.query('accounts');
      final accContext = accRows.map((r) => '${r['name']}: ₹${r['balance']}').join(', ');

      final fullPrompt = '''
You are Smart Money Manager, a personalized financial AI assistant. 
You are having a conversation with the user about their finances. 

Here is their current financial context:
Accounts:
$accContext

Transactions (last 60 days):
$txContext

Answer the user's following prompt using the data above. Be friendly, concise, and helpful. Use emojis. If the user asks about something not in the data, just say you don't have enough history.

User Prompt: "$prompt"
''';

      final content = [Content.text(fullPrompt)];
      final response = await model.generateContent(content);
      return response.text ?? 'Sorry, I could not generate a response.';
    } catch (e) {
      return 'Error connecting to Gemini: $e';
    }
  }

  Future<String> getPredictiveBudget(double budgetLimit, double currentSpent) async {
    if (_apiKey == null || _apiKey.isEmpty) return 'No API key configured for predictions.';

    try {
      final now = DateTime.now();
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final daysPassed = now.day;
      final remainingDays = daysInMonth - daysPassed;

      // Base mathematical prediction
      final dailyBurn = currentSpent / (daysPassed > 0 ? daysPassed : 1);
      final projectedTotal = currentSpent + (dailyBurn * remainingDays);

      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _apiKey);
      final prompt = '''
The user has a monthly budget limit of ₹$budgetLimit.
So far this month ($daysPassed days in, $remainingDays days left), they have spent ₹$currentSpent.
Their mathematically projected total spend for the month is ₹$projectedTotal.

Write a 2-sentence friendly, insightful alert message to the user about this. Use emojis.
If they are safe, encourage them. If they are projected to overspend, gently warn them to slow down.
''';

      final response = await model.generateContent([Content.text(prompt)]);
      return response.text?.trim() ?? 'Stay on track with your budget!';
    } catch (e) {
      return 'Could not generate prediction.';
    }
  }
}
