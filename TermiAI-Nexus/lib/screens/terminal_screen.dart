import 'dart:async';
import 'package:flutter/material.dart';
import '../core/approval_policy.dart';
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
  void initState() { super.initState(); _subscription = _pty.events.listen(_onEvent, onError: (Object e) { if (mounted) setState(() => _status = 'PTY event error: $e'); }); }
  void _onEvent(Map<String, dynamic> event) {
    final data = event['data']?.toString() ?? '';
    if (data.isNotEmpty && mounted) {
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
      WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent); });
    }
  }

  Future<void> _start() async {
    setState(() { _busy = true; _status = 'جارٍ إنشاء PTY…'; });
    try {
      await _pty.start(rows: 30, columns: 100);
      if (mounted) setState(() { _running = true; _status = 'جلسة Android shell نشطة — /system/bin/sh'; });
    } catch (e) { if (mounted) setState(() => _status = 'تعذر تشغيل PTY: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _send() async {
    final command = _input.text;
    if (command.trim().isEmpty || !_running) return;
    final decision = ApprovalPolicy.inspectCommand(command);
    if (decision.requiresApproval) {
      final approved = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('موافقة مطلوبة'), content: Text('${decision.reason}\n\n$command'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('أوافق على تشغيل الأمر'))]));
      if (approved != true) return;
    }
    _input.clear();
    try { await _pty.write('$command\n'); }
    catch (e) { if (mounted) setState(() => _status = 'فشل إرسال الأمر: $e'); }
  }

  Future<void> _close() async {
    try { await _pty.close(); } catch (_) {}
    if (mounted) setState(() { _running = false; _status = 'أُغلقت الجلسة'; });
  }

  @override
  void dispose() { _subscription?.cancel(); _input.dispose(); _scroll.dispose(); _pty.close(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 10), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Android PTY Console', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), Text(_status, style: const TextStyle(color: Color(0xFF91A6BE), fontSize: 10))])), if (!_running) FilledButton.icon(onPressed: _busy ? null : _start, icon: const Icon(Icons.play_arrow), label: const Text('تشغيل')) else OutlinedButton.icon(onPressed: _close, icon: const Icon(Icons.stop), label: const Text('إيقاف'))])),
    Expanded(child: Container(margin: const EdgeInsets.symmetric(horizontal: 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF050A10), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF20354C))), child: SelectionArea(child: SingleChildScrollView(controller: _scroll, child: Align(alignment: Alignment.topLeft, child: Text(_output.isEmpty ? 'TermiAI-Nexus PTY\nاضغط تشغيل لبدء جلسة تفاعلية.\n\nتنبيه: هذه طرفية Android وليست توزيعة Debian/Ubuntu.' : _output.toString(), textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFB7E7C8), fontSize: 12, height: 1.45))))))),
    Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 12), child: Row(children: [Expanded(child: TextField(controller: _input, enabled: _running, textDirection: TextDirection.ltr, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'اكتب أمر shell…', prefixIcon: Icon(Icons.chevron_right), isDense: true))), const SizedBox(width: 8), IconButton.filled(onPressed: _running ? _send : null, icon: const Icon(Icons.send_rounded))])),
  ]);
}
