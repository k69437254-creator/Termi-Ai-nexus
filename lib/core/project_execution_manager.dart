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

  /// Queued jobs can be removed safely before Android starts them.
  /// Active-service cancellation is connected in the dedicated cancellation
  /// integration step; this method never reports a false cancellation.
  Future<bool> cancel(String projectId) async {
    _QueuedProject? queuedJob;

    for (final job in _queue) {
      if (job.project.id == projectId) {
        queuedJob = job;
        break;
      }
    }

    if (queuedJob == null) return false;

    _queue.remove(queuedJob);
    _queuedOrRunningProjectIds.remove(projectId);

    if (!queuedJob.completer.isCompleted) {
      queuedJob.completer.complete(queuedJob.project);
    }
    return true;
  }

  Future<void> _drain() async {
    if (_draining) return;

    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeFirst();

        try {
          await _startAndroidExecution(job.project.id);
          final result = await _watchPersistedExecution(job);
          if (!job.completer.isCompleted) {
            job.completer.complete(result);
          }
        } catch (error, stackTrace) {
          if (!job.completer.isCompleted) {
            job.completer.completeError(error, stackTrace);
          }
        } finally {
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
      onTaskChanged?.call(task);
    }
  }

  bool _isExecutionFinished(ProjectRecord project) {
    if (project.tasks.isEmpty) return false;

    final stoppedWithFailure = project.tasks.any(
      (task) =>
          task.status == TaskStatus.failed ||
          task.status == TaskStatus.rolledBack ||
          task.status == TaskStatus.interrupted,
    );

    if (stoppedWithFailure) return true;

    return project.tasks.every(
      (task) => task.status == TaskStatus.completed,
    );
  }
}

class _QueuedProject {
  const _QueuedProject({
    required this.project,
    required this.onTaskChanged,
    required this.completer,
  });

  final ProjectRecord project;
  final void Function(PlanTask task)? onTaskChanged;
  final Completer<ProjectRecord> completer;
}
