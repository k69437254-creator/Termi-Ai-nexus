import 'package:material_ui/material_ui.dart';

import '../core/nexus_theme.dart';

class ControlScreen extends StatelessWidget {
  const ControlScreen({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          const NexusPageHeader(
            title: 'مركز التحكم',
            subtitle: 'صورة تشغيلية عن طبقات النظام والقدرات المتاحة فعليًا.',
            padding: EdgeInsets.fromLTRB(2, 12, 2, 18),
          ),
          const _StatusCard(
            icon: Icons.hub_rounded,
            title: 'منسق الفريق',
            detail: 'خطة واضحة ← موافقة المستخدم ← تنفيذ المهام ← مراجعة النتائج.',
            state: 'جاهز',
            color: NexusPalette.success,
          ),
          const _StatusCard(
            icon: Icons.psychology_alt_rounded,
            title: 'الذاكرة المزدوجة',
            detail: 'ذاكرة منفصلة لكل وكيل، وذاكرة فريق، وسياق مستقل لكل مشروع.',
            state: 'محلي',
            color: NexusPalette.primaryLight,
          ),
          const _StatusCard(
            icon: Icons.restore_rounded,
            title: 'الاستعادة التلقائية',
            detail: 'نقطة حفظ قبل المهمة، ومحاولات إصلاح محدودة، ثم استعادة تغييرات المهمة عند الفشل.',
            state: 'مفعّل',
            color: NexusPalette.success,
          ),
          const _StatusCard(
            icon: Icons.terminal_rounded,
            title: 'محرك الطرفية',
            detail: 'Android /system/bin/sh عبر PTY. لا توجد توزيعة Linux كاملة مضمنة.',
            state: 'PTY',
            color: NexusPalette.primaryLight,
          ),
          const _StatusCard(
            icon: Icons.code_rounded,
            title: 'GitHub',
            detail: 'REST API للمستودعات وIssues وPull Requests. العمليات المحلية تحتاج Git executable.',
            state: 'حسب الربط',
            color: NexusPalette.warning,
          ),
          const SizedBox(height: 7),
          const NexusGlassPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [NexusIconTile(Icons.insights_rounded, size: 38), SizedBox(width: 10), Text('طبقة تقنية متقدمة', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14))]),
              SizedBox(height: 11),
              Text('نعرض المعلومات التي توفرها الخدمات الحالية فقط. لا نعرض أرقام CPU أو RAM أو حالة نشاط وهمية؛ قراءة موارد الجهاز تحتاج تكاملًا أصليًا منفصلًا.', style: TextStyle(color: NexusPalette.muted, height: 1.55, fontSize: 11)),
            ]),
          ),
        ],
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.icon, required this.title, required this.detail, required this.state, required this.color});
  final IconData icon;
  final String title;
  final String detail;
  final String state;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: NexusGlassPanel(
          padding: const EdgeInsets.all(14),
          radius: 19,
          blur: 8,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            NexusIconTile(icon, color: color, size: 42),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w900, fontSize: 13)),
              const SizedBox(height: 5),
              Text(detail, style: const TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.5)),
            ])),
            const SizedBox(width: 8),
            NexusStatusPill(state, color: color),
          ]),
        ),
      );
}
