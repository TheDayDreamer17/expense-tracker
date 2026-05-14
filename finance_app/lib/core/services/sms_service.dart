import 'package:flutter/material.dart';
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
      onBackgroundMessage: backgroundSmsHandler,
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
  /// Returns all detected transaction messages.
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

// Top-level background handler — must be outside any class
@pragma('vm:entry-point')
void backgroundSmsHandler(SmsMessage message) {
  // Lightweight: just parse and store a flag in shared_preferences
  // The full popup is shown when app opens next time
  final parsed = SmsParser.parse(
    message.address ?? '',
    message.body ?? '',
  );
  if (parsed != null) {
    // Store pending transaction for next app open
    // (SharedPreferences access in background isolate)
  }
}

// ignore: unnecessary_library_directive
import 'dart:async';
