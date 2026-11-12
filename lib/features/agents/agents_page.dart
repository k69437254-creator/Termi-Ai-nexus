// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../shared/ui_components.dart';

class AgentsPage extends StatelessWidget {
  const AgentsPage({super.key});

  static const List<_AgentDefinition> _agents = <_AgentDefinition>[
    _AgentDefinition('المدير الرئيسي', 'يفهم الطلب ويخطط ويوزع المهام', Icons.account_tree_outlined, Color(0xFF66B7FF)),
    _AgentDefinition('المعماري', 'يصمم بنية المشروع وقراراته التقنية', Icons.architecture_rounded, Color(0xFF9D91FF)),
    _AgentDefinition('المبرمج', 'ينفذ التغييرات البرمجية داخل مساحة العمل', Icons.code_rounded, Color(0xFF58D6B6)),
    _AgentDefinition('الاختبارات', 'يشغّل الاختبارات ويتحقق من النتائج', Icons.fact_check_outlined, Color(0xFFFFC36B)),
    _AgentDefinition('الأمن', 'يراجع المخاطر والأسرار والصلاحيات', Icons.shield_outlined, Color(0xFFFF8195)),
    _AgentDefinition('GitHub', 'يدير الفروع والالتزامات وطلبات الدمج', Icons.device_hub_outlined, Color(0xFFB5C8E7)),
  ];

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 30),
          sliver: SliverList(
            delegate: SliverChildListDelegate(<Widget>[
              const PageHeading(title: 'فريق الوكلاء', subtitle: 'الأدوار الهندسية المعتمدة ضمن تصميم TermiAI-Nexus.'),
              const SizedBox(height: 18),
              const InfoPanel(
                icon: Icons.power_off_rounded,
                title: 'محرك الوكلاء غير متصل بعد',
                description: 'هذه بطاقات تعريفية للأدوار فقط. لا توجد الآن عمليات مستقلة أو محادثات أو استدعاءات نموذج تعمل في الخلفية.',
                color: Color(0xFFFFC36B),
              ),
              const SizedBox(height: 18),
              ..._agents.map(( _AgentDefinition agent) => Padding(
                padding: const EdgeInsets.only(bottom: 11),
                child: _AgentCard(agent: agent),
              )),
            ]),
          ),
        ),
      ],
    );
  }
}

class _AgentDefinition {
  const _AgentDefinition(this.name, this.description, this.icon, this.color);
  final String name;
  final String description;
  final IconData icon;
  final Color color;
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.agent});
  final _AgentDefinition agent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(17), border: Border.all(color: AppTheme.border)),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(shape: BoxShape.circle, color: agent.color.withValues(alpha: 0.13), border: Border.all(color: agent.color.withValues(alpha: 0.5))),
            child: Icon(agent.icon, color: agent.color),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(agent.name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(agent.description, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.4)),
              ],
            ),
          ),
          const StatusPill(label: 'غير متصل'),
        ],
      ),
    );
  }
}
