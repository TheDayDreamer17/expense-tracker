import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import '../db/database_helper.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';

final aiServiceProvider = Provider((ref) {
  final settings = ref.watch(settingsProvider);
  return AiService(
    provider: settings.aiProvider,
    apiKey: settings.aiApiKey ?? settings.geminiApiKey,
    endpoint: settings.aiCustomEndpoint,
    model: settings.aiModel,
  );
});

class AiService {
  final String provider;
  final String? apiKey;
  final String? endpoint;
  final String? model;

  AiService({
    required this.provider,
    required this.apiKey,
    required this.endpoint,
    required this.model,
  });

  Future<String> askCopilot(String prompt) async {
    final key = apiKey;
    if (provider != 'custom' && (key == null || key.isEmpty)) {
      return 'Please configure your API Key in Settings to use the AI Copilot.';
    }

    try {
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

      return _callAI(fullPrompt);
    } catch (e) {
      return 'Error connecting to AI: $e';
    }
  }

  Future<String> getPredictiveBudget(double budgetLimit, double currentSpent) async {
    final key = apiKey;
    if (provider != 'custom' && (key == null || key.isEmpty)) {
      return 'No API key configured for predictions.';
    }

    try {
      final now = DateTime.now();
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final daysPassed = now.day;
      final remainingDays = daysInMonth - daysPassed;

      // Base mathematical prediction
      final dailyBurn = currentSpent / (daysPassed > 0 ? daysPassed : 1);
      final projectedTotal = currentSpent + (dailyBurn * remainingDays);

      final prompt = '''
The user has a monthly budget limit of ₹$budgetLimit.
So far this month ($daysPassed days in, $remainingDays days left), they have spent ₹$currentSpent.
Their mathematically projected total spend for the month is ₹$projectedTotal.

Write a 2-sentence friendly, insightful alert message to the user about this. Use emojis.
If they are safe, encourage them. If they are projected to overspend, gently warn them to slow down.
''';

      return _callAI(prompt);
    } catch (e) {
      return 'Could not generate prediction.';
    }
  }

  Future<String> _callAI(String prompt) async {
    final activeModel = model ?? '';
    
    if (provider == 'gemini') {
      final geminiModel = GenerativeModel(
        model: activeModel.isEmpty ? 'gemini-1.5-flash' : activeModel,
        apiKey: apiKey!,
      );
      final response = await geminiModel.generateContent([Content.text(prompt)]);
      return response.text ?? 'No response generated.';
    }

    if (provider == 'openai') {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': activeModel.isEmpty ? 'gpt-4o-mini' : activeModel,
          'messages': [
            {'role': 'user', 'content': prompt}
          ]
        }),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return decoded['choices'][0]['message']['content']?.toString() ?? 'Empty response.';
      } else {
        return 'OpenAI Error: ${response.statusCode} - ${response.body}';
      }
    }

    if (provider == 'anthropic') {
      final response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey!,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': activeModel.isEmpty ? 'claude-3-5-sonnet-20240620' : activeModel,
          'max_tokens': 1024,
          'messages': [
            {'role': 'user', 'content': prompt}
          ]
        }),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return decoded['content'][0]['text']?.toString() ?? 'Empty response.';
      } else {
        return 'Anthropic Error: ${response.statusCode} - ${response.body}';
      }
    }

    if (provider == 'custom') {
      final url = endpoint ?? '';
      if (url.isEmpty) {
        return 'Please configure a custom API Endpoint URL in Settings.';
      }
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (apiKey != null && apiKey!.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': activeModel.isEmpty ? 'default' : activeModel,
          'messages': [
            {'role': 'user', 'content': prompt}
          ]
        }),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return decoded['choices'][0]['message']['content']?.toString() ?? 'Empty response.';
      } else {
        return 'Custom API Error: ${response.statusCode} - ${response.body}';
      }
    }

    return 'Unknown AI Provider: $provider';
  }
}
