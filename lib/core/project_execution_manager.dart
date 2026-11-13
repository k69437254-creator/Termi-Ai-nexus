import 'dart:async';
import 'dart:collection';

import '../models/domain.dart';
import 'project_coordinator.dart';

/// App-scoped queue for project execution.
///
/// This manager survives page navigation because AppShell owns it.
/// It is an in-memory queue; Android background execution and recovery
/// after process termination are implemented in later integration steps.
class ProjectExecutionManager {
  ProjectExecutionManager({required ProjectCoordinator coordinator})
      : _coordinator = coordinator;

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

  Future<void> _drain() async {
    if (_draining) return;

    _draining = true;

    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeFirst();

        try {
          final result = await _coordinator.execute(
            job.project,
            onTaskChanged: job.onTaskChanged,
          );

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
