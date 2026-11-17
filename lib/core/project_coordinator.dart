// TERMAI_GITHUB_AUTOMATION_UPDATE_20261116_V1
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/domain.dart';
import 'agent_command_executor.dart';
import 'agent_tool_runtime.dart';
import 'ai_gateway.dart';
import 'memory_store.dart';
import 'project_job_store.dart';
import 'project_workspace.dart';
import 'nexus_feature_suite.dart';

class ProjectExecutionControl {
  bool cancelRequested = false;
  String? requestId;
}

class _ProjectExecutionCancelled implements Exception {
  const _ProjectExecutionCancelled();
}

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

  // ARAM_NEXUS_SOURCE_UPDATE_20261116: idempotent plan creation with persisted draft reservation.
  Future<ProjectRecord> prepare(
    String request, {
    String? projectId,
    Future<void> Function(String stage, String message)? onProgress,
  }) async {
    final id = projectId?.trim().isNotEmpty == true
        ? projectId!.trim()
        : const Uuid().v4();
    if (!RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(id)) {
      throw ArgumentError('معرف المشروع غير صالح؛ يجب أن يتكون من 8 إلى 64 حرفًا أو رقمًا أو شرطة.');
    }
    final all = await listProjects();
    final existingIndex = all.indexWhere((item) => item.id == id);
    if (existingIndex >= 0) {
      final existing = all[existingIndex];
      if (existing.request != request) {
        throw StateError('معرف طلب التخطيط مرتبط بطلب مختلف؛ أوقف الاستعادة لمنع تكرار المشروع.');
      }
      if (existing.tasks.isNotEmpty) return existing;
    }

    await onProgress?.call('workspace', 'جارٍ حفظ طلب التخطيط وتجهيز مساحة العمل…');
    final docs = await getApplicationDocumentsDirectory();
    final slug = request.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final name = slug.isEmpty ? 'project-${id.substring(0, 8)}'
        : slug.substring(0, slug.length > 32 ? 32 : slug.length);
    final workspacePath = existingIndex >= 0
        ? all[existingIndex].workspacePath
        : p.join(docs.path, 'TermiAI-Nexus', 'workspaces', '${name}_${id.substring(0, 8)}');
    final draft = ProjectRecord(
      id: id, name: name, request: request, workspacePath: workspacePath,
      createdAt: existingIndex >= 0 ? all[existingIndex].createdAt : DateTime.now(),
      tasks: const <PlanTask>[],
    );
    if (existingIndex < 0) {
      all.insert(0, draft);
    } else {
      all[existingIndex] = draft;
    }
    await _saveProjects(all);

    final workspace = ProjectWorkspace(workspacePath);
    await workspace.initialize();
    await onProgress?.call('planning', 'تم تجهيز مساحة العمل؛ يجري الآن توليد خطة المهام من محرك Aram AI…');
    final tasks = await gateway.createPlan(request, id, memory, requestId: id);
    await onProgress?.call('saving', 'اكتمل توليد الخطة؛ جارٍ حفظ المهام وربطها بالمشروع…');
    final record = ProjectRecord(
      id: id, name: name, request: request, workspacePath: workspacePath,
      createdAt: draft.createdAt, tasks: tasks,
    );
    final latest = await listProjects();
    final latestIndex = latest.indexWhere((item) => item.id == id);
    if (latestIndex >= 0) {
      latest[latestIndex] = record;
    } else {
      latest.insert(0, record);
    }
    await _saveProjects(latest);
    try {
      await memory.addTeam('تم إنشاء مشروع $name وجرى إعداد خطة من ${tasks.length} مهام.');
      await memory.addProject(id, 'طلب المستخدم: $request');
    } catch (_) {
      // The saved project plan remains authoritative if ancillary memory logging fails.
    }
    await onProgress?.call('complete', 'تم حفظ الخطة؛ وهي بانتظار موافقتك قبل التنفيذ.');
    return record;
  }


  Future<ProjectRecord> execute(ProjectRecord project, {int maxRepairAttempts = 3, void Function(PlanTask task)? onTaskChanged, ProjectExecutionControl? control}) async {
    final executionControl = control ?? ProjectExecutionControl();
    if (maxRepairAttempts < 1) throw ArgumentError.value(maxRepairAttempts, 'maxRepairAttempts', 'Must be at least 1.');
    final leaseId = await gateway.acquireProjectExecutionLease();
    try {
      final workspace = ProjectWorkspace(project.workspacePath);
      await workspace.initialize();
      for (final task in project.tasks) {
        if (executionControl.cancelRequested) {
          var changedPendingTasks = false;
          for (final pendingTask in project.tasks) {
            if (pendingTask.status != TaskStatus.pending) continue;
            pendingTask.status = TaskStatus.interrupted;
            pendingTask.result = 'أُلغي التنفيذ قبل بدء هذه المهمة.';
            onTaskChanged?.call(pendingTask);
            changedPendingTasks = true;
          }
          if (changedPendingTasks) await save(project);
          break;
        }
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
        project.deploymentStatus = project.githubRepository == null ? project.deploymentStatus : 'agents';
        final finishedBefore = project.tasks.where((item) => item.status == TaskStatus.completed).length;
        project.deploymentProgress = project.githubRepository == null ? project.deploymentProgress : (10 + (finishedBefore / project.tasks.length) * 60).clamp(10, 70).toDouble();
        project.deploymentMessage = project.githubRepository == null ? project.deploymentMessage : 'الوكلاء ينفذون ${task.title} داخل Ubuntu/PRoot.';
        project.executionLog.add('${DateTime.now().toIso8601String()} • بدأ ${task.title} بواسطة ${task.agentId}.');
        if (project.executionLog.length > 120) project.executionLog.removeRange(0, project.executionLog.length - 120);
        await save(project);
        onTaskChanged?.call(task);
        var success = false;
        var rollbackFailed = false;
        var cancelled = false;
        var lastError = '';
        for (var attempt = 1; attempt <= maxRepairAttempts && !success && !rollbackFailed; attempt++) {
          if (executionControl.cancelRequested) {
            cancelled = true;
            break;
          }
          final checkpoint = await workspace.checkpoint('${task.id}_attempt_$attempt');
          var attemptedPatches = <String, String>{};
          var appliedPatches = <String, String>{};
          final stagingId = '${task.id}_attempt_$attempt';
          final toolRuntime = AgentToolRuntime(
            workspace,
            commandExecutor: const PlatformAgentCommandExecutor(),
            stagingId: stagingId,
            allowFileWrites: task.agentId != 'qa',
          );
          try {
            final workspaceContext = await workspace.readContextSnapshot(maxFiles: 12, maxCharacters: 6000);
            if (executionControl.cancelRequested) {
              throw const _ProjectExecutionCancelled();
            }
            final requestId = const Uuid().v4();
            executionControl.requestId = requestId;
            final raw = await gateway.executeTask(
              agentId: task.agentId,
              taskTitle: task.title,
              taskDescription: '${task.description}\nمحاولة الإصلاح: $attempt من $maxRepairAttempts. الخطأ السابق إن وجد: $lastError',
              projectId: project.id,
              workspaceContext: workspaceContext,
              memory: memory,
              requestId: requestId,
              toolRuntime: toolRuntime,
            );
            if (executionControl.requestId == requestId) {
              executionControl.requestId = null;
            }
            if (executionControl.cancelRequested) {
              throw const _ProjectExecutionCancelled();
            }
            final isQa = task.agentId == 'qa';
          final output = gateway.parseAgentOutput(
            raw,
            allowEmptyStagedFiles: isQa,
          );

          final List<dynamic> filePatches;
          if (isQa) {
            final manifest = output['stagedFiles'];
            final legacyFiles = output['files'];
            final qaEvidence = toolRuntime.successfulValidationEvidence;

            if (manifest is! List || manifest.isNotEmpty) {
              throw StateError('QA must return an explicitly empty stagedFiles list.');
            }
            if (legacyFiles is List && legacyFiles.isNotEmpty) {
              throw StateError('QA is not permitted to return legacy file patches.');
            }
            if (toolRuntime.stagedPaths.isNotEmpty) {
              throw StateError('QA attempted to stage files despite its read-only policy.');
            }
            if (toolRuntime.lastToolName != 'inspect_project') {
              throw StateError('QA must finish with an actual inspect_project tool call.');
            }
            if (qaEvidence.isEmpty) {
              throw StateError(
                'QA rejected: workspace inspection produced no successful structural evidence.',
              );
            }

            final report = StringBuffer()
              ..writeln('# QA Report')
              ..writeln()
              ..writeln('## Task')
              ..writeln(task.title)
              ..writeln()
              ..writeln('## Agent summary')
              ..writeln(output['summary'])
              ..writeln()
              ..writeln('## Executed workspace inspection evidence')
              ..writeln();

            for (var i = 0; i < qaEvidence.length; i++) {
              final item = qaEvidence[i];
              final command = item['command'];
              final args = (item['args'] as List).cast<String>();
              report
                ..writeln('### Validation ${i + 1}')
                ..writeln('- Command: `$command`')
                ..writeln('- Arguments: `${args.join(' ')}`')
                ..writeln('- Exit code: `${item['exit_code']}`')
                ..writeln('- Timed out: `${item['timed_out']}`')
                ..writeln('- Output truncated: `${item['truncated']}`');
              final commandOutput = item['output'] as String? ?? '';
              if (commandOutput.isNotEmpty) {
                report
                  ..writeln()
                  ..writeln('```text')
                  ..writeln(commandOutput)
                  ..writeln('```');
              }
              report.writeln();
            }

            final verificationNotes =
                (output['verification'] as List).cast<String>();
            report
              ..writeln('## QA notes')
              ..writeln(
                verificationNotes.isEmpty
                    ? 'No additional notes were supplied.'
                    : verificationNotes.map((item) => '- $item').join('\n'),
              )
              ..writeln()
              ..writeln('## Risks')
              ..writeln();

            final risks = output['risks'];
            if (risks is List && risks.isNotEmpty) {
              report.writeln(risks.map((item) => '- $item').join('\n'));
            } else {
              report.writeln('No additional risks were reported by the QA agent.');
            }

            filePatches = <dynamic>[
              {
                'path': 'docs/QA_REPORT.md',
                'content': report.toString(),
              },
            ];
          } else {
            final stagedManifest = output['stagedFiles'];
            if (stagedManifest is List) {
              final staged = await workspace.readStagedFiles(
                stagingId,
                stagedManifest.cast<String>(),
              );
              filePatches = [
                for (final entry in staged.entries)
                  {'path': entry.key, 'content': entry.value},
              ];
            } else {
              filePatches = output['files'] as List;
            }
          }
          attemptedPatches = workspace.validatePatches(filePatches);
            final changedPaths = await workspace.applyPatches(attemptedPatches, checkpoint: checkpoint);
            appliedPatches = <String, String>{
              for (final path in changedPaths) path: attemptedPatches[path]!,
            };
            final expectedContents = Map<String, String>.from(appliedPatches);
            if (executionControl.cancelRequested) {
              throw const _ProjectExecutionCancelled();
            }
            final verified = await workspace.verifyFiles(expectedContents);
            if (!verified) throw StateError('File content verification failed.');
            if (executionControl.cancelRequested) {
              throw const _ProjectExecutionCancelled();
            }
            final summary = output['summary'] as String;
            final proposedChecks = (output['verification'] as List).cast<String>();
            final checksText = proposedChecks.isEmpty
                ? 'لم يقدم الوكيل ملاحظات تحقق.'
                : proposedChecks.map((item) => '- $item').join('\n');
            final changedFilesText = changedPaths.map((path) => '- `$path`').join('\n');
            final commandEvidence = toolRuntime.successfulValidationEvidence;
          final commandEvidenceLines = commandEvidence.map((item) {
            final args = (item['args'] as List).cast<String>();
            return '- `${item['command']} ${args.join(' ')}`: exit=${item['exit_code']}, timed_out=${item['timed_out']}, truncated=${item['truncated']}';
          }).toList(growable: false);
          final evidence = '## Execution evidence\n\n'
              '- Changed files: ${changedPaths.length}\n'
              '- Full file-content comparison: PASS\n'
              '- Successful executed validation commands: ${commandEvidence.length}\n'
              '${commandEvidenceLines.join('\n')}\n\n'
              '## Agent notes\n$checksText';
          await workspace.writeAgentNote(task.id, '# ${task.title}\n\n$summary\n\n$evidence');
            await workspace.discardStagedFiles(stagingId);
            if (executionControl.cancelRequested) {
              throw const _ProjectExecutionCancelled();
            }
            final validationText = commandEvidenceLines.isEmpty
                ? 'لم تُشغّل أوامر تحقق في هذه المهمة؛ بوابة QA النهائية هي التي تحدد صلاحية التسليم.'
                : 'أوامر تحقق ناجحة نُفذت فعلياً داخل Ubuntu/PRoot:\n${commandEvidenceLines.join('\n')}';
            task.result = '$summary\n\n'
                'دليل التنفيذ: تم تعديل ${changedPaths.length} ملف/ملفات والتحقق من تطابق محتوى كل ملف بالكامل.\n'
                'الملفات المعدلة:\n$changedFilesText\n'
                '$validationText';
            task.status = TaskStatus.completed;
            success = true;
            final finishedNow = project.tasks.where((item) => item.status == TaskStatus.completed).length;
            project.deploymentProgress = project.githubRepository == null ? project.deploymentProgress : (10 + (finishedNow / project.tasks.length) * 60).clamp(10, 70).toDouble();
            project.deploymentMessage = project.githubRepository == null ? project.deploymentMessage : 'اكتملت ${task.title}؛ $finishedNow من ${project.tasks.length} مهام.';
            project.executionLog.add('${DateTime.now().toIso8601String()} • اكتملت ${task.title}؛ تغييرات الملفات: ${changedPaths.length}.');
            if (project.executionLog.length > 120) project.executionLog.removeRange(0, project.executionLog.length - 120);
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
            try {
              await workspace.discardStagedFiles(stagingId);
            } catch (_) {
              // Preserve the original failure; staging cleanup is best effort.
            }
            executionControl.requestId = null;
            final wasCancelled = error is _ProjectExecutionCancelled || executionControl.cancelRequested;
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
            if (wasCancelled) {
              cancelled = true;
              break;
            }
          }
        }
        if (cancelled || executionControl.cancelRequested) {
          task.status = TaskStatus.interrupted;
          task.result = rollbackFailed
              ? 'طُلب إلغاء المهمة، لكن تعذر إثبات اكتمال التراجع الآمن. يلزم فحص مساحة العمل.'
              : 'أُلغي تنفيذ المهمة. أُوقف طلب Spark وجرت محاولة التراجع عن تغييرات المحاولة مع الحفاظ على التعديلات الخارجية.';
          await save(project);
          onTaskChanged?.call(task);
          break;
        }
        if (!success) {
          task.status = rollbackFailed ? TaskStatus.failed : TaskStatus.rolledBack;
          project.executionLog.add('${DateTime.now().toIso8601String()} • فشلت ${task.title}: $lastError');
          if (project.executionLog.length > 120) project.executionLog.removeRange(0, project.executionLog.length - 120);
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
      if (project.tasks.isNotEmpty &&
          project.tasks.every((task) => task.status == TaskStatus.completed)) {
        try {
          await NexusDocumentationGenerator.generate(
            project.workspacePath,
            projectName: project.name,
          );
        } catch (documentationError) {
          project.tasks.last.result +=
              '\nتعذر إنشاء الدليل الآلي: $documentationError';
        }
      }
      final all = await listProjects();
      final index = all.indexWhere((e) => e.id == project.id);
      if (index >= 0) all[index] = project;
      await _saveProjects(all);
      return project;
    } finally {
      await gateway.releaseProjectExecutionLease(leaseId);
    }
  }

  Future<bool> cancelGeneration(String requestId) => gateway.cancelGeneration(requestId);

  Future<void> save(ProjectRecord project) async {
    final all = await listProjects();
    final index = all.indexWhere((e) => e.id == project.id);
    if (index >= 0) { all[index] = project; } else { all.insert(0, project); }
    await _saveProjects(all);
  }

  Future<String> workspaceFor(ProjectRecord project) async => project.workspacePath;
}
