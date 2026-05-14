import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/services/ai_service.dart';
import '../../core/utils/app_theme.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  ChatMessage(this.text, {required this.isUser});
}

class CopilotScreen extends ConsumerStatefulWidget {
  const CopilotScreen({super.key});
  @override
  ConsumerState<CopilotScreen> createState() => _CopilotScreenState();
}

class _CopilotScreenState extends ConsumerState<CopilotScreen> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<ChatMessage> _messages = [
    ChatMessage('Hi! I\'m your Financial Copilot. Ask me anything about your spending, budgets, or accounts.', isUser: false),
  ];
  bool _loading = false;

  void _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(text, isUser: true));
      _loading = true;
      _ctrl.clear();
    });
    _scrollToBottom();

    final ai = ref.read(aiServiceProvider);
    final response = await ai.askCopilot(text);

    if (mounted) {
      setState(() {
        _messages.add(ChatMessage(response, isUser: false));
        _loading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: 300.ms, curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.auto_awesome, color: AppColors.income),
          const SizedBox(width: 8),
          const Text('AI Copilot'),
        ]),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                return Align(
                  alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                    decoration: BoxDecoration(
                      color: m.isUser ? AppColors.primary : Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(16).copyWith(
                        bottomRight: m.isUser ? Radius.zero : const Radius.circular(16),
                        bottomLeft: !m.isUser ? Radius.zero : const Radius.circular(16),
                      ),
                      border: m.isUser ? null : Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
                    ),
                    child: Text(
                      m.text,
                      style: TextStyle(color: m.isUser ? Colors.white : null, fontSize: 14),
                    ),
                  ).animate().fadeIn().slideY(begin: 0.1),
                );
              },
            ),
          ),
          if (_loading)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: const Row(children: [
                SizedBox(width: 16),
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Thinking...', style: TextStyle(color: AppColors.lightTextSecondary, fontSize: 12)),
              ]).animate().fadeIn(),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'e.g., How much did I spend on food this month?',
                      filled: true,
                      fillColor: Theme.of(context).cardTheme.color,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: AppColors.primary,
                  radius: 24,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _loading ? null : _send,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
