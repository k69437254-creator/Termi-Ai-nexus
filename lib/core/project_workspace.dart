import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'approval_policy.dart';

class WorkspaceCheckpoint {
  const WorkspaceCheckpoint({required this.directory, required this.createdAt});
  final Directory directory;
  final DateTime createdAt;
}

class ProjectWorkspace {
  ProjectWorkspace(this.rootPath);
  final String rootPath;
  Directory get root => Directory(rootPath);

  Future<void> initialize() async {
    await root.create(recursive: true);
    await Directory(p.join(rootPath, '.termai', 'checkpoints')).create(recursive: true);
    await Directory(p.join(rootPath, '.termai', 'agent-results')).create(recursive: true);
  }

  Future<WorkspaceCheckpoint> checkpoint(String label) async {
    await initialize();
    final normalizedLabel = label.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final safeLabel = normalizedLabel.substring(0, normalizedLabel.length > 36 ? 36 : normalizedLabel.length);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final backup = Directory(p.join(rootPath, '.termai', 'checkpoints', '${stamp}_$safeLabel'));
    await backup.create(recursive: true);
    await _copyTree(root, backup, skipTermaiCheckpoints: true);
    return WorkspaceCheckpoint(directory: backup, createdAt: DateTime.now());
  }

  Map<String, String> validatePatches(List<dynamic> rawFiles) {
    if (rawFiles.length > 60) throw const FormatException('A task may write at most 60 files.');
    final patches = <String, String>{};
    var totalCharacters = 0;
    for (final item in rawFiles) {
      if (item is! Map) throw const FormatException('Every file patch must be an object.');
      final rawPath = item['path']?.toString() ?? '';
      final content = item['content'];
      if (!ApprovalPolicy.validRelativePath(rawPath)) throw FormatException('Rejected unsafe file path: $rawPath');
      if (content is! String) throw FormatException('File content must be text: $rawPath');
      final contentBytes = utf8.encode(content).length;
      if (contentBytes > 2 * 1024 * 1024) throw FormatException('File exceeds 2 MB limit: $rawPath');
      totalCharacters += contentBytes;
      if (totalCharacters > 8 * 1024 * 1024) throw const FormatException('A task may write at most 8 MB of text.');
      final relativePath = p.normalize(rawPath.replaceAll('\\', '/'));
      final destination = p.normalize(p.join(rootPath, relativePath));
      if (!p.isWithin(rootPath, destination)) throw FormatException('Path escaped workspace: $rawPath');
      patches[relativePath] = content;
    }
    return patches;
  }

