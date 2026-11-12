import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/models/project_draft.dart';
import '../../core/services/project_store.dart';
import '../../shared/ui_components.dart';

class ProjectsPage extends StatelessWidget {
  const ProjectsPage({required this.projectStore, super.key});

  final ProjectStore projectStore;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: projectStore,
      builder: (context, _) {
        final List<ProjectDraft> projects = projectStore.projects;
        return CustomScrollView(
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 30),
              sliver: SliverList(
                delegate: SliverChildListDelegate(<Widget>[
                  const PageHeading(title: 'المشاريع', subtitle: 'مساحة منفصلة لطلبات المشاريع التي أضفتها إلى التطبيق.'),
                  const SizedBox(height: 22),
                  Row(
                    children: <Widget>[
                      _MetricCard(value: '${projects.length}', label: 'مسودات محلية', icon: Icons.folder_copy_outlined),
                      const SizedBox(width: 10),
                      const _MetricCard(value: '0', label: 'قيد التنفيذ', icon: Icons.play_circle_outline),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (projects.isEmpty)
                    const InfoPanel(
                      icon: Icons.inbox_outlined,
                      title: 'لا توجد مشاريع حتى الآن',
                      description: 'استخدم خانة المساعد في الصفحة الرئيسية لإضافة أول طلب. سيُحفظ كمسودة محلية فقط في هذه النسخة.',
                    )
                  else
                    ...projects.map((ProjectDraft project) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ProjectCard(project: project, onDelete: () => projectStore.removeDraft(project.id)),
                    )),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.value, required this.label, required this.icon});
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(17), border: Border.all(color: AppTheme.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: AppTheme.accent),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ],
      ),
    ),
  );
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onDelete});
  final ProjectDraft project;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.folder_special_outlined, color: AppTheme.accent),
              const SizedBox(width: 10),
              Expanded(child: Text(project.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800))),
              const StatusPill(label: 'مسودة'),
              IconButton(onPressed: onDelete, tooltip: 'حذف المسودة', icon: const Icon(Icons.delete_outline, color: AppTheme.textMuted, size: 20)),
            ],
          ),
          const SizedBox(height: 9),
          Text(project.request, style: const TextStyle(color: AppTheme.textMuted, height: 1.5, fontSize: 12)),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          const Row(
            children: <Widget>[
              Icon(Icons.info_outline, size: 15, color: Color(0xFFFFC36B)),
              SizedBox(width: 7),
              Expanded(child: Text('بانتظار ربط محرك التخطيط والتنفيذ', style: TextStyle(color: Color(0xFFFFC36B), fontSize: 11))),
            ],
          ),
        ],
      ),
    );
  }
}
