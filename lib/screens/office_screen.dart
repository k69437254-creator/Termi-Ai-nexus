import 'package:material_ui/material_ui.dart';

import '../core/nexus_theme.dart';
import '../widgets/virtual_office_3d.dart';

class OfficeScreen extends StatelessWidget {
  const OfficeScreen({super.key, required this.onOpenAssistant});
  final VoidCallback onOpenAssistant;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const NexusPageHeader(
            title: 'مقر الفريق الافتراضي',
            subtitle: 'استكشف المقر ثلاثي الأبعاد وتجوّل بين محطات الوكلاء.',
            trailing: NexusStatusPill('العالم الافتراضي', icon: Icons.view_in_ar_rounded),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: NexusGlassPanel(
                padding: EdgeInsets.zero,
                radius: 25,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: const VirtualOffice3D(),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
            child: Column(
              children: [
                const Row(children: [
                  _AgentChip(glyph: '◈', title: 'المدير', subtitle: 'تنسيق'),
                  SizedBox(width: 7),
                  _AgentChip(glyph: '◇', title: 'المعمار', subtitle: 'تصميم'),
                  SizedBox(width: 7),
                  _AgentChip(glyph: '⌘', title: 'المطوّر', subtitle: 'تنفيذ'),
                ]),
                const SizedBox(height: 11),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onOpenAssistant,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('ابدأ مشروعًا من وصفك'),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _AgentChip extends StatelessWidget {
  const _AgentChip({required this.glyph, required this.title, required this.subtitle});
  final String glyph;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Expanded(
        child: NexusGlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
          radius: 15,
          blur: 8,
          child: Row(children: [
            Text(glyph, style: const TextStyle(fontSize: 19, color: NexusPalette.primaryLight)),
            const SizedBox(width: 7),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
              Text(subtitle, style: const TextStyle(fontSize: 9, color: NexusPalette.muted)),
            ])),
          ]),
        ),
      );
}
