import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'core/db/database_helper.dart';
import 'core/models/models.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/refresh_provider.dart';
import 'core/utils/app_theme.dart';
import 'features/auth/pin_lock_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/transactions/add_transaction_screen.dart';
import 'features/transactions/transaction_list_screen.dart';
import 'features/copilot/copilot_screen.dart';
import 'features/accounts/accounts_screen.dart';
import 'features/budget/budget_screen.dart';
import 'features/reports/reports_screen.dart';
import 'features/trips/trips_screen.dart';
import 'features/goals/goals_screen.dart';
import 'features/goals/bifurcation_screen.dart';
import 'features/subscriptions/subscriptions_screen.dart';
import 'features/networth/net_worth_screen.dart';
import 'features/health_score/health_score_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/category_manager_screen.dart';
import 'widgets/sms_popup/sms_transaction_sheet.dart';
import 'core/services/native_sms_service.dart';
import 'core/services/notification_service.dart';
import 'dart:async';

class FinanceApp extends ConsumerWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Smart Money Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const AppShell(),
      routes: {
        '/add-transaction': (_) => const AddTransactionScreen(),
        '/transactions': (_) => const TransactionListScreen(),
        '/copilot': (_) => const CopilotScreen(),
        '/accounts': (_) => const AccountsScreen(),
        '/budget': (_) => const BudgetScreen(),
        '/reports': (_) => const ReportsScreen(),
        '/trips': (_) => const TripsScreen(),
        '/goals': (_) => const GoalsScreen(),
        '/bifurcation': (_) => const BifurcationScreen(),
        '/subscriptions': (_) => const SubscriptionsScreen(),
        '/net-worth': (_) => const NetWorthScreen(),
        '/health-score': (_) => const HealthScoreScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/category-manager': (_) => const CategoryManagerScreen(),
      },
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  StreamSubscription<String>? _notificationSubscription;
  bool _isSheetOpen = false;
  final Set<String> _processedTxIds = {};

  final _pages = const [
    DashboardScreen(),
    ReportsScreen(),
    AccountsScreen(),
    BudgetScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAuth();
    _listenForSmsTransactions();
    _checkPendingSms();
    _listenForNotificationTaps();
    _checkLaunchTransaction();
    _checkFirstLaunchRestore();
    _checkInvestmentPromo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLaunchTransaction();
      _checkPendingSms();
    }
  }

  Future<void> _checkFirstLaunchRestore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prompted = prefs.getBool('first_launch_restore_prompted') ?? false;
      if (prompted) return;

      // Check if the database has any transactions
      final db = DatabaseHelper.instance;
      final transactions = await db.query('transactions');
      if (transactions.isNotEmpty) {
        // Mark as prompted since there's already data
        await prefs.setBool('first_launch_restore_prompted', true);
        return;
      }

      // Show prompt dialog on next frame
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final restore = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Restore from Backup?'),
            content: const Text(
              'Welcome to Smart Money Manager! It looks like this is a fresh install. If you have a backup JSON file saved on your device, you can restore your accounts and transactions now.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Start Fresh'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Select Backup File'),
              ),
            ],
          ),
        );

        // Mark as prompted regardless of user's choice
        await prefs.setBool('first_launch_restore_prompted', true);

        if (restore == true) {
          await _importDataFromStartup();
        }
      });
    } catch (_) {}
  }

  Future<void> _importDataFromStartup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null) return;
      
      final file = File(path);
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

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
        
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Import failed: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _showTransactionSheet(ParsedSmsTransaction tx) {
    if (tx.id != null) {
      if (_processedTxIds.contains(tx.id)) return;
      _processedTxIds.add(tx.id!);
    }

    if (_isSheetOpen) return;
    _isSheetOpen = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _isSheetOpen = false;
        return;
      }
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SmsTransactionSheet(parsed: tx),
      );
      _isSheetOpen = false;
    });
  }

  Future<void> _checkLaunchTransaction() async {
    final launchTx = await NativeSmsService.instance.getLaunchTransaction();
    if (launchTx != null) {
      if (!mounted) return;
      _showTransactionSheet(launchTx);
    }
  }

  void _listenForNotificationTaps() {
    // 1. Check if the app was launched by tapping a notification (terminated state)
    final launchPayload = NotificationService.instance.launchPayload;
    if (launchPayload == 'sms') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkPendingSms();
      });
    }

    // 2. Listen to active notification taps (background/foreground state)
    _notificationSubscription = NotificationService.instance.selectNotificationStream.listen((payload) {
      if (payload == 'sms') {
        _checkPendingSms();
      }
    });
  }

  Future<void> _checkPendingSms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final pending = prefs.getString('pending_sms_tx');
    if (pending != null) {
      await prefs.remove('pending_sms_tx');
      final parsed = ParsedSmsTransaction.fromMap(jsonDecode(pending) as Map<String, dynamic>);
      if (!mounted) return;
      _showTransactionSheet(parsed);
    }
  }

  void _checkAuth() {
    final pinEnabled = ref.read(settingsProvider).pinEnabled;
    if (pinEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PinLockScreen()),
        );
      });
    }
  }

  void _listenForSmsTransactions() {
    ref.listenManual(nativeSmsTransactionStreamProvider, (_, next) {
      next.whenData((parsed) {
        if (!mounted) return;
        _showTransactionSheet(parsed);
      });
    });
  }

  Future<void> _checkInvestmentPromo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentCount = prefs.getInt('app_open_count') ?? 0;
      final newCount = currentCount + 1;
      await prefs.setInt('app_open_count', newCount);

      final shown = prefs.getBool('promo_investment_shown') ?? false;
      if (newCount >= 3 && !shown) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showInvestmentPromoDialog(prefs);
        });
      }
    } catch (_) {}
  }

  void _showInvestmentPromoDialog(SharedPreferences prefs) {
    final amountCtrl = TextEditingController();
    final nameCtrl = TextEditingController(text: 'Mutual Funds SIP');
    String subType = 'MF';
    final subTypes = ['Bank', 'FD', 'MF', 'Stocks', 'Gold', 'Real Estate', 'Other'];
    bool saving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Row(
            children: [
              Text('📈 ', style: TextStyle(fontSize: 24)),
              Expanded(
                child: Text(
                  'Auto-Grow Your Wealth!',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Record your investments (mutual funds, FDs, stocks, etc.) inside Net Worth to easily monitor your wealth growth.',
                style: TextStyle(fontSize: 13, color: AppColors.lightTextSecondary),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: subType,
                decoration: const InputDecoration(labelText: 'Investment Type'),
                items: subTypes.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setStateDialog(() => subType = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Investment Name (e.g. SBI FD, Nifty SIP)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                decoration: const InputDecoration(labelText: 'Amount Put in Investment', prefixText: '₹ '),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await prefs.setBool('promo_investment_shown', true);
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              },
              child: const Text('Never Show Again'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
              },
              child: const Text('Remind Later'),
            ),
            ElevatedButton(
              onPressed: saving ? null : () async {
                final amt = double.tryParse(amountCtrl.text.trim());
                final name = nameCtrl.text.trim();
                if (amt == null || amt <= 0 || name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid name and amount')),
                  );
                  return;
                }
                
                setStateDialog(() => saving = true);
                
                final db = DatabaseHelper.instance;
                await db.insert('net_worth_entries', {
                  'id': const Uuid().v4(),
                  'entry_type': 'ASSET',
                  'sub_type': subType,
                  'name': name,
                  'amount': amt,
                  'date': DateTime.now().millisecondsSinceEpoch,
                });
                
                await prefs.setBool('promo_investment_shown', true);
                if (dialogCtx.mounted) {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Logged ₹${amt.toStringAsFixed(0)} in $name!'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save Investment'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = ref.watch(currentTabProvider);
    return Scaffold(
      body: IndexedStack(index: activeIndex, children: _pages),
      bottomNavigationBar: _BottomNav(
        currentIndex: activeIndex,
        onTap: (i) => ref.read(currentTabProvider.notifier).state = i,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pushNamed(context, '/add-transaction'),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BottomAppBar(
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      elevation: 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(icon: Icons.home_rounded, label: 'Home', index: 0, current: currentIndex, onTap: onTap),
          _NavItem(icon: Icons.bar_chart_rounded, label: 'Reports', index: 1, current: currentIndex, onTap: onTap),
          const SizedBox(width: 48), // FAB space
          _NavItem(icon: Icons.account_balance_wallet_rounded, label: 'Accounts', index: 2, current: currentIndex, onTap: onTap),
          _NavItem(icon: Icons.tune_rounded, label: 'Budget', index: 3, current: currentIndex, onTap: onTap),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int current;
  final ValueChanged<int> onTap;

  const _NavItem({required this.icon, required this.label, required this.index, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = index == current;
    return InkWell(
      onTap: () => onTap(index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? AppColors.primary : AppColors.darkTextSecondary, size: 24),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppColors.primary : AppColors.darkTextSecondary,
            )),
          ],
        ),
      ),
    );
  }
}
