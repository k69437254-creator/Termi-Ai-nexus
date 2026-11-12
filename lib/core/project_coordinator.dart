import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/domain.dart';
import 'ai_gateway.dart';
import 'memory_store.dart';
import 'project_workspace.dart';

class ProjectCoordinator {
  ProjectCoordinator({AiGateway? gateway, MemoryStore? memory})
      : gateway = gateway ?? AiGateway(), memory = memory ?? MemoryStore();
  final AiGateway gateway;
  final MemoryStore memory;
  static const _projectsKey = 'projects.v1';

  Future<List<ProjectRecord>> listProjects() async {
    final prefs = SharedPreferencesAsync();
    final raw = await prefs.getString(_projectsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).whereType<Map>().map((e) => ProjectRecord.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) { return []; }
  }

  Future<void> _saveProjects(List<ProjectRecord> records) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString(_projectsKey, jsonEncode(records.map((e) => e.toJson()).toList()));
  }

  Future<ProjectRecord> prepare(String request) async {
    final id = const Uuid().v4();
    final docs = await getApplicationDocumentsDirectory();
    final slug = request.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    final name = slug.isEmpty ? 'project-${id.substring(0, 8)}' : slug.substring(0, slug.length > 32 ? 32 : slug.length);
    final workspacePath = p.join(docs.path, 'TermiAI-Nexus', 'workspaces', '${name}_${id.substring(0, 8)}');
    final workspace = ProjectWorkspace(workspacePath);
    await workspace.initialize();
    final tasks = await gateway.createPlan(request, id, memory);
    final record = ProjectRecord(id: id, name: name, request: request, workspacePath: workspacePath, createdAt: DateTime.now(), tasks: tasks);
    final all = await listProjects();
    all.insert(0, record);
    await _saveProjects(all);
    await memory.addTeam('تم إنشاء مشروع $name وجرى إعداد خطة من ${tasks.length} مهام.');
    await memory.addProject(id, 'طلب المستخدم: $request');
    return record;
  }

  Future<ProjectRecord> execute(ProjectRecord project, {int maxRepairAttempts = 3, void Function(PlanTask task)? onTaskChanged}) async {
    final workspace = ProjectWorkspace(project.workspacePath);
    await workspace.initialize();
    for (final task in project.tasks) {
      task.status = TaskStatus.running;
      onTaskChanged?.call(task);
      var success = false;
      var lastError = '';
      for (var attempt = 1; attempt <= maxRepairAttempts && !success; attempt++) {
        final checkpoint = await workspace.checkpoint('${task.id}_attempt_$attempt');
        var attemptedPatches = <String, String>{};
        try {
          final workspaceContext = await workspace.readContextSnapshot();
          final raw = await gateway.executeTask(
            agentId: task.agentId,
            taskTitle: task.title,
            taskDescription: '${task.description}\nمحاولة الإصلاح: $attempt من $maxRepairAttempts. الخطأ السابق إن وجد: $lastError',
            projectId: project.id,
            workspaceContext: workspaceContext,
            memory: memory,
          );
          Map<String, dynamic> output;
          try {
            output = gateway.parseAgentOutput(raw);
          } catch (_) {
            output = {'summary': raw, 'files': <dynamic>[], 'verification': <dynamic>[]};
          }
          final files = (output['files'] as List?) ?? const [];
          attemptedPatches = workspace.validatePatches(files);
          final changedPaths = await workspace.applyPatches(attemptedPatches);
          final verified = await workspace.verifyFiles(changedPaths);
          if (!verified) throw StateError('File presence verification failed.');
          final summary = output['summary']?.toString() ?? raw;
          await workspace.writeAgentNote(task.id, '# ${task.title}\n\n$summary\n\n## Verification requested\n${(output['verification'] as List? ?? const []).join('\n')}\n\n> Presence checks only. No device build or test command was run by this coordinator.');
          task.result = summary;
          task.status = TaskStatus.completed;
          success = true;
          try {
            await memory.addAgent(task.agentId, 'نجحت المهمة ${task.title}. تغييرات الملفات: ${changedPaths.join(', ')}');
            if (attempt > 1 && lastError.isNotEmpty) {
              await memory.addAgent(task.agentId, 'سجل تعافٍ موثق: نجحت المهمة في المحاولة $attempt بعد الخطأ السابق: $lastError. اعتبر هذا سياقاً للمراجعة، لا قاعدة عامة مثبتة.');
            }
            await memory.addProject(project.id, 'تسليم الوكيل ${task.agentId}: ${task.title}. النتيجة: $summary. الملفات: ${changedPaths.join(', ')}');
            await memory.addTeam('اكتملت مهمة ${task.title} في المشروع ${project.name}.');
          } catch (memoryError) {
            task.result = '$summary\n\nتعذر تحديث سجل الذاكرة: $memoryError';
          }
        } catch (error) {
          task.status = TaskStatus.running;
          lastError = error.toString();
          try { await workspace.rollbackPatches(checkpoint, attemptedPatches); } catch (restoreError) { lastError = '$lastError | rollback error: $restoreError'; }
          try {
            await memory.addAgent(task.agentId, 'فشلت المحاولة $attempt للمهمة ${task.title}: $lastError');
            await memory.addProject(project.id, 'فشلت المحاولة $attempt للمهمة ${task.title} للوكيل ${task.agentId}: $lastError');
          } catch (_) {
            // A memory-storage problem must not mask the actual task failure.
          }
        }
      }
      if (!success) {
        task.status = TaskStatus.rolledBack;
        task.result = 'تعذّر إكمال المهمة بعد $maxRepairAttempts محاولات. آخر خطأ: $lastError';
        onTaskChanged?.call(task);
        break;
      }
      onTaskChanged?.call(task);
    }
    final all = await listProjects();
    final index = all.indexWhere((e) => e.id == project.id);
    if (index >= 0) all[index] = project;
    await _saveProjects(all);
    return project;
  }

  Future<void> save(ProjectRecord project) async {
    final all = await listProjects();
    final index = all.indexWhere((e) => e.id == project.id);
    if (index >= 0) { all[index] = project; } else { all.insert(0, project); }
    await _saveProjects(all);
  }

  Future<String> workspaceFor(ProjectRecord project) async => project.workspacePath;
}
