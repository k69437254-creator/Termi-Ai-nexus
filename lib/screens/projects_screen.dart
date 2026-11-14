import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/nexus_theme.dart';
import '../core/project_coordinator.dart';
import '../models/domain.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key, required this.coordinator});
  final ProjectCoordinator coordinator;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late Future<List<ProjectRecord>> _future;
  Timer? _refreshTimer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _future = widget.coordinator.listProjects();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshAutomatically(),
    );
  }

  Future<void> _refreshAutomatically() async {
    if (!mounted || _refreshing) return;

    _refreshing = true;
    try {
      final next = widget.coordinator.listProjects();
      setState(() => _future = next);
      await next;
    } catch (_) {
      // Keep the last displayed project snapshot if a refresh fails.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;

    _refreshing = true;
    try {
      final next = widget.coordinator.listProjects();
      setState(() => _future = next);
      await next;
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ProjectRecord>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final projects = snapshot.data ?? [];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 5, 16, 25),
              children: [
                NexusPageHeader(
                  title: 'مساحات العمل',
                  subtitle: 'كل مشروع يحتفظ بطلبه وخطته ونتائج وكلائه داخل مساحة مستقلة.',
                  padding: const EdgeInsets.fromLTRB(0, 12, 0, 17),
                  trailing: NexusStatusPill('${projects.length} مشاريع', icon: Icons.folder_copy_outlined),
                ),
                if (projects.isEmpty)
                  const NexusGlassPanel(
                    padding: EdgeInsets.symmetric(horizontal: 22, vertical: 30),
                    child: Column(children: [
                      NexusIconTile(Icons.folder_open_rounded, size: 54),
                      SizedBox(height: 14),
                      Text('مساحة العمل ما زالت فارغة', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      SizedBox(height: 6),
                      Text('ابدأ من محادثة المساعد الذكي، وستظهر خططك ومشاريعك هنا.', textAlign: TextAlign.center, style: TextStyle(color: NexusPalette.muted, fontSize: 11, height: 1.5)),
                    ]),
                  )
                else
                  ...projects.map((project) => _ProjectCard(
                        project: project,
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => _ProjectDetails(
                            project: project,
                            coordinator: widget.coordinator,
                          ),
                        ),
                      )),
              ],
            ),
          );
        },
      );
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});
  final ProjectRecord project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = project.tasks.where((task) => task.status == TaskStatus.completed).length;
    final total = project.tasks.length;
    final progress = total == 0 ? 0.0 : done / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(21),
          onTap: onTap,
          child: NexusGlassPanel(
            padding: const EdgeInsets.all(15),
            radius: 21,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const NexusIconTile(Icons.code_rounded),
                const SizedBox(width: 11),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w900, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('${project.tasks.length} مهام • ${project.createdAt.toLocal().toString().split('.').first}', style: const TextStyle(color: NexusPalette.muted, fontSize: 9)),
                ])),
                const Icon(Icons.chevron_left_rounded, color: NexusPalette.subtle),
              ]),
              const SizedBox(height: 13),
              Row(children: [
                Expanded(child: Text('$done من $total مهام مكتملة', style: const TextStyle(color: NexusPalette.muted, fontSize: 10))),
                Text('${(progress * 100).round()}%', style: const TextStyle(color: NexusPalette.primaryLight, fontWeight: FontWeight.w900, fontSize: 10)),
              ]),
              const SizedBox(height: 7),
              ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: progress, minHeight: 5, backgroundColor: NexusPalette.border, color: NexusPalette.primary)),
              const SizedBox(height: 9),
              Text(project.workspacePath, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: const TextStyle(color: NexusPalette.subtle, fontSize: 9)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ProjectDetails extends StatefulWidget {
  const _ProjectDetails({
    required this.project,
    required this.coordinator,
  });

  final ProjectRecord project;
  final ProjectCoordinator coordinator;

  @override
  State<_ProjectDetails> createState() => _ProjectDetailsState();
}

class _ProjectDetailsState extends State<_ProjectDetails> {
  Timer? _refreshTimer;
  late Future<ProjectRecord?> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadProject();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshProject(),
    );
  }

  Future<ProjectRecord?> _loadProject() async {
    final projects = await widget.coordinator.listProjects();
    for (final project in projects) {
      if (project.id == widget.project.id) return project;
    }
    return null;
  }

  void _refreshProject() {
    if (!mounted) return;
    setState(() => _future = _loadProject());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ProjectRecord?>(
        future: _future,
        builder: (context, snapshot) {
          final project = snapshot.data ?? widget.project;
          return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.82,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 25),
            children: [
              Text(project.name, style: const TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 7),
              Text(project.request, style: const TextStyle(color: NexusPalette.muted, fontSize: 12, height: 1.5)),
              const SizedBox(height: 15),
              const NexusSectionHeader('مسار التنفيذ', subtitle: 'الحالة الحالية لكل مهمة في هذه المساحة.'),
              ...project.tasks.asMap().entries.map((entry) {
                final task = entry.value;
                final color = switch (task.status) {
                  TaskStatus.completed => NexusPalette.success,
                  TaskStatus.running => NexusPalette.primaryLight,
                  TaskStatus.failed || TaskStatus.rolledBack || TaskStatus.interrupted => NexusPalette.danger,
                  _ => NexusPalette.muted,
                };
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: NexusGlassPanel(
                    padding: const EdgeInsets.all(12),
                    radius: 16,
                    blur: 7,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      NexusIconTile(task.status == TaskStatus.completed ? Icons.check_rounded : Icons.task_alt_rounded, color: color, size: 35),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${entry.key + 1}. ${task.title}', style: const TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w800, fontSize: 11)),
                        const SizedBox(height: 4),
                        Text('${task.agentId} • ${task.status.name}', style: TextStyle(color: color, fontSize: 9)),
                        if (task.result.isNotEmpty) ...[const SizedBox(height: 6), Text(task.result, style: const TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.4))],
                      ])),
                    ]),
                  ),
                );
              }),
            ],
          ),
        ),
      );
        },
      );
  }
}
