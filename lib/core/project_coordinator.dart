import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/domain.dart';
import 'ai_gateway.dart';
import 'memory_store.dart';
import 'project_job_store.dart';
import 'project_workspace.dart';

class ProjectCoordinator {
  ProjectCoordinator({AiGateway? gateway, MemoryStore? memory, ProjectJobStore? jobStore})
      : gateway = gateway ?? AiGateway(),
        memory = memory ?? MemoryStore(),
        jobStore = jobStore ?? ProjectJobStore();
  final AiGateway gateway;
  final MemoryStore memory;
  final ProjectJobStore jobStore;

  Future<List<ProjectRecord>> listProjects() => jobStore.loadProjects();

  Future<void> _saveProjects(List<ProjectRecord> records) => jobStore.saveProjects(records);

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
    if (maxRepairAttempts < 1) throw ArgumentError.value(maxRepairAttempts, 'maxRepairAttempts', 'Must be at least 1.');
    final workspace = ProjectWorkspace(project.workspacePath);
    await workspace.initialize();
    for (final task in project.tasks) {
      if (task.status == TaskStatus.completed) continue;

      if (task.status == TaskStatus.running) {
        task.status = TaskStatus.interrupted;
        task.result = 'انقطع التنفيذ أثناء هذه المهمة. لم تتم إعادة تشغيلها تلقائياً لتجنب تكرار آثار جانبية؛ يلزم فحص حالتها قبل الاستئناف.';
        await save(project);
        onTaskChanged?.call(task);
        break;
      }

      if (task.status != TaskStatus.pending) break;

      task.status = TaskStatus.running;
      await save(project);
      onTaskChanged?.call(task);
      var success = false;
      var rollbackFailed = false;
      var lastError = '';
      for (var attempt = 1; attempt <= maxRepairAttempts && !success && !rollbackFailed; attempt++) {
        final checkpoint = await workspace.checkpoint('${task.id}_attempt_$attempt');
        var attemptedPatches = <String, String>{};
        var appliedPatches = <String, String>{};
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
          final output = gateway.parseAgentOutput(raw);
          final files = output['files'] as List;
          attemptedPatches = workspace.validatePatches(files);
          final changedPaths = await workspace.applyPatches(attemptedPatches, checkpoint: checkpoint);
          appliedPatches = <String, String>{
            for (final path in changedPaths) path: attemptedPatches[path]!,
          };
          final expectedContents = Map<String, String>.from(appliedPatches);
          final verified = await workspace.verifyFiles(expectedContents);
          if (!verified) throw StateError('File content verification failed.');
          final summary = output['summary'] as String;
          final proposedChecks = (output['verification'] as List).cast<String>();
          final checksText = proposedChecks.isEmpty
              ? 'لم يقدم الوكيل فحوصات مقترحة.'
              : proposedChecks.map((item) => '- $item').join('\n');
          final changedFilesText = changedPaths.map((path) => '- `$path`').join('\n');
          final evidence = '## Execution evidence\n\n'
              '- Changed files: ${changedPaths.length}\n'
              '- Full file-content comparison: PASS\n'
              '- Device build and test commands: NOT RUN\n\n'
              '## Agent-proposed checks (not executed)\n$checksText';
          await workspace.writeAgentNote(task.id, '# ${task.title}\n\n$summary\n\n$evidence');
          task.result = '$summary\n\n'
              'دليل التنفيذ: تم تعديل ${changedPaths.length} ملف/ملفات والتحقق من تطابق محتوى كل ملف بالكامل.\n'
              'الملفات المعدلة:\n$changedFilesText\n'
              'لم تُشغّل اختبارات بناء أو تشغيل على الجهاز.';
          task.status = TaskStatus.completed;
          success = true;
          await save(project);
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
          if (error is WorkspaceApplyException && !error.rollbackComplete) {
            rollbackFailed = true;
          }
          try {
            final rollback = await workspace.rollbackPatches(checkpoint, appliedPatches);
            if (!rollback.isComplete) {
              rollbackFailed = true;
              lastError = '$lastError | rollback incomplete for: ${rollback.failedPaths.join(', ')}';
            }
            if (rollback.preservedPaths.isNotEmpty) {
              lastError = '$lastError | preserved external edits: ${rollback.preservedPaths.join(', ')}';
            }
          } catch (restoreError) {
            rollbackFailed = true;
            lastError = '$lastError | rollback error: $restoreError';
          }
          try {
            await memory.addAgent(task.agentId, 'فشلت المحاولة $attempt للمهمة ${task.title}: $lastError');
            await memory.addProject(project.id, 'فشلت المحاولة $attempt للمهمة ${task.title} للوكيل ${task.agentId}: $lastError');
          } catch (_) {
            // A memory-storage problem must not mask the actual task failure.
          }
        }
      }
      if (!success) {
        task.status = rollbackFailed ? TaskStatus.failed : TaskStatus.rolledBack;
        final rollbackMessage = rollbackFailed
            ? 'تعذر إثبات اكتمال التراجع الآمن؛ أوقف النظام المحاولات الإضافية.'
            : 'تم التراجع عن تغييرات المحاولة مع الحفاظ على التعديلات الخارجية المكتشفة.';
        task.result = 'تعذّر إكمال المهمة بعد $maxRepairAttempts محاولات. $rollbackMessage آخر خطأ: $lastError';
        await save(project);
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
