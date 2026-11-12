import 'package:flutter/material.dart';

class ControlScreen extends StatelessWidget {
  const ControlScreen({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('مركز التحكم', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
    const SizedBox(height: 4), const Text('نظرة تشغيلية مختصرة، مع الإعدادات التقنية في صفحة منفصلة.', style: TextStyle(color: Color(0xFF91A6BE), fontSize: 12)),
    const SizedBox(height: 14),
    const _StatusCard(icon: Icons.hub, title: 'منسق الفريق', detail: 'خطة → موافقة المستخدم → تنفيذ مهام الوكلاء → تحقق من الملفات.', state: 'جاهز'),
    const _StatusCard(icon: Icons.memory, title: 'الذاكرة المزدوجة', detail: 'ذاكرة منفصلة لكل وكيل + ذاكرة فريق + سياق مستقل لكل مشروع.', state: 'محلي'),
    const _StatusCard(icon: Icons.restore, title: 'الاستعادة التلقائية', detail: 'نقطة حفظ قبل المهمة، حتى 3 محاولات، ثم استرجاع تغييرات المهمة عند الفشل.', state: 'مفعّل'),
    const _StatusCard(icon: Icons.terminal, title: 'محرك الطرفية', detail: 'Android /system/bin/sh عبر PTY. توزيعة Linux كاملة غير مضمّنة.', state: 'PTY'),
    const _StatusCard(icon: Icons.code, title: 'GitHub', detail: 'REST API للمستودعات وIssues وPull Requests. عمليات Git المحلية تحتاج git binary.', state: 'يتطلب ربطاً'),
    const SizedBox(height: 12),
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('طبقة تقنية متقدمة', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 8), const Text('هذه النسخة تعرض إعدادات التشغيل المتاحة داخل التطبيق. لا تعرض أرقام CPU أو RAM أو حالة خدمات وهمية؛ يمكن إضافة قراءة موارد الجهاز وخدمات النظام لاحقاً عبر طبقة Android مخصصة.', style: TextStyle(color: Color(0xFF9CB0C7), height: 1.5, fontSize: 12))]))),
  ]);
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.icon, required this.title, required this.detail, required this.state});
  final IconData icon;
  final String title, detail, state;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFF1A344D), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: const Color(0xFF7DCDDF)),), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(detail, style: const TextStyle(color: Color(0xFF96ABC2), fontSize: 11, height: 1.4))])), const SizedBox(width: 6), Text(state, style: const TextStyle(color: Color(0xFF78CADD), fontSize: 10, fontWeight: FontWeight.w700))])));
}
