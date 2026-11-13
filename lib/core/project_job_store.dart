import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/domain.dart';

/// Durable persistence for project jobs and their task states.
///
/// The existing projects.v1 key is intentionally retained so existing projects
/// are read in place without a data migration or a parallel source of truth.
class ProjectJobStore {
  ProjectJobStore({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  static const String storageKey = 'projects.v1';
  final SharedPreferencesAsync _preferences;

  Future<List<ProjectRecord>> loadProjects() async {
    final raw = await _preferences.getString(storageKey);
    if (raw == null) return <ProjectRecord>[];

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Saved project jobs must be a JSON list.');
    }

    return decoded.map((entry) {
      if (entry is! Map) {
        throw const FormatException('A saved project job is not a JSON object.');
      }
      return ProjectRecord.fromJson(Map<String, dynamic>.from(entry));
    }).toList(growable: true);
  }

  Future<void> saveProjects(List<ProjectRecord> projects) async {
    final encoded = jsonEncode(projects.map((project) => project.toJson()).toList());
    await _preferences.setString(storageKey, encoded);
  }
}
