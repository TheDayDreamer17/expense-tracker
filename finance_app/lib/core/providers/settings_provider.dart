import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Theme provider ────────────────────────────────────────────────────────
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString('theme') ?? 'system';
    state = _fromString(val);
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', _toString(mode));
  }

  ThemeMode _fromString(String v) => switch (v) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  String _toString(ThemeMode m) => switch (m) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    _ => 'system',
  };
}

// ─── Settings model ────────────────────────────────────────────────────────
class AppSettings {
  final String currency;
  final String currencySymbol;
  final String defaultAccountId;
  final bool incomeReminderEnabled;
  final String incomeReminderTime;
  final bool pinEnabled;
  final bool biometricEnabled;
  final bool onboardingDone;
  final String? geminiApiKey;
  final bool localAutoBackupEnabled;
  final String aiProvider;
  final String? aiApiKey;
  final String? aiCustomEndpoint;
  final String? aiModel;

  const AppSettings({
    this.currency = 'INR',
    this.currencySymbol = '₹',
    this.defaultAccountId = 'acc_cash',
    this.incomeReminderEnabled = true,
    this.incomeReminderTime = '09:00',
    this.pinEnabled = false,
    this.biometricEnabled = false,
    this.onboardingDone = false,
    this.geminiApiKey,
    this.localAutoBackupEnabled = true,
    this.aiProvider = 'gemini',
    this.aiApiKey,
    this.aiCustomEndpoint = '',
    this.aiModel = 'gemini-1.5-flash',
  });

  AppSettings copyWith({
    String? currency, String? currencySymbol, String? defaultAccountId,
    bool? incomeReminderEnabled, String? incomeReminderTime,
    bool? pinEnabled, bool? biometricEnabled, bool? onboardingDone,
    String? geminiApiKey, bool? localAutoBackupEnabled,
    String? aiProvider, String? aiApiKey, String? aiCustomEndpoint, String? aiModel,
  }) {
    return AppSettings(
      currency: currency ?? this.currency,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      defaultAccountId: defaultAccountId ?? this.defaultAccountId,
      incomeReminderEnabled: incomeReminderEnabled ?? this.incomeReminderEnabled,
      incomeReminderTime: incomeReminderTime ?? this.incomeReminderTime,
      pinEnabled: pinEnabled ?? this.pinEnabled,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      onboardingDone: onboardingDone ?? this.onboardingDone,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      localAutoBackupEnabled: localAutoBackupEnabled ?? this.localAutoBackupEnabled,
      aiProvider: aiProvider ?? this.aiProvider,
      aiApiKey: aiApiKey ?? this.aiApiKey,
      aiCustomEndpoint: aiCustomEndpoint ?? this.aiCustomEndpoint,
      aiModel: aiModel ?? this.aiModel,
    );
  }
}

// ─── Settings provider ─────────────────────────────────────────────────────
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      currency: prefs.getString('currency') ?? 'INR',
      currencySymbol: prefs.getString('currency_symbol') ?? '₹',
      defaultAccountId: prefs.getString('default_account') ?? 'acc_cash',
      incomeReminderEnabled: prefs.getBool('income_reminder_enabled') ?? true,
      incomeReminderTime: prefs.getString('income_reminder_time') ?? '09:00',
      pinEnabled: prefs.getBool('pin_enabled') ?? false,
      biometricEnabled: prefs.getBool('biometric_enabled') ?? false,
      onboardingDone: prefs.getBool('onboarding_done') ?? false,
      geminiApiKey: prefs.getString('gemini_api_key'),
      localAutoBackupEnabled: prefs.getBool('local_auto_backup_enabled') ?? true,
      aiProvider: prefs.getString('ai_provider') ?? 'gemini',
      aiApiKey: prefs.getString('ai_api_key'),
      aiCustomEndpoint: prefs.getString('ai_custom_endpoint') ?? '',
      aiModel: prefs.getString('ai_model') ?? 'gemini-1.5-flash',
    );
  }

  Future<void> update(AppSettings updated) async {
    state = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currency', updated.currency);
    await prefs.setString('currency_symbol', updated.currencySymbol);
    await prefs.setString('default_account', updated.defaultAccountId);
    await prefs.setBool('income_reminder_enabled', updated.incomeReminderEnabled);
    await prefs.setString('income_reminder_time', updated.incomeReminderTime);
    await prefs.setBool('pin_enabled', updated.pinEnabled);
    await prefs.setBool('biometric_enabled', updated.biometricEnabled);
    await prefs.setBool('onboarding_done', updated.onboardingDone);
    await prefs.setBool('local_auto_backup_enabled', updated.localAutoBackupEnabled);
    if (updated.geminiApiKey != null) {
      await prefs.setString('gemini_api_key', updated.geminiApiKey!);
    } else {
      await prefs.remove('gemini_api_key');
    }
    await prefs.setString('ai_provider', updated.aiProvider);
    if (updated.aiApiKey != null) {
      await prefs.setString('ai_api_key', updated.aiApiKey!);
    } else {
      await prefs.remove('ai_api_key');
    }
    await prefs.setString('ai_custom_endpoint', updated.aiCustomEndpoint ?? '');
    await prefs.setString('ai_model', updated.aiModel ?? '');
    
    // Fallback sync for gemini key
    if (updated.aiProvider == 'gemini' && updated.aiApiKey != null) {
      await prefs.setString('gemini_api_key', updated.aiApiKey!);
    }
  }
}
