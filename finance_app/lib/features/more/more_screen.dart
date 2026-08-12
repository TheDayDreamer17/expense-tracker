import 'package:flutter/material.dart';
import '../../core/utils/app_theme.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : Colors.white;

    final items = [
      {
        'icon': Icons.account_balance_wallet_outlined,
        'label': 'Accounts',
        'sub': 'Manage cash, bank accounts & credit cards',
        'color': AppColors.primary,
        'route': '/accounts',
      },
      {
        'icon': Icons.flag_outlined,
        'label': 'Goals',
        'sub': 'Track your savings & target goals',
        'color': AppColors.success,
        'route': '/goals',
      },
      {
        'icon': Icons.map_outlined,
        'label': 'Trips & Budgets',
        'sub': 'Group travel expenses & budgets',
        'color': Colors.orange,
        'route': '/trips',
      },
      {
        'icon': Icons.pie_chart_outline,
        'label': 'Net Worth',
        'sub': 'Monitor your assets & investment values',
        'color': Colors.purple,
        'route': '/net-worth',
      },
      {
        'icon': Icons.loop,
        'label': 'Subscriptions',
        'sub': 'Track recurring bills & memberships',
        'color': AppColors.expense,
        'route': '/subscriptions',
      },
      {
        'icon': Icons.auto_awesome,
        'label': 'Orbit AI Copilot',
        'sub': 'Chat with your personal financial AI',
        'color': Colors.teal,
        'route': '/copilot',
      },
      {
        'icon': Icons.settings_outlined,
        'label': 'Settings',
        'sub': 'Preferences, security & key configs',
        'color': Colors.grey,
        'route': '/settings',
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('More Features'),
        centerTitle: false,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final color = item['color'] as Color;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).dividerColor.withOpacity(0.08),
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  item['icon'] as IconData,
                  color: color,
                  size: 24,
                ),
              ),
              title: Text(
                item['label'] as String,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  item['sub'] as String,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: AppColors.lightTextSecondary,
                size: 20,
              ),
              onTap: () => Navigator.pushNamed(context, item['route'] as String),
            ),
          );
        },
      ),
    );
  }
}
