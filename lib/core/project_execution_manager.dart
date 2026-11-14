import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';

import '../models/domain.dart';
import 'project_coordinator.dart';

/// App-scoped controller for Android background project execution.
///
/// Android owns execution. This manager only submits jobs and mirrors
/// their persisted task states into the current UI isolate.
class ProjectExecutionManager {
  ProjectExecutionManager({required ProjectCoordinator coordinator})
      : _coordinator = coordinator;

  static const MethodChannel _engineChannel =
      MethodChannel('termai/aram-engine');

  final ProjectCoordinator _coordinator;
  final Queue<_QueuedProject> _queue = Queue<_QueuedProject>();
  final Set<String> _queuedOrRunningProjectIds = <String>{};
  _QueuedProject? _activeJob;

  bool _draining = false;

  int get queuedCount => _queue.length;

  bool isQueuedOrRunning(String projectId) =>
      _queuedOrRunningProjectIds.contains(projectId);

  Future<ProjectRecord> enqueue(
    ProjectRecord project, {
    void Function(PlanTask task)? onTaskChanged,
  }) {
    if (!_queuedOrRunningProjectIds.add(project.id)) {
      return Future<ProjectRecord>.error(
        StateError(
          'Project ${project.id} is already queued or executing.',
        ),
      );
    }

    final completer = Completer<ProjectRecord>();
    _queue.add(
      _QueuedProject(
        project: project,
        onTaskChanged: onTaskChanged,
        completer: completer,
      ),
    );

    unawaited(_drain());
    return completer.future;
  }

  Future<bool> cancel(String projectId) async {
    _QueuedProject? queuedJob;

    for (final job in _queue) {
      if (job.project.id == projectId) {
        queuedJob = job;
        break;
      }
    }

    if (queuedJob != null) {
      final previousStatuses = <PlanTask, TaskStatus>{};
      final previousResults = <PlanTask, String>{};

      for (final task in queuedJob.project.tasks) {
        if (task.status != TaskStatus.pending) continue;
        previousStatuses[task] = task.status;
        previousResults[task] = task.result;
        task.status = TaskStatus.interrupted;
        task.result = 'أُلغي المشروع قبل بدء التنفيذ.';
      }

      try {
        await _coordinator.save(queuedJob.project);
      } catch (_) {
        for (final entry in previousStatuses.entries) {
          entry.key.status = entry.value;
          entry.key.result = previousResults[entry.key] ?? '';
        }
        rethrow;
      }

      _queue.remove(queuedJob);
      _queuedOrRunningProjectIds.remove(projectId);

      for (final task in previousStatuses.keys) {
        try {
          queuedJob.onTaskChanged?.call(task);
        } catch (_) {}
      }

      if (!queuedJob.completer.isCompleted) {
        queuedJob.completer.complete(queuedJob.project);
      }
      return true;
    }

    final active = _activeJob;
    if (active == null || active.project.id != projectId) return false;
    if (active.cancelRequested) return true;

    active.cancelRequested = true;
    if (!active.started) return true;

    final accepted = await _requestAndroidCancellation(projectId);
    if (!accepted) active.cancelRequested = false;
    return accepted;
  }

