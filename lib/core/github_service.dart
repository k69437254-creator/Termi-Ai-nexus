import 'dart:convert';
import 'package:http/http.dart' as http;
import 'secure_vault.dart';

class GitHubService {
  GitHubService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final SecureVault _vault = SecureVault.instance;
  static const _api = 'https://api.github.com';

  Future<Map<String, String>> _headers() async {
    final token = await _vault.read('github.token');
    if (token.isEmpty) throw StateError('أضف GitHub Personal Access Token في الإعدادات.');
    return {'Authorization': 'Bearer $token', 'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'Content-Type': 'application/json'};
  }

  Future<List<Map<String, dynamic>>> repositories({int page = 1}) async {
    final response = await _client.get(Uri.parse('$_api/user/repos?sort=updated&per_page=50&page=$page'), headers: await _headers());
    final data = _decode(response);
    if (data is! List) throw const FormatException('Unexpected repositories response');
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> createRepository({required String name, String description = '', bool isPrivate = true}) async {
    final response = await _client.post(Uri.parse('$_api/user/repos'), headers: await _headers(), body: jsonEncode({'name': name, 'description': description, 'private': isPrivate, 'auto_init': true}));
    final data = _decode(response);
    if (data is! Map<String, dynamic>) throw const FormatException('Unexpected create repository response');
    return data;
  }

  Uri _repositoryEndpoint(String owner, String repo, String resource) {
    final safePart = RegExp(r'^[A-Za-z0-9_.-]{1,100}$');
    if (!safePart.hasMatch(owner) || !safePart.hasMatch(repo)) {
      throw FormatException('Invalid GitHub owner or repository name.');
    }
    return Uri.https('api.github.com', '/repos/$owner/$repo/$resource');
  }

  Future<Map<String, dynamic>> createIssue({required String owner, required String repo, required String title, required String body}) async {
    final response = await _client.post(_repositoryEndpoint(owner, repo, 'issues'), headers: await _headers(), body: jsonEncode({'title': title, 'body': body}));
    final data = _decode(response);
    if (data is! Map<String, dynamic>) throw const FormatException('Unexpected issue response');
    return data;
  }

  Future<Map<String, dynamic>> createPullRequest({required String owner, required String repo, required String title, required String head, required String base, String body = ''}) async {
    final response = await _client.post(_repositoryEndpoint(owner, repo, 'pulls'), headers: await _headers(), body: jsonEncode({'title': title, 'head': head, 'base': base, 'body': body}));
    final data = _decode(response);
    if (data is! Map<String, dynamic>) throw const FormatException('Unexpected pull request response');
    return data;
  }

  Future<List<Map<String, dynamic>>> workflowRuns({
    required String owner,
    required String repo,
    required String branch,
  }) async {
    final safePart = RegExp(r'^[A-Za-z0-9_.-]{1,100}$');
    if (!safePart.hasMatch(owner) || !safePart.hasMatch(repo) || branch.trim().isEmpty) {
      throw FormatException('Invalid GitHub workflow query.');
    }
    final uri = Uri.https('api.github.com', '/repos/$owner/$repo/actions/runs', {
      'branch': branch,
      'per_page': '20',
    });
    final response = await _client.get(uri, headers: await _headers());
    final data = _decode(response);
    if (data is! Map || data['workflow_runs'] is! List) {
      throw const FormatException('Unexpected GitHub workflow-runs response.');
    }
    return (data['workflow_runs'] as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> dispatchWorkflow({
    required String owner,
    required String repo,
    required String workflow,
    required String ref,
  }) async {
    final safePart = RegExp(r'^[A-Za-z0-9_.-]{1,100}$');
    if (!safePart.hasMatch(owner) || !safePart.hasMatch(repo) ||
        !RegExp(r'^[A-Za-z0-9_.-]+\.ya?ml$').hasMatch(workflow) ||
        ref.trim().isEmpty) {
      throw FormatException('Invalid GitHub workflow dispatch arguments.');
    }
    final uri = Uri.https(
      'api.github.com',
      '/repos/$owner/$repo/actions/workflows/$workflow/dispatches',
    );
    final response = await _client.post(
      uri,
      headers: await _headers(),
      body: jsonEncode({'ref': ref}),
    );
    if (response.statusCode != 204) {
      _decode(response);
      throw Exception('GitHub workflow dispatch failed (${response.statusCode}).');
    }
  }

  dynamic _decode(http.Response response) {
    dynamic body;
    try { body = jsonDecode(response.body); } catch (_) { body = response.body; }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = body is Map ? body['message'] : body.toString();
      throw Exception('GitHub API ${response.statusCode}: $message');
    }
    return body;
  }

  void dispose() => _client.close();
}
