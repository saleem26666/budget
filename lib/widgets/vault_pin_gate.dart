import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/vault_pin_prefs.dart';

/// Short PIN unlock dialog before importing shared media into the vault.
class VaultPinGate {
  static Future<bool> unlock(BuildContext context) async {
    if (!await VaultPinPrefs.isSet()) return true;
    if (!context.mounted) return false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _VaultPinDialog(),
    );
    return ok == true;
  }
}

class _VaultPinDialog extends StatefulWidget {
  const _VaultPinDialog();

  @override
  State<_VaultPinDialog> createState() => _VaultPinDialogState();
}

class _VaultPinDialogState extends State<_VaultPinDialog> {
  String _entered = '';
  bool _error = false;
  bool _checking = false;

  Future<void> _onDigit(String d) async {
    if (_checking || _entered.length >= 4) return;
    HapticFeedback.lightImpact();
    setState(() {
      _entered += d;
      _error = false;
    });
    if (_entered.length == 4) {
      setState(() => _checking = true);
      final ok = await VaultPinPrefs.verify(_entered);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _error = true;
          _entered = '';
          _checking = false;
        });
      }
    }
  }

  void _onDelete() {
    if (_entered.isEmpty) return;
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _error = false;
    });
  }

  Widget _dot(int index) {
    final filled = index < _entered.length;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled
            ? (_error ? Colors.red : const Color(0xFF4F46E5))
            : Colors.grey.shade300,
      ),
    );
  }

  Widget _key(String label, {VoidCallback? onTap, IconData? icon}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: SizedBox(
        width: 64,
        height: 56,
        child: Center(
          child: icon != null
              ? Icon(icon, size: 22)
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Vault PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _error ? 'Wrong PIN' : 'Enter PIN to save document',
            style: TextStyle(
              color: _error ? Colors.red : Colors.grey.shade700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, _dot),
          ),
          const SizedBox(height: 20),
          for (final row in [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row
                  .map((d) => _key(d, onTap: () => _onDigit(d)))
                  .toList(),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 64, height: 56),
              _key('0', onTap: () => _onDigit('0')),
              _key('', icon: Icons.backspace_outlined, onTap: _onDelete),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
