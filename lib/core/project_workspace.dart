import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'approval_policy.dart';

class WorkspaceCheckpoint {
  const WorkspaceCheckpoint({required this.directory, required this.createdAt});
  final Directory directory;
  final DateTime createdAt;
}

class WorkspaceRollbackReport {
  const WorkspaceRollbackReport({
    required this.restoredPaths,
    required this.preservedPaths,
    required this.failedPaths,
  });

  final List<String> restoredPaths;
  final List<String> preservedPaths;
  final List<String> failedPaths;
  bool get isComplete => failedPaths.isEmpty;
}

class WorkspaceApplyException implements Exception {
  const WorkspaceApplyException({required this.message, required this.rollbackFailedPaths});

  final String message;
  final List<String> rollbackFailedPaths;
  bool get rollbackComplete => rollbackFailedPaths.isEmpty;

  @override
  String toString() => message;
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
    if (rawFiles.isEmpty) throw const FormatException('A task must provide at least one file patch.');
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
      if (patches.containsKey(relativePath)) throw FormatException('Duplicate file patch path: $relativePath');
      patches[relativePath] = content;
    }
    return patches;
  }

  Future<List<String>> applyPatches(
    Map<String, String> patches, {
    WorkspaceCheckpoint? checkpoint,
  }) async {
    await initialize();
    if (patches.isEmpty) throw const FormatException('Empty patch sets cannot be applied.');
    final changed = <String>[];
    var index = 0;
    for (final entry in patches.entries) {
      if (!ApprovalPolicy.validRelativePath(entry.key)) {
        throw FormatException('Rejected unsafe file path: ${entry.key}');
      }
      final segments = entry.key.split('/');
      var cursor = rootPath;
      for (var segmentIndex = 0; segmentIndex < segments.length; segmentIndex++) {
        cursor = p.join(cursor, segments[segmentIndex]);
        final type = await FileSystemEntity.type(cursor, followLinks: false);
        if (type == FileSystemEntityType.link) {
          throw FormatException('Symlink paths are not writable by the agent: ${entry.key}');
        }
        if (segmentIndex < segments.length - 1 && type != FileSystemEntityType.notFound && type != FileSystemEntityType.directory) {
          throw FormatException('A parent path is not a directory: $cursor');
        }
        if (segmentIndex == segments.length - 1 && type == FileSystemEntityType.directory) {
          throw FormatException('A directory cannot be replaced with a file: $cursor');
        }
      }

      final file = File(cursor);
      final currentType = await FileSystemEntity.type(file.path, followLinks: false);
      if (checkpoint != null && !await _matchesCheckpoint(file, checkpoint, entry.key)) {
        throw StateError('Workspace conflict: ${entry.key} changed after the task checkpoint.');
      }
      if (currentType == FileSystemEntityType.file && await file.readAsString() == entry.value) {
        index++;
        continue;
      }
      if (currentType != FileSystemEntityType.file && currentType != FileSystemEntityType.notFound) {
        throw FormatException('Target is not a regular file: ${entry.key}');
      }

      await file.parent.create(recursive: true);
      final temporary = File(p.join(
        file.parent.path,
        '.${p.basename(file.path)}.termai-${DateTime.now().microsecondsSinceEpoch}-$index.tmp',
      ));
      try {
        await temporary.writeAsString(entry.value, flush: true);
        await temporary.rename(file.path);
        changed.add(entry.key);
      } catch (_) {
        if (await temporary.exists()) await temporary.delete();
        rethrow;
      }
      index++;
    }
    if (changed.isEmpty) {
      throw StateError('No file contents changed; an empty or no-op patch cannot complete a task.');
    }
    return changed;
  }

  Future<bool> _matchesCheckpoint(File current, WorkspaceCheckpoint checkpoint, String relativePath) async {
    final saved = File(p.join(checkpoint.directory.path, relativePath));
    final savedType = await FileSystemEntity.type(saved.path, followLinks: false);
    final currentType = await FileSystemEntity.type(current.path, followLinks: false);
    if (savedType == FileSystemEntityType.file) {
      return currentType == FileSystemEntityType.file && await _sameFileContents(current, saved);
    }
    return savedType == FileSystemEntityType.notFound && currentType == FileSystemEntityType.notFound;
  }

  Future<bool> _sameFileContents(File first, File second) async {
    final firstBytes = await first.readAsBytes();
    final secondBytes = await second.readAsBytes();
    if (firstBytes.length != secondBytes.length) return false;
    for (var i = 0; i < firstBytes.length; i++) {
      if (firstBytes[i] != secondBytes[i]) return false;
    }
    return true;
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

  Future<String> readTextFile(String relativePath) async {
    if (!ApprovalPolicy.validRelativePath(relativePath)) {
      throw FormatException('Rejected unsafe path: $relativePath');
    }
    final normalized = p.normalize(relativePath.replaceAll('\\', '/'));
    final target = p.normalize(p.join(rootPath, normalized));
    if (!p.isWithin(rootPath, target)) {
      throw FormatException('Path escaped workspace: $relativePath');
    }
    var cursor = rootPath;
    for (final segment in normalized.split('/')) {
      cursor = p.join(cursor, segment);
      if (await FileSystemEntity.type(cursor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw FormatException('Symlink access is forbidden: $relativePath');
      }
    }
    final file = File(target);
    if (await FileSystemEntity.type(target, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException('File not found or not regular', target);
    }
    if (await file.length() > 128 * 1024) {
      throw FormatException('File exceeds the 128 KB read limit');
    }
    final bytes = await file.readAsBytes();
    if (bytes.contains(0)) throw FormatException('Binary files are not readable');
    return utf8.decode(bytes);
  }

  Future<bool> verifyFiles(Map<String, String> expectedContents) async {
    if (expectedContents.isEmpty) return false;
    for (final entry in expectedContents.entries) {
      if (!ApprovalPolicy.validRelativePath(entry.key)) return false;
      final file = File(p.join(rootPath, entry.key));
      if (await FileSystemEntity.type(file.path, followLinks: false) != FileSystemEntityType.file) return false;
      if (await file.length() > 2 * 1024 * 1024) return false;
      if (await file.readAsString() != entry.value) return false;
    }
    return true;
  }

  /// Restores only the paths written by the failed task. If a user or another
  /// process changed a file after the agent wrote it, the file is left untouched.
  Future<WorkspaceRollbackReport> rollbackPatches(
    WorkspaceCheckpoint checkpoint,
    Map<String, String> patches,
  ) async {
    final restored = <String>[];
    final preserved = <String>[];
    final failed = <String>[];
    var index = 0;
    for (final entry in patches.entries) {
      final relativePath = entry.key;
      if (!ApprovalPolicy.validRelativePath(relativePath)) {
        failed.add(relativePath);
        continue;
      }
      final current = File(p.join(rootPath, relativePath));
      try {
        if (await FileSystemEntity.type(current.path, followLinks: false) != FileSystemEntityType.file) {
          preserved.add(relativePath);
          continue;
        }
        final currentContent = await current.readAsString();
        if (currentContent != entry.value) {
          preserved.add(relativePath);
          continue;
        }

        final saved = File(p.join(checkpoint.directory.path, relativePath));
        final savedType = await FileSystemEntity.type(saved.path, followLinks: false);
        if (savedType == FileSystemEntityType.file) {
          await current.parent.create(recursive: true);
          final temporary = File('${current.path}.termai-restore-${DateTime.now().microsecondsSinceEpoch}-$index.tmp');
          try {
            await saved.copy(temporary.path);
            if (await FileSystemEntity.type(current.path, followLinks: false) != FileSystemEntityType.file ||
                await current.readAsString() != entry.value) {
              if (await temporary.exists()) await temporary.delete();
              preserved.add(relativePath);
              continue;
            }
            await temporary.rename(current.path);
          } catch (_) {
            if (await temporary.exists()) await temporary.delete();
            rethrow;
          }
        } else if (savedType == FileSystemEntityType.notFound) {
          await current.delete();
          var parent = current.parent;
          while (p.isWithin(rootPath, parent.path) && !p.equals(rootPath, parent.path)) {
            final remaining = await parent.list(followLinks: false).isEmpty;
            if (!remaining) break;
            await parent.delete();
            parent = parent.parent;
          }
        } else {
          failed.add(relativePath);
          continue;
        }
        restored.add(relativePath);
      } catch (_) {
        failed.add(relativePath);
      }
      index++;
    }
    return WorkspaceRollbackReport(
      restoredPaths: restored,
      preservedPaths: preserved,
      failedPaths: failed,
    );
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
