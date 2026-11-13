import 'package:material_ui/material_ui.dart';

import '../core/nexus_theme.dart';
import '../models/domain.dart';
import '../widgets/virtual_office_3d.dart';

class OfficeScreen extends StatefulWidget {
  const OfficeScreen({super.key, required this.onOpenAssistant});
  final VoidCallback onOpenAssistant;

  @override
  State<OfficeScreen> createState() => _OfficeScreenState();
}

class _OfficeScreenState extends State<OfficeScreen> {
  String _selectedAgent = 'manager';
  bool _autoOrbit = true;
  int _cameraResetKey = 0;

  AgentProfile get _agent => AgentProfile.defaults.firstWhere(
        (agent) => agent.id == _selectedAgent,
        orElse: () => AgentProfile.defaults.first,
      );

  Color _agentColor(String id) => switch (id) {
        'manager' => NexusPalette.primary,
        'architect' => NexusPalette.purple,
        'developer' => NexusPalette.emerald,
        'qa' => NexusPalette.amber,
        'security' => NexusPalette.crimson,
        _ => NexusPalette.primary,
      };

  void _selectAgent(String id) {
    if (!AgentProfile.defaults.any((agent) => agent.id == id)) return;
    setState(() => _selectedAgent = id);
  }

  @override
  Widget build(BuildContext context) {
    final worldHeight = (MediaQuery.sizeOf(context).height * 0.43).clamp(285.0, 370.0).toDouble();
    final selectedColor = _agentColor(_selectedAgent);

    return ListView(
      padding: const EdgeInsets.fromLTRB(13, 2, 13, 18),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(3, 2, 3, 10),
          child: Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('NEURAL COMMAND CENTER', style: TextStyle(color: NexusPalette.primary, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              SizedBox(height: 4),
              Text('عالم الوكلاء ثلاثي الأبعاد', style: TextStyle(color: NexusPalette.text, fontSize: 15, fontWeight: FontWeight.w900)),
            ])),
            _WorldControl(
              icon: _autoOrbit ? Icons.pause_rounded : Icons.play_arrow_rounded,
              label: _autoOrbit ? 'تدوير' : 'ثابت',
              onTap: () => setState(() => _autoOrbit = !_autoOrbit),
            ),
            const SizedBox(width: 6),
            _WorldControl(icon: Icons.center_focus_strong_rounded, label: 'إعادة', onTap: () => setState(() => _cameraResetKey++)),
          ]),
        ),
        SizedBox(
          height: worldHeight,
          child: NexusGlassPanel(
            padding: EdgeInsets.zero,
            radius: 24,
            blur: 18,
            borderColor: const Color(0x3300F0FF),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(23),
              child: Stack(fit: StackFit.expand, children: [
                VirtualOffice3D(
                  key: ValueKey(_cameraResetKey),
                  onAgentTap: _selectAgent,
                  selectedAgentId: _selectedAgent,
                  autoOrbit: _autoOrbit,
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: _HudTag(label: 'AETHERIUM / 3D', color: NexusPalette.primary),
                ),
                const Positioned(
                  bottom: 10,
                  right: 12,
                  child: Text('اسحب لتحريك الكاميرا • قرّب بإصبعين • المس وكيلًا لتحديده', style: TextStyle(color: Color(0xFFB7C6D8), fontSize: 8, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 13),
        const NexusSectionHeader('شبكة الوكلاء', subtitle: 'كيانات رقمية متخصصة داخل المقر الافتراضي.'),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: AgentProfile.defaults.map((agent) {
            final active = agent.id == _selectedAgent;
            final color = _agentColor(agent.id);
            return _AgentSelector(
              agent: agent,
              color: color,
              selected: active,
              onTap: () => _selectAgent(agent.id),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        NexusGlassPanel(
          padding: const EdgeInsets.all(13),
          radius: 19,
          borderColor: selectedColor.withValues(alpha: 0.32),
          child: Row(children: [
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selectedColor.withValues(alpha: 0.12),
                border: Border.all(color: selectedColor.withValues(alpha: 0.46)),
                boxShadow: [BoxShadow(color: selectedColor.withValues(alpha: 0.15), blurRadius: 17)],
              ),
              child: Center(child: Text(_agent.glyph, style: TextStyle(color: selectedColor, fontSize: 21, fontWeight: FontWeight.w900))),
            ),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_agent.name, style: TextStyle(color: selectedColor, fontSize: 12, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(_agent.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NexusPalette.muted, fontSize: 9, height: 1.45)),
            ])),
            const SizedBox(width: 7),
            const NexusStatusPill('AGENT NODE', icon: Icons.hub_outlined),
          ]),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: widget.onOpenAssistant,
            icon: const Icon(Icons.arrow_upward_rounded),
            label: const Text('توجيه طلب جديد إلى المدير الرئيسي'),
          ),
        ),
      ],
    );
  }
}

class _WorldControl extends StatelessWidget {
  const _WorldControl({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xB30A0F1C),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: NexusPalette.border)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: NexusPalette.primary, size: 14), const SizedBox(width: 4), Text(label, style: const TextStyle(color: NexusPalette.text, fontSize: 9, fontWeight: FontWeight.w800))],),
          ),
        ),
      );
}

class _HudTag extends StatelessWidget {
  const _HudTag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(color: const Color(0xCC050811), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.4))),
        child: Text(label, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
      );
}

class _AgentSelector extends StatelessWidget {
  const _AgentSelector({required this.agent, required this.color, required this.selected, required this.onTap});
  final AgentProfile agent;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: selected ? color.withValues(alpha: 0.9) : NexusPalette.border),
              boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 15)] : const [],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 7)])),
              const SizedBox(width: 7),
              Text(agent.name, style: TextStyle(color: selected ? NexusPalette.text : NexusPalette.muted, fontSize: 9, fontWeight: selected ? FontWeight.w900 : FontWeight.w700)),
            ]),
          ),
        ),
      );
}
