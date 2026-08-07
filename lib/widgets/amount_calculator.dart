import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';

/// Opens a calculator; returns the final number as a string, or null if cancelled.
Future<String?> showAmountCalculator(
  BuildContext context, {
  String? initialValue,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AmountCalculatorSheet(initialValue: initialValue),
  );
}

class _AmountCalculatorSheet extends StatefulWidget {
  final String? initialValue;

  const _AmountCalculatorSheet({this.initialValue});

  @override
  State<_AmountCalculatorSheet> createState() => _AmountCalculatorSheetState();
}

class _AmountCalculatorSheetState extends State<_AmountCalculatorSheet> {
  String _buffer = '0';
  String _history = '';
  double? _acc;
  String? _pendingOp; // +, −, ×, ÷
  bool _fresh = true; // next digit replaces buffer

  @override
  void initState() {
    super.initState();
    final init = (widget.initialValue ?? '').trim();
    final n = double.tryParse(init);
    if (n != null) {
      _buffer = _fmt(n);
    }
  }

  String _fmt(double n) {
    if (n == n.roundToDouble() && n.abs() < 1e12) {
      return n.round().toString();
    }
    var s = n.toStringAsFixed(6);
    s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    return s.isEmpty ? '0' : s;
  }

  void _haptic() => HapticFeedback.selectionClick();

  double? _apply(double a, String op, double b) {
    switch (op) {
      case '+':
        return a + b;
      case '−':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        if (b == 0) return null;
        return a / b;
      default:
        return null;
    }
  }

  void _digit(String d) {
    _haptic();
    setState(() {
      if (_fresh) {
        _buffer = d == '.' ? '0.' : d;
        _fresh = false;
        return;
      }
      if (d == '.' && _buffer.contains('.')) return;
      if (_buffer == '0' && d != '.') {
        _buffer = d;
      } else {
        _buffer = '$_buffer$d';
      }
    });
  }

  void _op(String op) {
    _haptic();
    setState(() {
      final cur = double.tryParse(_buffer) ?? 0;
      if (_acc != null && _pendingOp != null && !_fresh) {
        final r = _apply(_acc!, _pendingOp!, cur);
        if (r == null) {
          _buffer = 'Error';
          _acc = null;
          _pendingOp = null;
          _history = '';
          _fresh = true;
          return;
        }
        _acc = r;
        _buffer = _fmt(r);
      } else {
        _acc = cur;
      }
      _pendingOp = op;
      _history = '${_fmt(_acc!)} $op';
      _fresh = true;
    });
  }

  void _equals() {
    _haptic();
    setState(() {
      if (_pendingOp == null || _acc == null) return;
      final cur = double.tryParse(_buffer) ?? 0;
      final r = _apply(_acc!, _pendingOp!, cur);
      if (r == null) {
        _buffer = 'Error';
        _acc = null;
        _pendingOp = null;
        _history = '';
        _fresh = true;
        return;
      }
      _history = '${_fmt(_acc!)} $_pendingOp ${_fmt(cur)} =';
      _buffer = _fmt(r);
      _acc = r;
      _pendingOp = null;
      _fresh = true;
    });
  }

  void _clear() {
    _haptic();
    setState(() {
      _buffer = '0';
      _history = '';
      _acc = null;
      _pendingOp = null;
      _fresh = true;
    });
  }

  void _backspace() {
    _haptic();
    setState(() {
      if (_fresh || _buffer == 'Error') {
        _buffer = '0';
        _fresh = true;
        return;
      }
      if (_buffer.length <= 1) {
        _buffer = '0';
        _fresh = true;
      } else {
        _buffer = _buffer.substring(0, _buffer.length - 1);
      }
    });
  }

  void _use() {
    _haptic();
    // Finish pending op if any
    if (_pendingOp != null && _acc != null && !_fresh) {
      final cur = double.tryParse(_buffer) ?? 0;
      final r = _apply(_acc!, _pendingOp!, cur);
      if (r != null) {
        _buffer = _fmt(r);
      }
    }
    final n = double.tryParse(_buffer);
    if (n == null || n < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }
    Navigator.pop(context, _fmt(n));
  }

  Widget _key(
    String label, {
    Color? bg,
    Color? fg,
    int flex = 1,
    required VoidCallback onTap,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: bg ?? Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 56,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: label.length > 2 ? 15 : 22,
                    fontWeight: FontWeight.w600,
                    color: fg ?? Colors.black87,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Calculator',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_history.isNotEmpty)
                  Text(
                    _history,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                Text(
                  _buffer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _key('C',
                bg: Colors.orange.shade50,
                fg: Colors.orange.shade800,
                onTap: _clear),
            _key('⌫',
                bg: Colors.orange.shade50,
                fg: Colors.orange.shade800,
                onTap: _backspace),
            _key('÷',
                bg: AppTheme.primary.withValues(alpha: 0.12),
                fg: AppTheme.primary,
                onTap: () => _op('÷')),
            _key('×',
                bg: AppTheme.primary.withValues(alpha: 0.12),
                fg: AppTheme.primary,
                onTap: () => _op('×')),
          ]),
          Row(children: [
            _key('7', onTap: () => _digit('7')),
            _key('8', onTap: () => _digit('8')),
            _key('9', onTap: () => _digit('9')),
            _key('−',
                bg: AppTheme.primary.withValues(alpha: 0.12),
                fg: AppTheme.primary,
                onTap: () => _op('−')),
          ]),
          Row(children: [
            _key('4', onTap: () => _digit('4')),
            _key('5', onTap: () => _digit('5')),
            _key('6', onTap: () => _digit('6')),
            _key('+',
                bg: AppTheme.primary.withValues(alpha: 0.12),
                fg: AppTheme.primary,
                onTap: () => _op('+')),
          ]),
          Row(children: [
            _key('1', onTap: () => _digit('1')),
            _key('2', onTap: () => _digit('2')),
            _key('3', onTap: () => _digit('3')),
            _key('=',
                bg: AppTheme.primary.withValues(alpha: 0.12),
                fg: AppTheme.primary,
                onTap: _equals),
          ]),
          Row(children: [
            _key('0', flex: 2, onTap: () => _digit('0')),
            _key('.', onTap: () => _digit('.')),
            _key('Use',
                bg: AppTheme.primary, fg: Colors.white, onTap: _use),
          ]),
          const SizedBox(height: 4),
          Text(
            'Calculate, then tap Use to fill amount',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
