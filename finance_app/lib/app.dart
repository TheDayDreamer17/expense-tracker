import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/providers/settings_provider.dart';
import 'core/utils/app_theme.dart';
import 'features/auth/pin_lock_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/transactions/add_transaction_screen.dart';
import 'features/transactions/transaction_list_screen.dart';
import 'features/accounts/accounts_screen.dart';
import 'features/budget/budget_screen.dart';
import 'features/reports/reports_screen.dart';
import 'features/trips/trips_screen.dart';
import 'features/goals/goals_screen.dart';
import 'features/subscriptions/subscriptions_screen.dart';
import 'features/networth/net_worth_screen.dart';
import 'features/health_score/health_score_screen.dart';
import 'features/settings/settings_screen.dart';
import 'widgets/sms_popup/sms_transaction_sheet.dart';

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
        '/accounts': (_) => const AccountsScreen(),
        '/budget': (_) => const BudgetScreen(),
        '/reports': (_) => const ReportsScreen(),
        '/trips': (_) => const TripsScreen(),
        '/goals': (_) => const GoalsScreen(),
        '/subscriptions': (_) => const SubscriptionsScreen(),
        '/net-worth': (_) => const NetWorthScreen(),
        '/health-score': (_) => const HealthScoreScreen(),
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex = 0;

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
    _checkAuth();
    _listenForSmsTransactions();
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
    ref.listenManual(smsTransactionStreamProvider, (_, next) {
      next.whenData((parsed) {
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => SmsTransactionSheet(parsed: parsed),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
