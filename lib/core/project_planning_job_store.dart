import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One durable manager-planning request. It is deliberately separate from the
/// conversation transcript so a request can be recovered after navigation or restart.
class ProjectPlanningJob {
  const ProjectPlanningJob({
    required this.id,
    required this.projectId,
    required this.request,
    required this.stage,
    required this.status,
    required this.message,
    required this.updatedAt,
    this.error = '',
  });

  final String id;
  final String projectId;
  final String request;
  final String stage;
  final String status;
  final String message;
  final String updatedAt;
  final String error;

  ProjectPlanningJob copyWith({
    String? request,
    String? stage,
    String? status,
    String? message,
    String? error,
  }) => ProjectPlanningJob(
    id: id,
    projectId: projectId,
    request: request ?? this.request,
    stage: stage ?? this.stage,
    status: status ?? this.status,
    message: message ?? this.message,
    updatedAt: DateTime.now().toIso8601String(),
    error: error ?? this.error,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'projectId': projectId,
    'request': request,
    'stage': stage,
    'status': status,
    'message': message,
    'updatedAt': updatedAt,
    'error': error,
  };

  factory ProjectPlanningJob.fromJson(Map<String, dynamic> json) => ProjectPlanningJob(
    id: '${json['id'] ?? ''}',
    projectId: '${json['projectId'] ?? ''}',
    request: '${json['request'] ?? ''}',
    stage: '${json['stage'] ?? 'understanding'}',
    status: '${json['status'] ?? 'running'}',
    message: '${json['message'] ?? ''}',
    updatedAt: '${json['updatedAt'] ?? DateTime.now().toIso8601String()}',
    error: '${json['error'] ?? ''}',
  );
}

class ProjectPlanningJobStore {
  ProjectPlanningJobStore({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  static const String storageKey = 'manager.planning_job.v1';
  final SharedPreferencesAsync _preferences;

  Future<ProjectPlanningJob?> load() async {
    final raw = await _preferences.getString(storageKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Saved planning job is not an object.');
    return ProjectPlanningJob.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> save(ProjectPlanningJob job) =>
      _preferences.setString(storageKey, jsonEncode(job.toJson()));

  Future<void> clear() => _preferences.remove(storageKey);
}
