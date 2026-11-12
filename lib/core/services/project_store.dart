import 'package:flutter/foundation.dart';

import '../models/project_draft.dart';

/// Holds project requests locally for the current app session.
/// Persistent storage and execution orchestration are intentionally not
/// claimed until those services are implemented and tested.
class ProjectStore extends ChangeNotifier {
  final List<ProjectDraft> _projects = <ProjectDraft>[];

  List<ProjectDraft> get projects => List<ProjectDraft>.unmodifiable(_projects);

  ProjectDraft addDraft(String request) {
    final String normalized = request.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(request, 'request', 'Request cannot be empty.');
    }

    final String title = normalized.split(RegExp(r'\s+')).take(7).join(' ');
    final DateTime now = DateTime.now();
    final ProjectDraft draft = ProjectDraft(
      id: '${now.microsecondsSinceEpoch}',
      title: title.length > 52 ? '${title.substring(0, 49)}…' : title,
      request: normalized,
      createdAt: now,
    );

    _projects.insert(0, draft);
    notifyListeners();
    return draft;
  }

  void removeDraft(String id) {
    _projects.removeWhere((ProjectDraft project) => project.id == id);
    notifyListeners();
  }
}
