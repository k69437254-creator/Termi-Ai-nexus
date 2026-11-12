import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/models/project_draft.dart';
import '../../core/services/project_store.dart';
import '../../shared/ui_components.dart';

class HomePage extends StatefulWidget {
  const HomePage({required this.projectStore, required this.onOpenProjects, super.key});

  final ProjectStore projectStore;
  final VoidCallback onOpenProjects;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _requestController = TextEditingController();

  @override
  void dispose() {
    _requestController.dispose();
    super.dispose();
  }

  void _saveRequest() {
    final String request = _requestController.text.trim();
    if (request.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب وصف المشروع أولًا.')),
      );
      return;
    }

    widget.projectStore.addDraft(request);
    _requestController.clear();
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('حُفظ الطلب كمسودة محلية. التنفيذ الآلي غير مفعّل بعد.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate(<Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(colors: <Color>[Color(0xFF39A8FF), Color(0xFF174B88)]),
                    ),
                    child: const Icon(Icons.auto_awesome, color: Colors.white),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('TermiAI-Nexus', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w900)),
                        SizedBox(height: 3),
                        Text('بيئة بناء المشاريع الذكية', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                  const StatusPill(label: 'الإصدار التأسيسي', color: Color(0xFF64B5FF)),
                ],
              ),
              const SizedBox(height: 28),
              const Text('مرحبًا بك في مساحة البناء', style: TextStyle(color: AppTheme.textPrimary, fontSize: 25, fontWeight: FontWeight.w900, height: 1.3)),
              const SizedBox(height: 8),
              const Text('صف المشروع الذي تريد إنشاءه، وستكون هذه نقطة البداية لتخطيط العمل وتنفيذه.', style: TextStyle(color: AppTheme.textMuted, height: 1.55)),
              const SizedBox(height: 22),
              _buildRequestComposer(context),
              const SizedBox(height: 26),
              const SectionTitle('مساحة الفريق'),
              const SizedBox(height: 12),
              const _TeamRoomPreview(),
              const SizedBox(height: 26),
              SectionTitle(
                'المشاريع الأخيرة',
                action: TextButton(onPressed: widget.onOpenProjects, child: const Text('عرض الكل')),
              ),
              const SizedBox(height: 12),
              AnimatedBuilder(
                animation: widget.projectStore,
                builder: (context, _) {
                  final List<ProjectDraft> projects = widget.projectStore.projects.take(3).toList();
                  if (projects.isEmpty) {
                    return const _EmptyProjectsPreview();
                  }
                  return Column(
                    children: projects.map((ProjectDraft project) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ProjectPreviewCard(project: project),
                    )).toList(),
                  );
                },
              ),
              const SizedBox(height: 20),
              const Text('هذه نسخة تأسيسية: حفظ المسودات محلي داخل الجلسة فقط، ولم يُربط محرك التنفيذ بعد.', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.5)),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestComposer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: <Color>[Color(0xFF13243A), Color(0xFF0D1727)]),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF2C4C70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.edit_note_rounded, color: Color(0xFF68B9FF)),
              SizedBox(width: 8),
              Text('ما الذي تريد بناءه؟', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 13),
          TextField(
            controller: _requestController,
            minLines: 4,
            maxLines: 7,
            textAlign: TextAlign.right,
            textDirection: TextDirection.rtl,
            style: const TextStyle(color: AppTheme.textPrimary, height: 1.5),
            decoration: const InputDecoration(
              hintText: 'مثال: أنشئ تطبيق إدارة مهام مع تسجيل دخول وقاعدة بيانات...',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 13),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saveRequest,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('حفظ طلب المشروع'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamRoomPreview extends StatelessWidget {
  const _TeamRoomPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[Color(0xFF101F34), Color(0xFF090F1C)]),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(left: -35, top: -55, child: _GlowOrb(size: 150, color: const Color(0xFF147DDE).withValues(alpha: 0.16))),
          Positioned(right: 12, bottom: -72, child: _GlowOrb(size: 175, color: const Color(0xFF2B6BB1).withValues(alpha: 0.15))),
          Positioned.fill(
            child: CustomPaint(painter: _GridPainter()),
          ),
          Align(
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: const <Widget>[
                _AgentLight(color: Color(0xFF5CC4FF), label: 'المعمار'),
                _AgentLight(color: Color(0xFF8C87FF), label: 'البرمجة'),
                _AgentLight(color: Color(0xFF5FE0C0), label: 'الاختبار'),
              ],
            ),
          ),
          const Positioned(
            bottom: 10,
            left: 12,
            right: 12,
            child: Text('معاينة بصرية أولية — الوكلاء غير متصلين بمحرك تنفيذ بعد', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: <BoxShadow>[BoxShadow(color: color, blurRadius: 42, spreadRadius: 18)]),
  );
}

class _AgentLight extends StatelessWidget {
  const _AgentLight({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: <Color>[color.withValues(alpha: 0.95), color.withValues(alpha: 0.25), color.withValues(alpha: 0.03)]),
            boxShadow: <BoxShadow>[BoxShadow(color: color.withValues(alpha: 0.22), blurRadius: 22, spreadRadius: 4)],
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Icon(Icons.blur_on_rounded, color: Colors.white.withValues(alpha: 0.9), size: 26),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: AppTheme.textPrimary.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = const Color(0xFF5D8DBD).withValues(alpha: 0.10)..strokeWidth = 0.7;
    const double step = 24;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EmptyProjectsPreview extends StatelessWidget {
  const _EmptyProjectsPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
      child: const Row(
        children: <Widget>[
          Icon(Icons.folder_open_outlined, color: AppTheme.textMuted),
          SizedBox(width: 12),
          Expanded(child: Text('لا توجد مشاريع بعد. اكتب أول طلب في الأعلى.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12))),
        ],
      ),
    );
  }
}

class _ProjectPreviewCard extends StatelessWidget {
  const _ProjectPreviewCard({required this.project});
  final ProjectDraft project;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
      child: Row(
        children: <Widget>[
          const Icon(Icons.code_rounded, color: AppTheme.accent),
          const SizedBox(width: 12),
          Expanded(child: Text(project.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700))),
          const StatusPill(label: 'مسودة'),
        ],
      ),
    );
  }
}
