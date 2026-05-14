import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'core/db/database_helper.dart';
import 'core/services/notification_service.dart';
import 'core/services/sms_service.dart';
import 'app.dart';

@pragma('vm:entry-point')
void backgroundSmsHandler(dynamic message) async {
  // Handled in SmsService
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await DatabaseHelper.instance.database;
  await NotificationService.instance.initialize();
  await SmsService.instance.initialize();

  runApp(const ProviderScope(child: FinanceApp()));
}
