import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../core/github_service.dart';
import '../core/nexus_feature_suite.dart';
import '../core/nexus_theme.dart';
import '../core/project_coordinator.dart';
import '../models/domain.dart';

class NexusFeatureLabScreen extends StatefulWidget {
  const NexusFeatureLabScreen({super.key, required this.coordinator});
  final ProjectCoordinator coordinator;

  @override
  State<NexusFeatureLabScreen> createState() => _NexusFeatureLabScreenState();
}

class _NexusFeatureLabScreenState extends State<NexusFeatureLabScreen> {
  final GitHubService _github = GitHubService();
  List<ProjectRecord> _projects = [];
  String? _selectedProjectId;
  Map<String, dynamic>? _metrics;
  List<Map<String, dynamic>> _workflowRuns = [];
  String _message = 'اختر مشروعاً لعرض أدوات التحليل والتوثيق والمعاينة.';
  String _report = '';
  bool _busy = false;
  bool _loadingRuns = false;
  bool _metricsBusy = false;
  Timer? _metricsTimer;

  static const _owner = 'k69437254-creator';
  static const _repository = 'Termi-Ai-nexus';
  static const _branch = 'integration/aram-ai-engine';
  static const _workflow = 'aram-engine-integration.yml';

  ProjectRecord? get _selectedProject {
    for (final project in _projects) {
      if (project.id == _selectedProjectId) return project;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _refreshMetrics();
    _metricsTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshMetrics());
    _refreshWorkflowRuns();
  }

