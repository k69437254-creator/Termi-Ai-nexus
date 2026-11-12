import 'dart:async';
import 'dart:convert';
import 'secure_vault.dart';

class MemoryStore {
  final SecureVault _vault = SecureVault.instance;
  static final Map<String, Future<void>> _writeQueues = {};
  static const String _teamKey = 'memory.team.v1';
  static String _agentKey(String id) => 'memory.agent.$id.v1';
  static String _projectKey(String id) => 'memory.project.$id.v1';

  Future<List<String>> _read(String key) async {
    final raw = await _vault.read(key);
    if (raw.isEmpty) return <String>[];
    try { return (jsonDecode(raw) as List).map((e) => e.toString()).toList(); }
    catch (_) { return <String>[]; }
  }

  Future<void> _append(String key, String note, {int limit = 200}) async {
    final value = note.trim();
    if (value.isEmpty) return;
    final previous = _writeQueues[key] ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) async {
      final items = await _read(key);
      items.add('${DateTime.now().toIso8601String()} | $value');
      await _vault.write(key, jsonEncode(items.length > limit ? items.sublist(items.length - limit) : items));
    });
    _writeQueues[key] = next;
    try { await next; }
    finally { if (identical(_writeQueues[key], next)) _writeQueues.remove(key); }
  }

  Future<List<String>> team() => _read(_teamKey);
  Future<List<String>> agent(String id) => _read(_agentKey(id));
  Future<List<String>> project(String id) => _read(_projectKey(id));
  Future<void> addTeam(String note) => _append(_teamKey, note);
  Future<void> addAgent(String id, String note) => _append(_agentKey(id), note);
  Future<void> addProject(String id, String note) => _append(_projectKey(id), note);

  Future<String> contextFor({required String agentId, required String projectId}) async {
    final t = await team();
    final a = await agent(agentId);
    final p = await project(projectId);
    return [
      'TEAM MEMORY:\n${t.reversed.take(40).toList().reversed.join('\n')}',
      'AGENT MEMORY ($agentId):\n${a.reversed.take(30).toList().reversed.join('\n')}',
      'PROJECT MEMORY ($projectId):\n${p.reversed.take(50).toList().reversed.join('\n')}',
    ].join('\n\n');
  }
}
