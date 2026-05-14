import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/utils/app_theme.dart';

// ─── PIN Lock Screen ────────────────────────────────────────────────────────
class PinLockScreen extends ConsumerStatefulWidget {
  const PinLockScreen({super.key});
  @override
  ConsumerState<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<PinLockScreen> {
  final _storage = const FlutterSecureStorage();
  final _auth = LocalAuthentication();
  String _entered = '';
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _tryBiometric();
  }

  Future<void> _tryBiometric() async {
    final settings = ref.read(settingsProvider);
    if (!settings.biometricEnabled) return;
    try {
      final ok = await _auth.authenticate(localizedReason: 'Unlock Smart Money Manager', options: const AuthenticationOptions(biometricOnly: true));
      if (ok && mounted) Navigator.pop(context);
    } catch (_) {}
  }

  void _onKey(String digit) {
    if (_entered.length >= 6) return;
    setState(() { _entered += digit; _error = false; });
    if (_entered.length == 4 || _entered.length == 6) _verify();
  }

  void _onBackspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _verify() async {
    final stored = await _storage.read(key: 'user_pin');
    if (_entered == stored) {
      if (mounted) Navigator.pop(context);
    } else {
      setState(() { _entered = ''; _error = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 56, color: AppColors.primary),
            const SizedBox(height: 16),
            const Text('Enter PIN', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            if (_error) ...[
              const SizedBox(height: 8),
              const Text('Incorrect PIN. Try again.', style: TextStyle(color: AppColors.expense, fontSize: 13)),
            ],
            const SizedBox(height: 32),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(6, (i) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 14, height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _entered.length ? AppColors.primary : AppColors.primary.withOpacity(0.2),
              ),
            ))),
            const SizedBox(height: 40),
            _PinPad(onKey: _onKey, onBackspace: _onBackspace, onBiometric: _tryBiometric,
                showBiometric: ref.watch(settingsProvider).biometricEnabled),
          ],
        ),
      ),
    );
  }
}

// ─── PIN Setup Screen ───────────────────────────────────────────────────────
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});
  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  final _storage = const FlutterSecureStorage();
  String _pin = '';
  String _confirm = '';
  bool _confirming = false;
  bool _error = false;

  void _onKey(String digit) {
    setState(() {
      if (!_confirming) {
        if (_pin.length < 6) { _pin += digit; if (_pin.length == 4) _confirming = true; }
      } else {
        if (_confirm.length < 6) { _confirm += digit; if (_confirm.length == _pin.length) _save(); }
      }
      _error = false;
    });
  }

  void _onBackspace() {
    setState(() {
      if (_confirming) { _confirm = _confirm.isNotEmpty ? _confirm.substring(0, _confirm.length - 1) : ''; }
      else { _pin = _pin.isNotEmpty ? _pin.substring(0, _pin.length - 1) : ''; }
    });
  }

  Future<void> _save() async {
    if (_pin != _confirm) {
      setState(() { _confirm = ''; _error = true; });
      return;
    }
    await _storage.write(key: 'user_pin', value: _pin);
    await ref.read(settingsProvider.notifier).update(ref.read(settingsProvider).copyWith(pinEnabled: true));
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN set successfully 🔐'), backgroundColor: AppColors.success));
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _confirming ? _confirm : _pin;
    return Scaffold(
      appBar: AppBar(title: const Text('Set PIN')),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_confirming ? 'Confirm your PIN' : 'Choose a PIN (4 or 6 digits)',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (_error) ...[
              const SizedBox(height: 8),
              const Text('PINs don\'t match. Try again.', style: TextStyle(color: AppColors.expense, fontSize: 13)),
            ],
            const SizedBox(height: 32),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(6, (i) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 14, height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < current.length ? AppColors.primary : AppColors.primary.withOpacity(0.2),
              ),
            ))),
            const SizedBox(height: 40),
            _PinPad(onKey: _onKey, onBackspace: _onBackspace),
          ],
        ),
      ),
    );
  }
}

// ─── Shared PIN Pad ─────────────────────────────────────────────────────────
class _PinPad extends StatelessWidget {
  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;
  final bool showBiometric;

  const _PinPad({required this.onKey, required this.onBackspace, this.onBiometric, this.showBiometric = false});

  @override
  Widget build(BuildContext context) {
    final keys = ['1','2','3','4','5','6','7','8','9'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: [
          GridView.count(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.5,
            children: keys.map((k) => _PinKey(label: k, onTap: () => onKey(k))).toList(),
          ),
          const SizedBox(height: 12),
          Row(children: [
            if (showBiometric && onBiometric != null)
              Expanded(child: _PinKey(icon: Icons.fingerprint, onTap: onBiometric!))
            else
              const Expanded(child: SizedBox()),
            Expanded(child: _PinKey(label: '0', onTap: () => onKey('0'))),
            Expanded(child: _PinKey(icon: Icons.backspace_outlined, onTap: onBackspace)),
          ]),
        ],
      ),
    );
  }
}

class _PinKey extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  const _PinKey({this.label, this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
        child: Center(
          child: label != null
              ? Text(label!, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600))
              : Icon(icon, size: 24, color: AppColors.primary),
        ),
      ),
    );
  }
}
