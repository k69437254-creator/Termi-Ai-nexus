import 'package:material_ui/material_ui.dart';
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
  @override
  void initState() { super.initState(); _future = widget.coordinator.listProjects(); }
  void _refresh() => setState(() => _future = widget.coordinator.listProjects());

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ProjectRecord>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      final projects = snapshot.data ?? [];
      if (projects.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.folder_open, size: 45, color: Color(0xFF5B7897)), const SizedBox(height: 12), const Text('لا توجد مشاريع بعد', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)), const SizedBox(height: 6), const Text('ابدأ مشروعاً من المساعد الذكي ليظهر هنا.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF92A8C0))), const SizedBox(height: 12), OutlinedButton(onPressed: _refresh, child: const Text('تحديث'))])));
      return RefreshIndicator(onRefresh: () async => _refresh(), child: ListView(padding: const EdgeInsets.all(14), children: [
        Row(children: [const Expanded(child: Text('مساحات العمل', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))), Text('${projects.length} مشاريع', style: const TextStyle(color: Color(0xFF84CADD), fontSize: 11))]),
        const SizedBox(height: 10),
        ...projects.map((project) => Card(child: ListTile(leading: const CircleAvatar(backgroundColor: Color(0xFF19364D), child: Icon(Icons.code, color: Color(0xFF77C9DD))), title: Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${project.tasks.where((e) => e.status == TaskStatus.completed).length}/${project.tasks.length} مهام مكتملة\n${project.workspacePath}', maxLines: 2, overflow: TextOverflow.ellipsis), isThreeLine: true, trailing: const Icon(Icons.chevron_left), onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => _ProjectDetails(project: project))))),
      ]));
    },
  );
}

class _ProjectDetails extends StatelessWidget {
  const _ProjectDetails({required this.project});
  final ProjectRecord project;
  @override
  Widget build(BuildContext context) => SafeArea(child: SizedBox(height: MediaQuery.sizeOf(context).height * 0.78, child: SingleChildScrollView(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(project.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)), const SizedBox(height: 7), Text(project.request, style: const TextStyle(color: Color(0xFF9CB0C7))), const Divider(height: 24), ...project.tasks.map((task) => ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(task.status == TaskStatus.completed ? Icons.check_circle : Icons.circle_outlined, color: task.status == TaskStatus.completed ? const Color(0xFF58CFA1) : const Color(0xFF8199B4)), title: Text(task.title), subtitle: Text('${task.agentId} • ${task.status.name}'))), const SizedBox(height: 12)]))));
}
