import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/approval_policy.dart';
import '../core/nexus_theme.dart';
import '../core/pty_service.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final PtyService _pty = PtyService();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final StringBuffer _output = StringBuffer();
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _running = false;
  bool _busy = false;
  String _status = 'الجلسة غير مشغّلة';

  @override
  void initState() {
    super.initState();
    _subscription = _pty.events.listen(
      _onEvent,
      onError: (Object error) {
        if (mounted) setState(() => _status = 'خطأ في أحداث PTY: $error');
      },
    );
  }

  void _onEvent(Map<String, dynamic> event) {
    final data = event['data']?.toString() ?? '';
    if (data.isEmpty || !mounted) return;
    setState(() {
      _output.write(data);
      if (data.contains('[PTY session closed]')) {
        _running = false;
        _status = 'أُغلقت جلسة PTY';
      }
      if (_output.length > 80000) {
        final trimmed = _output.toString().substring(_output.length - 60000);
        _output.clear();
        _output.write(trimmed);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _start() async {
    setState(() { _busy = true; _status = 'جارٍ إنشاء جلسة PTY…'; });
    try {
      await _pty.start(rows: 30, columns: 100);
      if (mounted) setState(() { _running = true; _status = 'جلسة Android shell نشطة — /system/bin/sh'; });
    } catch (error) {
      if (mounted) setState(() => _status = 'تعذر تشغيل PTY: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final command = _input.text;
    if (command.trim().isEmpty || !_running) return;
    final decision = ApprovalPolicy.inspectCommand(command);
    if (decision.requiresApproval) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('موافقة مطلوبة'),
          content: Text('${decision.reason}\n\n$command', textDirection: TextDirection.ltr),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('أوافق على تشغيل الأمر')),
          ],
        ),
      );
      if (approved != true) return;
    }
    _input.clear();
    try {
      await _pty.write('$command\n');
    } catch (error) {
      if (mounted) setState(() => _status = 'فشل إرسال الأمر: $error');
    }
  }

  Future<void> _close() async {
    try { await _pty.close(); } catch (_) {}
    if (mounted) setState(() { _running = false; _status = 'أُغلقت الجلسة'; });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _input.dispose();
    _scroll.dispose();
    _pty.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(17, 16, 17, 12),
          child: Row(children: [
            const NexusIconTile(Icons.terminal_rounded, size: 43),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Android PTY Console', style: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w900, fontSize: 14)),
              const SizedBox(height: 3),
              Text(_status, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NexusPalette.muted, fontSize: 9)),
            ])),
            if (!_running)
              FilledButton.icon(onPressed: _busy ? null : _start, icon: const Icon(Icons.play_arrow_rounded), label: const Text('تشغيل'))
            else
              OutlinedButton.icon(onPressed: _close, icon: const Icon(Icons.stop_rounded), label: const Text('إيقاف')),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(21),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF07090E),
                  borderRadius: BorderRadius.circular(21),
                  border: Border.all(color: NexusPalette.border),
                  boxShadow: const [BoxShadow(color: Color(0x338B5CF6), blurRadius: 18, offset: Offset(0, 5))],
                ),
                child: SelectionArea(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(15),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        _output.isEmpty ? 'TERMI AI NEXUS  /  PTY\nاضغط تشغيل لبدء جلسة طرفية تفاعلية.\n\nتنبيه: هذه طرفية Android وليست توزيعة Debian أو Ubuntu.\n' : _output.toString(),
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontFamily: 'monospace', color: NexusPalette.terminal, fontSize: 11.5, height: 1.52),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 13),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _input,
              enabled: _running,
              textDirection: TextDirection.ltr,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(hintText: 'اكتب أمر shell…', prefixIcon: Icon(Icons.chevron_right_rounded), isDense: true),
            )),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _running ? _send : null, icon: const Icon(Icons.send_rounded)),
          ]),
        ),
      ]);
}