  Future<List<String>> applyPatches(Map<String, String> patches) async {
    await initialize();
    final changed = <String>[];
    for (final entry in patches.entries) {
      if (!ApprovalPolicy.validRelativePath(entry.key)) {
        throw FormatException('Rejected unsafe file path: ${entry.key}');
      }
      final segments = entry.key.split('/');
      var cursor = rootPath;
      for (var index = 0; index < segments.length; index++) {
        cursor = p.join(cursor, segments[index]);
        final type = await FileSystemEntity.type(cursor, followLinks: false);
        if (type == FileSystemEntityType.link) {
          throw FormatException('Symlink paths are not writable by the agent: ${entry.key}');
        }
        if (index < segments.length - 1 && type != FileSystemEntityType.notFound && type != FileSystemEntityType.directory) {
          throw FormatException('A parent path is not a directory: $cursor');
        }
        if (index == segments.length - 1 && type == FileSystemEntityType.directory) {
          throw FormatException('A directory cannot be replaced with a file: $cursor');
        }
      }
      final file = File(cursor);
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.value, flush: true);
      changed.add(entry.key);
    }
    return changed;
  }

  /// Provides a bounded, secret-filtered snapshot so agents can reason about
  /// the existing project instead of generating files without repository context.
  Future<String> readContextSnapshot({int maxFiles = 32, int maxCharacters = 80000}) async {
    await initialize();
    const ignoredDirectories = {
      '.git', '.termai', '.dart_tool', '.gradle', '.idea', '.vscode',
      'build', 'node_modules', 'vendor', 'coverage', '.next', 'dist',
    };
    const ignoredExtensions = {
      '.pem', '.p12', '.pfx', '.jks', '.keystore', '.key',
      '.db', '.sqlite', '.sqlite3', '.der', '.cer', '.gpg', '.asc',
    };
    const ignoredNames = {'.npmrc', '.pypirc', '.netrc', '.git-credentials', 'google-services.json'};
    final secretName = RegExp(r'(^|[._-])(secret|secrets|credential|credentials|token|password|private|apikey|api_key|auth|service-account)([._-]|$)', caseSensitive: false);
    final candidates = <File>[];
    final pending = <Directory>[root];
    while (pending.isNotEmpty && candidates.length < maxFiles * 4) {
      final directory = pending.removeLast();
      final children = await directory.list(followLinks: false).toList();
      children.sort((a, b) => a.path.compareTo(b.path));
      for (final entity in children) {
        final name = p.basename(entity.path);
        if (entity is Directory) {
          if (!ignoredDirectories.contains(name) && pending.length < 128) pending.add(entity);
          continue;
        }
        if (entity is! File || name == '.env' || name.startsWith('.env.')) continue;
        final lower = name.toLowerCase();
        if (ignoredNames.contains(lower) || lower.startsWith('id_rsa') || lower.startsWith('id_ed25519')) continue;
        if (secretName.hasMatch(name) || ignoredExtensions.any(lower.endsWith)) continue;
        candidates.add(entity);
        if (candidates.length >= maxFiles * 4) break;
      }
    }
    candidates.sort((a, b) => a.path.compareTo(b.path));
    final output = StringBuffer('PROJECT FILE CONTEXT (secret-like files and generated folders excluded):\n');
    var included = 0;
    for (final file in candidates) {
      if (included >= maxFiles || output.length >= maxCharacters) break;
      final size = await file.length();
      if (size == 0 || size > 24000) continue;
      final bytes = await file.readAsBytes();
      if (bytes.contains(0)) continue;
      final content = utf8.decode(bytes, allowMalformed: true);
      final relative = p.relative(file.path, from: rootPath).replaceAll('\\', '/');
      final section = '\n--- FILE: $relative ---\n$content\n';
      if (output.length + section.length > maxCharacters) break;
      output.write(section);
      included++;
    }
    if (included == 0) output.write('(No readable source files found yet.)');
    return output.toString();
  }

  Future<bool> verifyFiles(List<String> paths) async {
    for (final path in paths) {
      if (!ApprovalPolicy.validRelativePath(path)) return false;
      final file = File(p.join(rootPath, path));
      if (await FileSystemEntity.type(file.path, followLinks: false) != FileSystemEntityType.file) return false;
      if (await file.length() > 2 * 1024 * 1024) return false;
    }
    return true;
  }

  /// Restores only the paths written by the failed task. If a user or another
  /// process changed a file after the agent wrote it, the file is left untouched.
  Future<void> rollbackPatches(WorkspaceCheckpoint checkpoint, Map<String, String> patches) async {
    for (final entry in patches.entries) {
      final relativePath = entry.key;
      if (!ApprovalPolicy.validRelativePath(relativePath)) continue;
      final current = File(p.join(rootPath, relativePath));
      if (await FileSystemEntity.type(current.path, followLinks: false) != FileSystemEntityType.file) continue;
      String currentContent;
      try { currentContent = await current.readAsString(); } catch (_) { continue; }
      if (currentContent != entry.value) continue;

      final saved = File(p.join(checkpoint.directory.path, relativePath));
      if (await saved.exists()) {
        await current.parent.create(recursive: true);
        await saved.copy(current.path);
      } else {
        await current.delete();
        var parent = current.parent;
        while (p.isWithin(rootPath, parent.path) && !p.equals(rootPath, parent.path)) {
          final remaining = await parent.list(followLinks: false).isEmpty;
          if (!remaining) break;
          await parent.delete();
          parent = parent.parent;
        }
      }
    }
  }

  Future<void> writeAgentNote(String id, String content) async {
    final normalizedId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final safeId = normalizedId.length > 64 ? normalizedId.substring(0, 64) : normalizedId;
    final fileName = '${safeId.isEmpty ? 'task' : safeId}.md';
    final file = File(p.join(rootPath, '.termai', 'agent-results', fileName));
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }

  Future<void> _copyTree(Directory source, Directory target, {required bool skipTermaiCheckpoints}) async {
    await target.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (skipTermaiCheckpoints && name == 'checkpoints' && p.basename(source.path) == '.termai') continue;
      final destination = p.join(target.path, name);
      if (entity is Directory) {
        await _copyTree(entity, Directory(destination), skipTermaiCheckpoints: skipTermaiCheckpoints);
      } else if (entity is File) {
        await entity.copy(destination);
      }
      // Symlinks are intentionally not followed or copied.
    }
  }
}
