import 'package:flutter_riverpod/flutter_riverpod.dart';

/// StateProvider to signal screens to refresh transaction/account data
final transactionUpdateProvider = StateProvider<int>((ref) => 0);

/// StateProvider to control bottom navigation index globally
final currentTabProvider = StateProvider<int>((ref) => 0);

/// StateProvider to control Reports screen categories vs merchants sub-tab globally
final reportsSubTabProvider = StateProvider<String>((ref) => 'CATEGORIES');
