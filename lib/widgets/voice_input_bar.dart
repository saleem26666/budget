import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../app_theme.dart';
import '../utils/voice_translate_helper.dart';

/// English / Urdu / Urdu→English mic — device speech + optional translation.
class VoiceInputBar extends StatefulWidget {
  final TextEditingController controller;

  const VoiceInputBar({super.key, required this.controller});

  @override
  State<VoiceInputBar> createState() => _VoiceInputBarState();
}

class _VoiceInputBarState extends State<VoiceInputBar> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  String _activeMode = '';
  String _baseText = '';
  String _pendingSpoken = '';
  bool _availableLocalesLoaded = false;
  List<String> _availableLocales = [];
  bool _initialized = false;
  bool _translating = false;

  Future<void> _ensureLocalesLoaded() async {
    if (_availableLocalesLoaded) return;
    try {
      final locales = await _speech.locales();
      _availableLocales = locales.map((e) => e.localeId).toList();
    } catch (_) {}
    _availableLocalesLoaded = true;
  }

  String _normalizeLocale(String id) =>
      id.toLowerCase().replaceAll('_', '-');

  String _bestLocaleFor(String mode) {
    final wantUrdu = mode == 'ur' || mode == 'ur_en';
    if (!wantUrdu) {
      const preferred = ['en_US', 'en-GB', 'en_IN', 'en-AU', 'en'];
      for (final id in preferred) {
        final match = _availableLocales.firstWhere(
          (l) => _normalizeLocale(l) == _normalizeLocale(id),
          orElse: () => '',
        );
        if (match.isNotEmpty) return match;
      }
      final anyEn = _availableLocales.firstWhere(
        (l) => _normalizeLocale(l).startsWith('en'),
        orElse: () => '',
      );
      return anyEn.isNotEmpty ? anyEn : 'en_US';
    }

    const preferred = ['ur_PK', 'ur-IN', 'ur-AE', 'ur-SA', 'ur'];
    for (final id in preferred) {
      final match = _availableLocales.firstWhere(
        (l) => _normalizeLocale(l) == _normalizeLocale(id),
        orElse: () => '',
      );
      if (match.isNotEmpty) return match;
    }
    final anyUr = _availableLocales.firstWhere(
      (l) => _normalizeLocale(l).startsWith('ur'),
      orElse: () => '',
    );
    return anyUr.isNotEmpty ? anyUr : 'ur_PK';
  }

  Future<bool> _ensureSpeechReady() async {
    if (_initialized) return true;
    final ok = await _speech.initialize(
      onStatus: (status) async {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          await _flushPendingTranslation();
          if (!mounted) return;
          setState(() {
            _listening = false;
            _activeMode = '';
            _translating = false;
          });
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _activeMode = '';
          _translating = false;
          _pendingSpoken = '';
        });
        widget.controller.text = _baseText;
        final msg = error.errorMsg;
        if (msg.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Voice error: $msg')),
          );
        }
      },
    );
    _initialized = ok;
    return ok;
  }

  Future<void> _appendText(String text) async {
    if (text.trim().isEmpty || !mounted) return;
    setState(() {
      _baseText += '${text.trim()} ';
      widget.controller.text = _baseText;
      widget.controller.selection = TextSelection.fromPosition(
        TextPosition(offset: widget.controller.text.length),
      );
    });
  }

  Future<void> _translateAndAppend(String spoken) async {
    final raw = spoken.trim();
    if (raw.isEmpty || !mounted) return;

    setState(() => _translating = true);
    widget.controller.text = _baseText;
    final translated = await VoiceTranslateHelper.urduToEnglish(raw);
    if (!mounted) return;
    setState(() => _translating = false);

    final out = translated.trim();
    if (out.isEmpty) return;

    final failed = out == raw ||
        (VoiceTranslateHelper.looksUrdu(out) &&
            VoiceTranslateHelper.looksUrdu(raw));
    if (failed) {
      widget.controller.text = _baseText;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not translate to English — use Ur → En mic and check internet',
            ),
          ),
        );
      }
      return;
    }

    await _appendText(out);
  }

  Future<void> _flushPendingTranslation() async {
    if (_activeMode != 'ur_en') return;
    final pending = _pendingSpoken.trim();
    _pendingSpoken = '';
    if (pending.isEmpty) return;
    await _translateAndAppend(pending);
  }

  Future<void> _startListening(String mode) async {
    final ok = await _ensureSpeechReady();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone not available')),
        );
      }
      return;
    }
    await _ensureLocalesLoaded();
    final locale = _bestLocaleFor(mode);
    setState(() {
      _listening = true;
      _activeMode = mode;
      _translating = false;
      _pendingSpoken = '';
      _baseText = widget.controller.text;
      if (_baseText.isNotEmpty && !_baseText.endsWith(' ')) {
        _baseText += ' ';
      }
    });

    await _speech.listen(
      localeId: locale,
      listenFor: const Duration(minutes: 2),
      pauseFor: const Duration(seconds: 8),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
      ),
      onResult: (val) async {
        if (!mounted || _activeMode != mode) return;

        final spoken = val.recognizedWords.trim();
        if (mode == 'ur_en') {
          if (spoken.isNotEmpty) _pendingSpoken = spoken;
          if (!val.finalResult) {
            widget.controller.text =
                _baseText.isEmpty ? 'Listening…' : '$_baseText(Listening…)';
            widget.controller.selection = TextSelection.fromPosition(
              TextPosition(offset: widget.controller.text.length),
            );
            return;
          }
          _pendingSpoken = '';
          if (spoken.isEmpty) return;
          await _translateAndAppend(spoken);
          return;
        }

        if (!val.finalResult) {
          widget.controller.text = _baseText + val.recognizedWords;
          widget.controller.selection = TextSelection.fromPosition(
            TextPosition(offset: widget.controller.text.length),
          );
          return;
        }
        if (spoken.isEmpty) return;
        await _appendText(spoken);
      },
    );
  }

  Future<void> _toggle(String mode) async {
    if (_listening && _activeMode == mode) {
      await _flushPendingTranslation();
      await _speech.stop();
      if (mounted) {
        setState(() {
          _listening = false;
          _activeMode = '';
          _translating = false;
          _pendingSpoken = '';
        });
        widget.controller.text = _baseText;
      }
      return;
    }

    if (_listening) {
      await _flushPendingTranslation();
      await _speech.stop();
    }

    await _startListening(mode);
  }

  Widget _chip({
    required String label,
    required String mode,
    required Color color,
    IconData? icon,
  }) {
    final active = _listening && _activeMode == mode;
    final busy = active && _translating;
    return Material(
      color: active ? color.withValues(alpha: 0.15) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: busy ? null : () => _toggle(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? color : Colors.grey.shade300,
              width: active ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                busy
                    ? Icons.hourglass_top_rounded
                    : active
                        ? Icons.mic
                        : (icon ?? Icons.mic_none_rounded),
                size: 18,
                color: active ? Colors.red : color,
              ),
              const SizedBox(width: 6),
              Text(
                busy ? 'Translating…' : (active ? 'Listening…' : label),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: active ? color : Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Voice input',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'اردو = Urdu text · Ur → En = speak Urdu, writes English',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(label: 'English', mode: 'en', color: AppTheme.primary),
            _chip(
              label: 'اردو',
              mode: 'ur',
              color: const Color(0xFF0D9488),
            ),
            _chip(
              label: 'Ur → En',
              mode: 'ur_en',
              color: const Color(0xFF7C3AED),
              icon: Icons.translate_rounded,
            ),
          ],
        ),
      ],
    );
  }
}
