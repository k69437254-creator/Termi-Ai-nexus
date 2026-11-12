import 'package:flutter/material.dart';
import '../core/project_coordinator.dart';
import '../models/domain.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, required this.coordinator});
  final ProjectCoordinator coordinator;
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final TextEditingController _request = TextEditingController();
  ProjectRecord? _project;
  bool _planning = false;
  bool _executing = false;
  String _notice = '';

  @override
  void dispose() { _request.dispose(); super.dispose(); }

  Future<void> _prepare() async {
    if (_request.text.trim().isEmpty || _planning || _executing) return;
    setState(() { _planning = true; _notice = ''; _project = null; });
    try {
      final project = await widget.coordinator.prepare(_request.text.trim());
      if (!mounted) return;
      setState(() { _project = project; _notice = 'تم إعداد الخطة. راجع المهام ثم وافق لبدء التنفيذ.'; });
    } catch (e) {
      if (mounted) setState(() => _notice = e.toString());
    } finally { if (mounted) setState(() => _planning = false); }
  }

  Future<void> _execute() async {
    final project = _project;
    if (project == null || _executing) return;
    setState(() { _executing = true; _notice = 'بدأ الفريق تنفيذ المهام بالترتيب المعتمد…'; });
    try {
      await widget.coordinator.execute(project, onTaskChanged: (_) { if (mounted) setState(() {}); });
      if (mounted) setState(() => _notice = 'انتهى مسار التنفيذ. راجع نتيجة كل مهمة وحالة الملفات في مساحة المشروع.');
    } catch (e) {
      if (mounted) setState(() => _notice = 'توقف التنفيذ: $e');
    } finally { if (mounted) setState(() => _executing = false); }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF173956), Color(0xFF172742)]), borderRadius: BorderRadius.circular(22)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.auto_awesome, color: Color(0xFF75D6E7)), SizedBox(width: 8), Text('NEXUS PROJECT DIRECTOR', style: TextStyle(fontSize: 10, letterSpacing: 1.4, color: Color(0xFF9BD8E7), fontWeight: FontWeight.w800))]),
      SizedBox(height: 12), Text('صف ما تريد بناءه.\nالفريق يخطط أولاً، ثم ينتظر موافقتك.', style: TextStyle(fontSize: 20, height: 1.4, fontWeight: FontWeight.w800)),
      SizedBox(height: 8), Text('لن يبدأ تنفيذ الخطة قبل اعتمادك لها.', style: TextStyle(color: Color(0xFFB0C2D5), fontSize: 12)),
    ])),
    const SizedBox(height: 16),
    TextField(controller: _request, minLines: 4, maxLines: 8, decoration: const InputDecoration(hintText: 'مثال: أنشئ تطبيق إدارة مهام مع تسجيل دخول وقاعدة بيانات واختبارات…', alignLabelWithHint: true, prefixIcon: Icon(Icons.edit_note))),
    const SizedBox(height: 10),
    FilledButton.icon(onPressed: _planning || _executing ? null : _prepare, icon: _planning ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.account_tree_outlined), label: Text(_planning ? 'يحلل الطلب ويضع الخطة…' : 'حلّل الطلب وأنشئ خطة')),
    if (_notice.isNotEmpty) ...[
      const SizedBox(height: 12),
      Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF17283C), borderRadius: BorderRadius.circular(12)), child: Text(_notice, style: const TextStyle(fontSize: 12, color: Color(0xFFC4D6E9)))),
    ],
    if (_project != null) ...[
      const SizedBox(height: 18),
      Row(children: [const Expanded(child: Text('خطة التنفيذ المقترحة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))), Text('${_project!.tasks.length} مهام', style: const TextStyle(color: Color(0xFF7FCBDD), fontSize: 11))]),
      const SizedBox(height: 8),
      ..._project!.tasks.asMap().entries.map((entry) => _TaskTile(index: entry.key + 1, task: entry.value)),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: _executing ? null : _execute, icon: _executing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded), label: Text(_executing ? 'الفريق يعمل…' : 'أوافق على الخطة — ابدأ التنفيذ')),
      TextButton(onPressed: _executing ? null : () => setState(() { _project = null; _notice = 'تم إلغاء الخطة الحالية. لم يبدأ تنفيذها.'; }), child: const Text('إلغاء الخطة')),
    ],
    const SizedBox(height: 20),
    const Text('ملاحظة تشغيلية: الوكلاء يعيدون المحاولة عند فشل معالجة المهمة حتى 3 مرات. التحقق الحالي يتأكد من سلامة كتابة الملفات فقط؛ لا يدّعي نجاح بناء Flutter أو الاختبارات ما لم تُشغّل فعلياً.', style: TextStyle(fontSize: 11, height: 1.5, color: Color(0xFF8FA5BE))),
  ]);
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.index, required this.task});
  final int index;
  final PlanTask task;
  @override
  Widget build(BuildContext context) {
    final color = switch (task.status) { TaskStatus.completed => const Color(0xFF58CFA1), TaskStatus.running => const Color(0xFF67C8E0), TaskStatus.failed || TaskStatus.rolledBack => const Color(0xFFE58C83), _ => const Color(0xFF8CA4BF) };
    return Card(child: Padding(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(width: 25, height: 25, alignment: Alignment.center, decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)), child: Text('$index', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11))), const SizedBox(width: 9), Expanded(child: Text(task.title, style: const TextStyle(fontWeight: FontWeight.w800))), Text(task.status.name, style: TextStyle(color: color, fontSize: 10))]),
      const SizedBox(height: 7), Text(task.description, style: const TextStyle(fontSize: 12, color: Color(0xFF9CB0C7), height: 1.4)),
      const SizedBox(height: 7), Row(children: [Text('الوكيل: ${task.agentId}', style: const TextStyle(fontSize: 10, color: Color(0xFF75C9DC))), const SizedBox(width: 12), Text('المخاطر: ${task.risk}', style: const TextStyle(fontSize: 10, color: Color(0xFF9CB0C7)))]),
      if (task.result.isNotEmpty) ...[const Divider(height: 18), Text(task.result, style: const TextStyle(fontSize: 11, height: 1.4))],
    ])));
  }
}
