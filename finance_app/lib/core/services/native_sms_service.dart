import 'dart:async';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';

final nativeSmsTransactionStreamProvider = StreamProvider<ParsedSmsTransaction>((ref) {
  return NativeSmsService.instance.onTransactionReceived;
});

class NativeSmsService {
  static final NativeSmsService instance = NativeSmsService._();
  NativeSmsService._();

  static const _methodChannel = MethodChannel('com.example.finance_app/sms_methods');
  static const _eventChannel = EventChannel('com.example.finance_app/sms_events');

  final _controller = StreamController<ParsedSmsTransaction>.broadcast();
  Stream<ParsedSmsTransaction> get onTransactionReceived => _controller.stream;

  StreamSubscription? _eventSubscription;

  Future<void> initialize() async {
    final granted = await requestPermissions();
    if (!granted) return;

    // Listen to real-time events from EventChannel
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen((data) {
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final tx = ParsedSmsTransaction.fromMap(map);
        _controller.add(tx);
      }
    }, onError: (err) {
      // Handle error or log
    });
  }

  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.sms,
      Permission.phone,
      Permission.notification,
    ].request();

    return statuses[Permission.sms]?.isGranted ?? false;
  }

  /// Fetches all transactions stored in native Room database.
  Future<List<ParsedSmsTransaction>> getTransactions() async {
    try {
      final List? result = await _methodChannel.invokeMethod('getTransactions');
      if (result == null) return [];
      return result.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return ParsedSmsTransaction.fromMap(map);
      }).toList();
    } on PlatformException catch (_) {
      return [];
    }
  }

  /// Fetches recent transactions stored in native Room database.
  Future<List<ParsedSmsTransaction>> getRecentTransactions({int limit = 10}) async {
    try {
      final List? result = await _methodChannel.invokeMethod('getRecentTransactions', {'limit': limit});
      if (result == null) return [];
      return result.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return ParsedSmsTransaction.fromMap(map);
      }).toList();
    } on PlatformException catch (_) {
      return [];
    }
  }

  /// Deletes a transaction from Room database.
  Future<bool> deleteTransaction(String id) async {
    try {
      final bool? result = await _methodChannel.invokeMethod('deleteTransaction', {'id': id});
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Checks if the app was launched by tapping a notification with transaction data.
  Future<ParsedSmsTransaction?> getLaunchTransaction() async {
    try {
      final Map? result = await _methodChannel.invokeMethod('getLaunchTransaction');
      if (result == null) return null;
      final map = Map<String, dynamic>.from(result);
      return ParsedSmsTransaction.fromMap(map);
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// Scans the SMS inbox for the past [months] months using the native content provider.
  Future<List<ParsedSmsTransaction>> scanInbox({int months = 3}) async {
    try {
      final List? result = await _methodChannel.invokeMethod('scanInbox', {'months': months});
      if (result == null) return [];
      return result.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return ParsedSmsTransaction.fromMap(map);
      }).toList();
    } on PlatformException catch (_) {
      return [];
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _controller.close();
  }
}
