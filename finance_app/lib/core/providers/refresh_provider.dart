import 'package:flutter_riverpod/flutter_riverpod.dart';

/// StateProvider to signal screens to refresh transaction/account data
final transactionUpdateProvider = StateProvider<int>((ref) => 0);