  Future<bool> _requestAndroidCancellation(String projectId) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        final accepted = await _engineChannel.invokeMethod<bool>(
          'cancelProjectExecution',
          <String, Object?>{'projectId': projectId},
        );
        if (accepted == true) return true;
      } on MissingPluginException {
        return false;
      } on PlatformException {
        // The service may still be completing its startup handshake.
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  Future<void> _drain() async {
    if (_draining) return;

    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeFirst();
        _activeJob = job;

        try {
          await _startAndroidExecution(job.project.id);
          job.started = true;

          if (job.cancelRequested) {
            await _requestAndroidCancellation(job.project.id);
          }

          final result = await _watchPersistedExecution(job);
          if (!job.completer.isCompleted) {
            job.completer.complete(result);
          }
        } catch (error, stackTrace) {
          Object reportedError = error;
          try {
            await _markUnfinishedTasksInterrupted(job, error);
          } catch (recoveryError) {
            reportedError = StateError(
              '$error | تعذر حفظ حالة التعافي: $recoveryError',
            );
          }
          if (!job.completer.isCompleted) {
            job.completer.completeError(reportedError, stackTrace);
          }
        } finally {
          _activeJob = null;
          _queuedOrRunningProjectIds.remove(job.project.id);
        }
      }
    } finally {
      _draining = false;
      if (_queue.isNotEmpty) {
        unawaited(_drain());
      }
    }
  }

  Future<void> _startAndroidExecution(String projectId) async {
    final started = await _engineChannel.invokeMethod<bool>(
      'startProjectExecution',
      <String, Object?>{'projectId': projectId},
    );

    if (started != true) {
      throw StateError(
        'Android did not confirm starting project execution.',
      );
    }
  }

  Future<ProjectRecord> _watchPersistedExecution(
    _QueuedProject job,
  ) async {
    final serviceStartTime = DateTime.now();
    var serviceWasActive = false;

    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 800));

      final projects = await _coordinator.listProjects();
      ProjectRecord? persisted;

      for (final candidate in projects) {
        if (candidate.id == job.project.id) {
          persisted = candidate;
          break;
        }
      }

      if (persisted == null) {
        throw StateError(
          'Project ${job.project.id} disappeared from persistent storage.',
        );
      }

      _mirrorTaskStates(job.project, persisted, job.onTaskChanged);

      if (_isExecutionFinished(persisted)) {
        return job.project;
      }

      final serviceActive = await _engineChannel.invokeMethod<bool>(
        'isProjectExecutionActive',
        <String, Object?>{'projectId': job.project.id},
      );

      if (serviceActive == true) {
        serviceWasActive = true;
      }

      final startupGraceExpired = DateTime.now()
              .difference(serviceStartTime) >=
          const Duration(seconds: 15);

      final serviceUnexpectedlyStopped = serviceActive == false &&
          (serviceWasActive || startupGraceExpired);

      if (serviceUnexpectedlyStopped) {
        var changed = false;

        for (final task in persisted.tasks) {
          if (task.status == TaskStatus.running) {
            task.status = TaskStatus.interrupted;
            task.result =
                'توقفت خدمة تنفيذ المشروع قبل اكتمال المهمة. '
                'لم تُعد المهمة تلقائياً لتجنب تكرار آثار جانبية.';
            changed = true;
          } else if (task.status == TaskStatus.pending) {
            task.status = TaskStatus.interrupted;
            task.result =
                'لم تبدأ المهمة لأن خدمة تنفيذ المشروع توقفت.';
            changed = true;
          }
        }

        if (changed) {
          await _coordinator.save(persisted);
          _mirrorTaskStates(job.project, persisted, job.onTaskChanged);
        }

        if (_isExecutionFinished(persisted)) {
          return job.project;
        }

        throw StateError(
          'Android project service stopped before the project reached a terminal state.',
        );
      }
    }
  }

  Future<void> _markUnfinishedTasksInterrupted(
    _QueuedProject job,
    Object error,
  ) async {
    final projects = await _coordinator.listProjects();
    ProjectRecord? persisted;

    for (final candidate in projects) {
      if (candidate.id == job.project.id) {
        persisted = candidate;
        break;
      }
    }

    if (persisted == null) {
      throw StateError(
        'تعذر العثور على المشروع لحفظ حالة التعافي: ${job.project.id}',
      );
    }

    var changed = false;
    for (final task in persisted.tasks) {
      if (task.status != TaskStatus.pending &&
          task.status != TaskStatus.running) {
        continue;
      }

      task.status = TaskStatus.interrupted;
      task.result =
          'توقف تنفيذ المشروع بسبب خطأ في بدء الخدمة أو متابعة التنفيذ: '
          '$error. لم تُعد المهمة تلقائياً لتجنب تكرار آثار جانبية.';
      changed = true;
    }

    if (changed) {
      await _coordinator.save(persisted);
      _mirrorTaskStates(job.project, persisted, job.onTaskChanged);
    }
  }

  void _mirrorTaskStates(
    ProjectRecord target,
    ProjectRecord source,
    void Function(PlanTask task)? onTaskChanged,
  ) {
    final sourceById = <String, PlanTask>{
      for (final task in source.tasks) task.id: task,
    };

    for (final task in target.tasks) {
      final saved = sourceById[task.id];
      if (saved == null) continue;

      final changed =
          task.status != saved.status || task.result != saved.result;

      if (!changed) continue;

      task.status = saved.status;
      task.result = saved.result;
      try {
        onTaskChanged?.call(task);
      } catch (_) {
        // UI observers must not interrupt background project execution.
      }
    }
  }

  bool _isExecutionFinished(ProjectRecord project) {
    if (project.tasks.isEmpty) return false;

    return project.tasks.every(
      (task) =>
          task.status == TaskStatus.completed ||
          task.status == TaskStatus.failed ||
          task.status == TaskStatus.rolledBack ||
          task.status == TaskStatus.interrupted,
    );
  }
}

class _QueuedProject {
  _QueuedProject({
    required this.project,
    required this.onTaskChanged,
    required this.completer,
  });

  final ProjectRecord project;
  final void Function(PlanTask task)? onTaskChanged;
  final Completer<ProjectRecord> completer;

  bool started = false;
  bool cancelRequested = false;
}
