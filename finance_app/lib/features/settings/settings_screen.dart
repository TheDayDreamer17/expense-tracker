import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../core/db/database_helper.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/notification_service.dart';
import '../../core/utils/app_theme.dart';
import '../../core/utils/formatters.dart';
// import '../auth/pin_setup_screen.dart';
import '../auth/sms_scanner_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _auth = LocalAuthentication();
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final available = await _auth.canCheckBiometrics;
    if (mounted) setState(() => _biometricAvailable = available);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // App header
          Center(
            child: Column(children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.account_balance_wallet,
                    color: Colors.white, size: 36),
              ),
              const SizedBox(height: 8),
              const Text('Smart Money Manager',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Text('v1.0.0',
                  style: TextStyle(
                      color: AppColors.lightTextSecondary, fontSize: 12)),
            ]),
          ).animate().fadeIn(),
          const SizedBox(height: 24),

          _SectionHeader('Appearance'),
          _SettingCard(children: [
            _SettingRow(
              icon: Icons.palette_outlined,
              label: 'Theme',
              trailing: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {themeMode},
                onSelectionChanged: (s) =>
                    ref.read(themeModeProvider.notifier).setTheme(s.first),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ),
          ]),

          _SectionHeader('Notifications'),
          _SettingCard(children: [
            _SettingRow(
              icon: Icons.notifications_active_outlined,
              label: 'Monthly Income Reminder',
              subtitle: '1st of every month',
              trailing: Switch(
                value: settings.incomeReminderEnabled,
                onChanged: (v) async {
                  await ref
                      .read(settingsProvider.notifier)
                      .update(settings.copyWith(incomeReminderEnabled: v));
                  if (v) {
                    final parts = settings.incomeReminderTime.split(':');
                    await NotificationService.instance
                        .scheduleMonthlyIncomeReminder(
                            hour: int.parse(parts[0]),
                            minute: int.parse(parts[1]));
                  } else {
                    await NotificationService.instance.cancelIncomeReminder();
                  }
                },
                activeThumbColor: AppColors.primary,
              ),
            ),
            if (settings.incomeReminderEnabled)
              _SettingRow(
                icon: Icons.access_time_outlined,
                label: 'Reminder Time',
                subtitle: settings.incomeReminderTime,
                onTap: () => _pickReminderTime(settings),
              ),
          ]),

          _SectionHeader('Security'),
          _SettingCard(children: [
            _SettingRow(
              icon: Icons.pin_outlined,
              label: 'PIN Lock',
              subtitle: settings.pinEnabled ? 'Enabled' : 'Disabled',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN Setup coming soon!'))
                );
              },
            ),
            if (_biometricAvailable)
              _SettingRow(
                icon: Icons.fingerprint,
                label: 'Fingerprint Unlock',
                trailing: Switch(
                  value: settings.biometricEnabled,
                  onChanged: settings.pinEnabled
                      ? (v) => ref
                          .read(settingsProvider.notifier)
                          .update(settings.copyWith(biometricEnabled: v))
                      : null,
                  activeThumbColor: AppColors.primary,
                ),
              ),
          ]),

          _SectionHeader('SMS & Import'),
          _SettingCard(children: [
            _SettingRow(
              icon: Icons.sms_outlined,
              label: 'Scan SMS Inbox',
              subtitle: 'Import historical transactions from SMS',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SmsScannerScreen())),
            ),
          ]),

          _SectionHeader('AI Features'),
          _SettingCard(children: [
            _SettingRow(
              icon: Icons.auto_awesome,
              label: 'Gemini API Key',
              subtitle: settings.geminiApiKey?.isNotEmpty == true
                  ? 'Connected'
                  : 'Not configured',
              onTap: _setApiKey,
            ),
          ]),

          _SectionHeader('Backup & Restore'),
          _SettingCard(children: [
            _SettingRow(
              icon: Icons.cloud_upload_outlined,
              label: 'Back up to Google Drive',
              subtitle: 'Upload or replace backup file in Google Drive',
              onTap: _backupToGoogleDrive,
            ),
            _SettingRow(
              icon: Icons.settings_backup_restore_outlined,
              label: 'Local Auto-Backup',
              subtitle: 'Auto-saves in Downloads/SmartMoneyManager on change',
              trailing: Switch(
                value: settings.localAutoBackupEnabled,
                onChanged: (v) async {
                  await ref
                      .read(settingsProvider.notifier)
                      .update(settings.copyWith(localAutoBackupEnabled: v));
                },
                activeThumbColor: AppColors.primary,
              ),
            ),
            _SettingRow(
              icon: Icons.upload_outlined,
              label: 'Export Data Manually',
              subtitle: 'Save JSON backup file to device',
              onTap: _exportData,
            ),
            _SettingRow(
              icon: Icons.download_outlined,
              label: 'Import Data Manually',
              subtitle: 'Restore from JSON backup file',
              onTap: _importData,
            ),
          ]),

          _SectionHeader('About'),
          _SettingCard(children: [
            _SettingRow(
                icon: Icons.code_outlined,
                label: 'Built with Flutter',
                subtitle: 'Open source'),
            _SettingRow(
                icon: Icons.favorite_outline,
                label: 'Made with ❤️ by TheDayDreamer17'),
          ]),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _pickReminderTime(AppSettings settings) async {
    final parts = settings.incomeReminderTime.split(':');
    final time = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (time != null) {
      final timeStr =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      await ref
          .read(settingsProvider.notifier)
          .update(settings.copyWith(incomeReminderTime: timeStr));
      await NotificationService.instance
          .scheduleMonthlyIncomeReminder(hour: time.hour, minute: time.minute);
    }
  }

  Future<void> _setApiKey() async {
    final ctrl =
        TextEditingController(text: ref.read(settingsProvider).geminiApiKey);
    final key = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Gemini API Key'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              hintText: 'Paste your API key here',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (key != null) {
      final s = ref.read(settingsProvider);
      await ref
          .read(settingsProvider.notifier)
          .update(s.copyWith(geminiApiKey: key.isEmpty ? null : key));
    }
  }

  Future<void> _exportData() async {
    try {
      final db = DatabaseHelper.instance;
      final data = {
        'exported_at': DateTime.now().toIso8601String(),
        'version': '1.0.0',
        'accounts': await db.query('accounts'),
        'categories': await db.query('categories'),
        'transactions': await db.query('transactions'),
        'budgets': await db.query('budgets'),
        'trips': await db.query('trips'),
        'goals': await db.query('goals'),
        'subscriptions': await db.query('subscriptions'),
        'net_worth_entries': await db.query('net_worth_entries'),
      };
      final json = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/smart_money_backup_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(json);
      await Share.shareXFiles([XFile(file.path)],
          text: 'Smart Money Manager Backup');
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _importData() async {
    try {
      final result = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.first.path!);
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Import Data'),
          content: Text(
              'This will merge data from backup (${data['exported_at']}). Existing data will NOT be deleted.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Import')),
          ],
        ),
      );
      if (confirm != true) return;

      final db = DatabaseHelper.instance;
      for (final table in [
        'accounts',
        'categories',
        'transactions',
        'budgets',
        'trips',
        'goals',
        'subscriptions',
        'net_worth_entries'
      ]) {
        final rows = data[table] as List<dynamic>? ?? [];
        for (final row in rows) {
          await db.insert(table, Map<String, dynamic>.from(row as Map));
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Data imported successfully!'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<void> _backupToGoogleDrive() async {
    try {
      final db = DatabaseHelper.instance;
      final data = {
        'exported_at': DateTime.now().toIso8601String(),
        'version': '1.0.0',
        'accounts': await db.query('accounts'),
        'categories': await db.query('categories'),
        'transactions': await db.query('transactions'),
        'budgets': await db.query('budgets'),
        'trips': await db.query('trips'),
        'goals': await db.query('goals'),
        'subscriptions': await db.query('subscriptions'),
        'net_worth_entries': await db.query('net_worth_entries'),
      };
      final json = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/smart_money_backup_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(json);
      
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Smart Money Manager Backup',
        text: 'Backup of Smart Money Manager data. Save this file to Google Drive to keep it secure.',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Backup failed: $e')));
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                letterSpacing: 0.5)),
      );
}

class _SettingCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingCard({required this.children});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(0.5)),
        ),
        child: Column(
            children: children.indexed.map((e) {
          final isLast = e.$1 == children.length - 1;
          return Column(children: [
            e.$2,
            if (!isLast) const Divider(height: 1, indent: 16, endIndent: 16),
          ]);
        }).toList()),
      );
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SettingRow(
      {required this.icon,
      required this.label,
      this.subtitle,
      this.trailing,
      this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: AppColors.primary, size: 22),
        title: Text(label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.lightTextSecondary))
            : null,
        trailing: trailing ??
            (onTap != null
                ? const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.lightTextSecondary)
                : null),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      );
}
