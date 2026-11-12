import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../shared/ui_components.dart';

class MonitorPage extends StatelessWidget {
  const MonitorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 30),
          sliver: SliverList(
            delegate: SliverChildListDelegate(<Widget>[
              const PageHeading(title: 'مراقبة العمليات', subtitle: 'حالة النظام وعمليات البناء والتنفيذ.'),
              const SizedBox(height: 20),
              const InfoPanel(
                icon: Icons.hourglass_empty_rounded,
                title: 'لا توجد عمليات تشغيل حاليًا',
                description: 'لم يُربط بعد منسّق المهام أو طرفية Debian/PTY. ستظهر هنا العمليات الحقيقية وسجلها بعد تنفيذ هذه الخدمات.',
                color: Color(0xFFFFC36B),
              ),
              const SizedBox(height: 18),
              const _SystemStatusRow(label: 'واجهة Flutter', value: 'تعمل', color: Color(0xFF65D8B0)),
              const _SystemStatusRow(label: 'مشغل الوكلاء', value: 'غير منفذ', color: Color(0xFFFFC36B)),
              const _SystemStatusRow(label: 'Debian / Bash / PTY', value: 'غير منفذ', color: Color(0xFFFFC36B)),
              const _SystemStatusRow(label: 'تكامل Aram AI', value: 'غير مربوط', color: Color(0xFFFFC36B)),
              const _SystemStatusRow(label: 'GitHub العمليات المحلية', value: 'غير منفذ', color: Color(0xFFFFC36B)),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF0E1725), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
                child: const Text('مهم: هذه الشاشة لا تعرض تقدمًا وهميًا. لن تظهر حالة «قيد التنفيذ» إلا بعد وجود محرك فعلي يرسل أحداثًا موثقة.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.6)),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _SystemStatusRow extends StatelessWidget {
  const _SystemStatusRow({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600))),
          StatusPill(label: value, color: color),
        ],
      ),
    );
  }
}
