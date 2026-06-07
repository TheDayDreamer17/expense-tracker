import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'core/db/database_helper.dart';
import 'core/services/notification_service.dart';
import 'core/services/native_sms_service.dart';
import 'core/services/recurring_transaction_service.dart';
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

  // Init DB first so all services can use it
  await DatabaseHelper.instance.database;

  // Process any overdue recurring transactions before UI loads
  await RecurringTransactionService.instance.processOverdue();

  // Init notifications and SMS
  await NotificationService.instance.initialize(isMainApp: true);
  await NotificationService.instance.scheduleAllSubscriptionAlerts();
  await NativeSmsService.instance.initialize();

  runApp(const ProviderScope(child: FinanceApp()));
}

