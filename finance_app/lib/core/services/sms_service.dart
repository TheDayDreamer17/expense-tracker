import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/sms_parser.dart';
import '../models/models.dart';

/// Emits parsed SMS transactions for the UI to show the popup.
final smsTransactionStreamProvider = StreamProvider<ParsedSmsTransaction>((ref) {
  return SmsService.instance.transactionStream;
});

class SmsService {
  static final SmsService instance = SmsService._();
  SmsService._();

  final _telephony = Telephony.instance;
  final _controller = StreamController<ParsedSmsTransaction>.broadcast();

  Stream<ParsedSmsTransaction> get transactionStream => _controller.stream;

  Future<void> initialize() async {
    final granted = await _requestPermissions();
    if (!granted) return;

    _telephony.listenIncomingSms(
      onNewMessage: _onMessage,
      onBackgroundMessage: smsBgHandler,
      listenInBackground: true,
    );
  }

  void _onMessage(SmsMessage message) {
    final parsed = SmsParser.parse(
      message.address ?? '',
      message.body ?? '',
    );
    if (parsed != null) {
      _controller.add(parsed);
    }
  }

  Future<bool> _requestPermissions() async {
    final statuses = await [
      Permission.sms,
      Permission.phone,
    ].request();
    return statuses[Permission.sms]?.isGranted ?? false;
  }

  /// Scans the SMS inbox for the past [months] months.
  Future<List<ParsedSmsTransaction>> scanInbox({int months = 3}) async {
    final granted = await _requestPermissions();
    if (!granted) return [];

    final cutoff = DateTime.now().subtract(Duration(days: months * 30));
    final messages = await _telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      filter: SmsFilter.where(SmsColumn.DATE)
          .greaterThan(cutoff.millisecondsSinceEpoch.toString()),
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );

    final results = <ParsedSmsTransaction>[];
    for (final msg in messages ?? []) {
      final parsed = SmsParser.parse(
        msg.address ?? '',
        msg.body ?? '',
      );
      if (parsed != null) results.add(parsed);
    }
    return results;
  }

  void dispose() => _controller.close();
}

// ─── Background handler (top-level, outside class) ──────────────────────────
@pragma('vm:entry-point')
void smsBgHandler(SmsMessage message) {
  final parsed = SmsParser.parse(
    message.address ?? '',
    message.body ?? '',
  );
  // Store parsed data for pickup on next app open (no UI available in bg isolate)
  if (parsed != null) {
    // Could persist to shared_prefs here if needed
  }
}
