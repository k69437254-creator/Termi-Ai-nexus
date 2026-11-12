import 'package:material_ui/material_ui.dart';
import '../widgets/virtual_office_3d.dart';

class OfficeScreen extends StatelessWidget {
  const OfficeScreen({super.key, required this.onOpenAssistant});
  final VoidCallback onOpenAssistant;
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 10), child: Row(children: [
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('مقر الفريق الافتراضي', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), SizedBox(height: 3), Text('اسحب لتدوير المشهد، وقرّب بإصبعين', style: TextStyle(color: Color(0xFF91A6BE), fontSize: 11))])),
      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: const Color(0xFF143B3A), borderRadius: BorderRadius.circular(24)), child: const Row(children: [Icon(Icons.circle, size: 7, color: Color(0xFF51D0A1)), SizedBox(width: 6), Text('مقر الفريق', style: TextStyle(color: Color(0xFF8DE0C3), fontSize: 11, fontWeight: FontWeight.w700))])),
    ])),
    Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: ClipRRect(borderRadius: BorderRadius.circular(24), child: const VirtualOffice3D()))),
    Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 10), child: Column(children: [
      Row(children: [
        _AgentChip(glyph: '◈', title: 'المدير', subtitle: 'تنسيق'), const SizedBox(width: 6),
        _AgentChip(glyph: '◇', title: 'المعمار', subtitle: 'تصميم'), const SizedBox(width: 6),
        _AgentChip(glyph: '⌘', title: 'المطوّر', subtitle: 'تنفيذ'),
      ]),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: onOpenAssistant, icon: const Icon(Icons.add_rounded), label: const Text('ابدأ مشروعًا من وصفك'))),
    ])),
  ]);
}

class _AgentChip extends StatelessWidget {
  const _AgentChip({required this.glyph, required this.title, required this.subtitle});
  final String glyph, title, subtitle;
  @override
  Widget build(BuildContext context) => Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9), decoration: BoxDecoration(color: const Color(0xFF132238), borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0x223D6387))), child: Row(children: [Text(glyph, style: const TextStyle(fontSize: 17, color: Color(0xFF76CDE0))), const SizedBox(width: 7), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)), Text(subtitle, style: const TextStyle(fontSize: 9, color: Color(0xFF8EA4BC)))]))])));
}
