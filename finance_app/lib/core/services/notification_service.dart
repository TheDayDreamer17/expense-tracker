import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'finance_app_main';
  static const _channelName = 'Finance App';

  // Notification IDs
  static const incomeReminderId = 1001;
  static const budgetAlertBaseId = 2000;
  static const subscriptionAlertBaseId = 3000;
  static const goalMilestoneBaseId = 4000;

  Future<void> initialize() async {
    tz.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    await _createChannel();
  }

  Future<void> _createChannel() async {
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Finance App notifications',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  void _onNotificationTap(NotificationResponse response) {
    // Navigation handled via payload in the app
  }

  // ─── Income Reminder ────────────────────────────────────────────────────
  Future<void> scheduleMonthlyIncomeReminder({
    required int hour,
    required int minute,
  }) async {
    await _plugin.cancel(incomeReminderId);
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, 1, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = tz.TZDateTime(tz.local, now.year, now.month + 1, 1, hour, minute);
    }
    await _plugin.zonedSchedule(
      incomeReminderId,
      '💰 Income Reminder',
      "Don't forget to log your income for ${_monthName(scheduled.month)}!",
      scheduled,
      _notifDetails(payload: 'add_income'),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
    );
  }

  Future<void> cancelIncomeReminder() => _plugin.cancel(incomeReminderId);

  // ─── Budget Alert ───────────────────────────────────────────────────────
  Future<void> showBudgetAlert({
    required String categoryName,
    required double percent,
    required int categoryIndex,
  }) async {
    await _plugin.show(
      budgetAlertBaseId + categoryIndex,
      '🔴 Budget Alert',
      '$categoryName budget is ${(percent * 100).toInt()}% used',
      _notifDetails(payload: 'budget'),
    );
  }

  // ─── Subscription Alert ─────────────────────────────────────────────────
  Future<void> scheduleSubscriptionAlert({
    required String subId,
    required String name,
    required double amount,
    required DateTime billingDate,
    required int index,
  }) async {
    final alertDate = billingDate.subtract(const Duration(days: 3));
    if (alertDate.isBefore(DateTime.now())) return;
    final tzDate = tz.TZDateTime.from(alertDate, tz.local);
    await _plugin.zonedSchedule(
      subscriptionAlertBaseId + index,
      '💳 Upcoming Subscription',
      '$name charges ₹${amount.toStringAsFixed(0)} in 3 days',
      tzDate,
      _notifDetails(payload: 'subscription:$subId'),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> showUnusedSubscriptionAlert({
    required String name,
    required int daysSinceUsed,
    required double amount,
    required int index,
  }) async {
    await _plugin.show(
      subscriptionAlertBaseId + 500 + index,
      '⚠️ Unused Subscription',
      "You haven't used $name in $daysSinceUsed days — still worth ₹${amount.toStringAsFixed(0)}/mo?",
      _notifDetails(payload: 'subscription'),
    );
  }

  // ─── Goal Milestone ─────────────────────────────────────────────────────
  Future<void> showGoalMilestone({
    required String goalName,
    required int percent,
    required int index,
  }) async {
    await _plugin.show(
      goalMilestoneBaseId + index,
      '🎯 Goal Milestone!',
      "You're $percent% toward your $goalName goal!",
      _notifDetails(payload: 'goals'),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────
  NotificationDetails _notifDetails({String? payload}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: const BigTextStyleInformation(''),
        icon: '@mipmap/ic_launcher',
      ),
    );
  }

  String _monthName(int month) {
    const months = ['', 'January', 'February', 'March', 'April', 'May',
      'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return months[month];
  }
}