  @override
  void dispose() {
    _metricsTimer?.cancel();
    _github.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await widget.coordinator.listProjects();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        if (_selectedProjectId == null || !projects.any((p) => p.id == _selectedProjectId)) {
          _selectedProjectId = projects.isEmpty ? null : projects.first.id;
        }
      });
    } catch (error) {
      _show('تعذر تحميل المشاريع: $error');
    }
  }

  Future<void> _refreshMetrics() async {
    if (_metricsBusy) return;
    _metricsBusy = true;
    try {
      final metrics = await NexusDeviceServices.metrics();
      if (mounted) setState(() => _metrics = metrics);
    } catch (error) {
      if (mounted) setState(() => _message = 'تعذر قراءة مقاييس Android: $error');
    } finally {
      _metricsBusy = false;
    }
  }

  Future<void> _refreshWorkflowRuns() async {
    if (_loadingRuns) return;
    setState(() => _loadingRuns = true);
    try {
      final runs = await _github.workflowRuns(
        owner: _owner,
        repo: _repository,
        branch: _branch,
      );
      if (mounted) setState(() => _workflowRuns = runs.take(8).toList());
    } catch (error) {
      if (mounted) setState(() => _message = 'تعذر جلب حالة GitHub Actions: $error');
    } finally {
      if (mounted) setState(() => _loadingRuns = false);
    }
  }

  Future<void> _dispatchWorkflow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _github.dispatchWorkflow(
        owner: _owner,
        repo: _repository,
        workflow: _workflow,
        ref: _branch,
      );
      _show('أُرسل طلب تشغيل مختبر الاختبارات إلى GitHub Actions.');
      await _refreshWorkflowRuns();
    } catch (error) {
      _show('تعذر تشغيل CI: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runAnalysis() async {
    final project = _selectedProject;
    if (project == null || _busy) return;
    setState(() => _busy = true);
    try {
      final analysis = await NexusProjectAnalyzer.analyze(project.workspacePath);
      final sorted = analysis.languages.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final text = StringBuffer()
        ..writeln('تحليل المشروع: ${project.name}')
        ..writeln('الملفات المفحوصة: ${analysis.fileCount}')
        ..writeln('ملفات المصدر المعروفة: ${analysis.sourceFileCount}')
        ..writeln('اللغة الأبرز: ${analysis.primaryLanguage}')
        ..writeln('\nتوزيع اللغات:');
      for (final item in sorted) {
        text.writeln('- ${item.key}: ${item.value}');
      }
      text.writeln('\nنقاط الدخول:');
      for (final path in analysis.entryPoints) {
        text.writeln('- $path');
      }
      if (analysis.entryPoints.isEmpty) text.writeln('- لم يتم التعرف على نقاط دخول شائعة.');
      if (mounted) setState(() { _report = text.toString(); _message = 'اكتمل فحص بنية المشروع دون تعديل ملفاته.'; });
    } catch (error) {
      _show('فشل تحليل المشروع: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generateDocumentation() async {
    final project = _selectedProject;
    if (project == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await NexusDocumentationGenerator.generate(
        project.workspacePath,
        projectName: project.name,
      );
      if (mounted) {
        setState(() {
          _report = 'تم إنشاء دليل المشروع:\n${file.path}\n\nيتضمن توزيع الملفات ونقاط الدخول والاعتماديات وحدود التحليل.';
          _message = 'اكتمل التوثيق التلقائي.';
        });
      }
    } catch (error) {
      _show('تعذر إنشاء التوثيق: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _auditDependencies() async {
    final project = _selectedProject;
    if (project == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await NexusDependencyManager.writeAuditReport(project.workspacePath);
      final dependencies = await NexusDependencyManager.audit(project.workspacePath);
      if (mounted) {
        setState(() {
          _report = 'عدد الاعتماديات المكتشفة: ${dependencies.length}\n\n'
              '${dependencies.map((item) => '${item.name} — ${item.version} (${item.source})').join('\n')}\n\n'
              'حُفظ التقرير في:\n${file.path}\n\nلم يتم تحديث أي إصدار أو تنزيل حزم.';
          _message = 'اكتمل تدقيق الاعتماديات.';
        });
      }
    } catch (error) {
      _show('فشل تدقيق الاعتماديات: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewHtml() async {
    final project = _selectedProject;
    if (project == null || _busy) return;
    final controller = TextEditingController(text: 'index.html');
    final relative = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('معاينة تطبيق ويب'),
        content: TextField(
          controller: controller,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(labelText: 'المسار النسبي لملف HTML', hintText: 'web/index.html'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('فتح المعاينة')),
        ],
      ),
    );
    controller.dispose();
    if (relative == null || relative.isEmpty) return;
    final root = Directory(project.workspacePath).absolute;
    final target = File('${root.path}${Platform.pathSeparator}$relative');
    try {
      final canonicalRoot = await root.resolveSymbolicLinks();
      final canonicalTarget = await target.resolveSymbolicLinks();
      if (!canonicalTarget.startsWith('$canonicalRoot${Platform.pathSeparator}') ||
          !const {'html', 'htm'}.contains(target.uri.pathSegments.last.split('.').last.toLowerCase())) {
        throw const FormatException('المعاينة تقبل ملف HTML داخل مساحة المشروع فقط.');
      }
      await NexusDeviceServices.openHtmlPreview(target.absolute.path);
    } catch (error) {
      _show('تعذر فتح المعاينة: $error');
    }
  }

  void _show(String value) {
    if (!mounted) return;
    setState(() => _message = value);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value), behavior: SnackBarBehavior.floating));
  }

  String _formatBytes(dynamic raw) {
    final bytes = (raw as num?)?.toDouble();
    if (bytes == null) return '—';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const NexusPageHeader(
            title: 'مختبر Nexus',
            subtitle: 'الاختبارات، فحص المشاريع، المعاينة، الاعتماديات ومراقبة موارد Android.',
            padding: EdgeInsets.fromLTRB(0, 12, 0, 17),
          ),
          _section(
            title: 'مراقبة الأداء',
            icon: Icons.memory_rounded,
            trailing: IconButton(onPressed: _refreshMetrics, icon: const Icon(Icons.refresh_rounded)),
            child: _metrics == null
                ? const Text('لم تصل بيانات القياس بعد.', style: TextStyle(color: NexusPalette.muted, fontSize: 11))
                : Wrap(spacing: 8, runSpacing: 8, children: [
                    _metric('RAM الجهاز', _formatBytes(_metrics!['deviceTotalRamBytes'])),
                    _metric('RAM المتاحة', _formatBytes(_metrics!['deviceAvailableRamBytes'])),
                    _metric('ذاكرة التطبيق PSS', '${_metrics!['appPssKb'] ?? '—'} KB'),
                    _metric('Heap المستخدم', _formatBytes(_metrics!['appJavaHeapUsedBytes'])),
                    _metric('حالة الذاكرة', _metrics!['deviceLowMemory'] == true ? 'ضغط ذاكرة' : 'طبيعية'),
                  ]),
          ),
          _section(
            title: 'أدوات المشروع',
            icon: Icons.folder_special_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<String>(
                value: _selectedProjectId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'مساحة العمل'),
                items: _projects.map((project) => DropdownMenuItem(value: project.id, child: Text(project.name, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: _busy ? null : (value) => setState(() { _selectedProjectId = value; _report = ''; }),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _action('تحليل المشروع', Icons.account_tree_outlined, _runAnalysis),
                _action('توليد التوثيق', Icons.description_outlined, _generateDocumentation),
                _action('تدقيق الاعتماديات', Icons.inventory_2_outlined, _auditDependencies),
                _action('معاينة HTML', Icons.preview_outlined, _previewHtml),
              ]),
              if (_report.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: NexusPalette.background.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(14)),
                  child: SelectableText(_report, style: const TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.5)),
                ),
              ],
            ]),
          ),
          _section(
            title: 'مختبر الاختبارات وGitHub Actions',
            icon: Icons.science_outlined,
            trailing: IconButton(onPressed: _loadingRuns ? null : _refreshWorkflowRuns, icon: const Icon(Icons.refresh_rounded)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('المستودع: $_owner/$_repository\nالفرع: $_branch', style: const TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.5)),
              const SizedBox(height: 9),
              FilledButton.icon(
                onPressed: _busy ? null : _dispatchWorkflow,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('تشغيل التحليل والاختبارات وبناء APK على GitHub'),
              ),
              const SizedBox(height: 10),
              if (_loadingRuns) const LinearProgressIndicator(minHeight: 2),
              if (_workflowRuns.isEmpty && !_loadingRuns)
                const Text('لا توجد نتائج تشغيل متاحة أو لم يتم ربط GitHub.', style: TextStyle(color: NexusPalette.muted, fontSize: 10)),
              ..._workflowRuns.map((run) {
                final conclusion = run['conclusion']?.toString() ?? run['status']?.toString() ?? 'unknown';
                final success = conclusion == 'success';
                final failed = conclusion == 'failure';
                final sha = run['head_sha']?.toString() ?? '';
                final shortSha = sha.substring(0, sha.length > 7 ? 7 : sha.length);
                final color = success ? NexusPalette.success : failed ? NexusPalette.danger : NexusPalette.warning;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(success ? Icons.check_circle_outline : failed ? Icons.error_outline : Icons.pending_outlined, color: color),
                  title: Text(run['display_title']?.toString() ?? 'تشغيل CI', style: const TextStyle(fontSize: 11, color: NexusPalette.text)),
                  subtitle: Text('${run['event'] ?? '—'} • ${shortSha.isEmpty ? '—' : shortSha}', style: const TextStyle(fontSize: 9, color: NexusPalette.muted)),
                  trailing: Text(conclusion, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800)),
                  onTap: () {
                    final url = run['html_url']?.toString();
                    if (url != null && url.startsWith('https://github.com/')) {
                      // The CI run URL is also printed in the report for manual review.
                      setState(() => _report = 'GitHub Actions:\n$url');
                    }
                  },
                );
              }),
            ]),
          ),
          _section(
            title: 'خريطة قدرات المشروع الـ15',
            icon: Icons.checklist_rounded,
            child: Column(children: const [
              _CapabilityLine('1. فريق الوكلاء المتخصصين', 'خمسة أدوار مستقلة ومحادثة وذاكرة لكل وكيل.'),
              _CapabilityLine('2. فهم المشروع', 'سياق ملفات محدود وآمن مع فهرسة بنية المشروع.'),
              _CapabilityLine('3. الإصلاح الذاتي', 'محاولات إصلاح محدودة مع تحقق وتراجع.'),
              _CapabilityLine('4. نقاط الاستعادة', 'Checkpoint قبل المهمة واستعادة انتقائية.'),
              _CapabilityLine('5. الحارس الأمني', 'حماية مسارات حساسة وروابط رمزية.'),
              _CapabilityLine('6. مختبر الاختبارات', 'تشغيل CI عن بُعد وعرض نتيجة GitHub Actions.'),
              _CapabilityLine('7. معاينة التطبيقات', 'معاينة محلية لتطبيقات الويب HTML؛ تطبيقات Android تحتاج جهاز بناء/تشغيل.'),
              _CapabilityLine('8. إدارة GitHub', 'مستودعات وIssues وPull Requests وتشغيل CI.'),
              _CapabilityLine('9. مدير النماذج', 'تنزيل واستيراد وتشغيل نموذج Aram AI المحلي.'),
              _CapabilityLine('10. مشاريع متعددة', 'سجل مستقل وقائمة تنفيذ متسلسلة للمشاريع.'),
              _CapabilityLine('11. فهم الصور', 'إرسال الصورة إلى بوابة خارجية تدعم Vision؛ المحرك المحلي الحالي غير متعدد الوسائط.'),
              _CapabilityLine('12. الصوت إلى مهام', 'تحويل الكلام العربي إلى نص يراجعه المستخدم قبل الإرسال.'),
              _CapabilityLine('13. التوثيق التلقائي', 'إنشاء دليل مشروع وفهرس نقاط الدخول.'),
              _CapabilityLine('14. مراقبة الأداء', 'قراءة فعلية لذاكرة الجهاز وذاكرة التطبيق.'),
              _CapabilityLine('15. مدير الاعتماديات', 'فهرسة الاعتماديات وتقرير تدقيق؛ لا يحدّث الإصدارات تلقائياً.'),
            ]),
          ),
          const SizedBox(height: 6),
          Text(_message, style: const TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.4)),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(minHeight: 2)),
        ],
      );

  Widget _section({required String title, required IconData icon, Widget? trailing, required Widget child}) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: NexusGlassPanel(
          padding: const EdgeInsets.all(14),
          radius: 19,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [NexusIconTile(icon, size: 36), const SizedBox(width: 9), Expanded(child: Text(title, style: const TextStyle(color: NexusPalette.text, fontSize: 12, fontWeight: FontWeight.w900))), if (trailing != null) trailing]),
            const SizedBox(height: 11),
            child,
          ]),
        ),
      );

  Widget _metric(String label, String value) => Container(
        constraints: const BoxConstraints(minWidth: 112),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(color: NexusPalette.background.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: NexusPalette.muted, fontSize: 9)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: NexusPalette.primaryLight, fontSize: 12, fontWeight: FontWeight.w900)),
        ]),
      );

  Widget _action(String label, IconData icon, VoidCallback callback) => OutlinedButton.icon(
        onPressed: _busy || _selectedProject == null ? null : callback,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 10)),
      );
}

class _CapabilityLine extends StatelessWidget {
  const _CapabilityLine(this.title, this.description);
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.arrow_forward_ios_rounded, color: NexusPalette.muted, size: 11),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: NexusPalette.text, fontSize: 10, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(description, style: const TextStyle(color: NexusPalette.muted, fontSize: 9, height: 1.4)),
          ])),
        ]),
      );
}
