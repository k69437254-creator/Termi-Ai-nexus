// TERMAI_GITHUB_AUTOMATION_UPDATE_20261116_V1
import 'dart:convert';
import 'dart:io';

import 'approval_policy.dart';
import 'agent_command_executor.dart';
import 'project_workspace.dart';

class AgentToolRuntime {
  AgentToolRuntime(
    this.workspace, {
    this.commandExecutor,
    this.stagingId,
    this.allowFileWrites = true,
  });

  final ProjectWorkspace workspace;
  final AgentCommandExecutor? commandExecutor;
  final String? stagingId;
  final bool allowFileWrites;
  final List<Map<String, dynamic>> _successfulValidationEvidence =
      <Map<String, dynamic>>[];
  final Set<String> _stagedPaths = <String>{};
  String? _lastToolName;

  bool get hasSuccessfulValidation => _successfulValidationEvidence.isNotEmpty;
  String? get lastToolName => _lastToolName;

  List<Map<String, dynamic>> get successfulValidationEvidence =>
      List.unmodifiable(
        _successfulValidationEvidence.map(
          (item) => Map<String, dynamic>.unmodifiable(item),
        ),
      );

  // Kept for existing callers while the coordinator moves to structured evidence.
  List<String> get successfulValidationCommands =>
      List.unmodifiable(
        _successfulValidationEvidence.map((item) {
          final args = (item['args'] as List).cast<String>();
          return '${item['command']} ${args.join(' ')} (exit ${item['exit_code']})'.trim();
        }),
      );

  List<String> get stagedPaths => List.unmodifiable(_stagedPaths);

  Future<Map<String, dynamic>> execute(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    _lastToolName = toolName;
    if (toolName == 'list_files') {
      final path = arguments['path'];
      if (path != null && path is! String) {
        return {'ok': false, 'error': 'Path must be text.'};
      }
      try {
        final entries = await workspace.listDirectory(path as String? ?? '');
        return {
          'ok': true,
          'path': path ?? '.',
          'entries': entries.take(200).toList(),
          'truncated': entries.length > 200,
        };
      } catch (error) {
        return {'ok': false, 'error': error.toString()};
      }
    }

    if (toolName == 'search_files') {
      final query = arguments['query'];
      final path = arguments['path'];
      if (query is! String || query.trim().isEmpty || query.length > 256) {
        return {'ok': false, 'error': 'Query must contain 1 to 256 characters.'};
      }
      if (path != null && path is! String) {
        return {'ok': false, 'error': 'Path must be text.'};
      }
      try {
        final result = await workspace.searchFiles(
          query,
          relativePath: path as String? ?? '',
        );
        return {'ok': true, 'query': query, 'path': path ?? '.', ...result};
      } catch (error) {
        return {'ok': false, 'error': error.toString()};
      }
    }

    if (toolName == 'inspect_project') {
      try {
        final root = Directory(workspace.rootPath);
        if (!await root.exists()) throw StateError('Workspace directory does not exist.');
        const ignored = {'.git', '.termai', '.dart_tool', '.gradle', 'build', 'node_modules', '.idea'};
        const sensitiveNames = {'.env', '.npmrc', '.netrc', '.git-credentials', 'google-services.json'};
        const sensitiveExtensions = {'.pem', '.p12', '.pfx', '.jks', '.keystore', '.key'};
        final secretPatterns = <RegExp>[
          RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
          RegExp(r'\bgh[pousr]_[A-Za-z0-9]{24,}\b'),
          RegExp(r'\bgithub_pat_[A-Za-z0-9_]{30,}\b'),
          RegExp(r'\bAKIA[0-9A-Z]{16}\b'),
          RegExp(r'(?im)^\s*(?:storePassword|keyPassword|signingPassword)\s*=\s*\S+'),
        ];
        final problems = <String>[];
        var visited = 0;
        await for (final entity in root.list(recursive: true, followLinks: false)) {
          final relative = entity.path.substring(root.path.length).replaceAll('\\', '/').replaceFirst(RegExp(r'^/'), '');
          final parts = relative.split('/');
          if (parts.any(ignored.contains)) continue;
          if (parts.any(ApprovalPolicy.isSensitivePathSegment)) {
            problems.add('Sensitive path must not be published: $relative');
            continue;
          }
          if (await FileSystemEntity.type(entity.path, followLinks: false) == FileSystemEntityType.link) {
            problems.add('Symlink found: $relative');
            continue;
          }
          if (entity is File) {
            if (visited >= 2500) {
              problems.add('Workspace exceeds the 2500-file inspection limit.');
              break;
            }
            visited++;
            final name = parts.last.toLowerCase();
            final extension = name.contains('.') ? name.substring(name.lastIndexOf('.')) : '';
            if (sensitiveNames.contains(name) || ApprovalPolicy.isSensitivePathSegment(name) || sensitiveExtensions.contains(extension) || (name.startsWith('.env.') && !const {'.env.example', '.env.sample', '.env.template'}.contains(name))) {
              problems.add('Sensitive file must not be published: $relative');
            }
            final fileSize = await entity.length();
            if (fileSize <= 2 * 1024 * 1024) {
              final bytes = await entity.readAsBytes();
              if (!bytes.contains(0)) {
                final text = utf8.decode(bytes, allowMalformed: true);
                if (secretPatterns.any((pattern) => pattern.hasMatch(text))) {
                  problems.add('Embedded credential pattern found: $relative');
                }
              }
            }
          }
        }
        final flutter = await File('${root.path}/pubspec.yaml').exists();
        final androidSettings = await File('${root.path}/android/settings.gradle').exists() ||
            await File('${root.path}/android/settings.gradle.kts').exists() ||
            await File('${root.path}/settings.gradle').exists() ||
            await File('${root.path}/settings.gradle.kts').exists();
        final flutterEntry = await File('${root.path}/lib/main.dart').exists();
        final wrapperRoot = '${root.path}/android/gradle/wrapper';
        final wrapperPlain = '${root.path}/gradle/wrapper';
        final wrapperJar = await File('$wrapperRoot/gradle-wrapper.jar').exists() ||
            await File('$wrapperPlain/gradle-wrapper.jar').exists();
        final wrapperProperties = await File('$wrapperRoot/gradle-wrapper.properties').exists() ||
            await File('$wrapperPlain/gradle-wrapper.properties').exists();
        final gradleApp = await File('${root.path}/android/app/build.gradle').exists() ||
            await File('${root.path}/android/app/build.gradle.kts').exists() ||
            await File('${root.path}/app/build.gradle').exists() ||
            await File('${root.path}/app/build.gradle.kts').exists();
        final gradleWrapper = await File('${root.path}/android/gradlew').exists() || await File('${root.path}/gradlew').exists();
        final supportedFlutter = flutter && flutterEntry && androidSettings && gradleApp && gradleWrapper && wrapperJar && wrapperProperties;
        final supportedAndroid = !flutter && androidSettings && gradleApp && gradleWrapper && wrapperJar && wrapperProperties;
        if (!supportedFlutter && !supportedAndroid) {
          problems.add('Android build structure is incomplete: expected Flutter pubspec/lib/main.dart or Android Gradle app, plus settings, wrapper JAR and wrapper properties.');
        }
        if (problems.isNotEmpty) throw StateError(problems.join('\n'));
        final summary = 'PASS: ${supportedFlutter ? 'Flutter Android' : 'Android Gradle'} project structure. Inspected $visited files; required Android build files exist; no blocked paths or known embedded credential patterns were found. Full tests and APK compilation will run in GitHub Actions.';
        _successfulValidationEvidence.add({
          'command': 'workspace_inspection',
          'args': <String>[],
          'exit_code': 0,
          'timed_out': false,
          'truncated': false,
          'output': summary,
        });
        return {'ok': true, 'projectType': supportedFlutter ? 'flutter' : 'android-gradle', 'filesInspected': visited, 'output': summary};
      } catch (error) {
        return {'ok': false, 'error': error.toString()};
      }
    }


    if (toolName == 'write_file_chunk') {
      if (!allowFileWrites) {
        return {
          'ok': false,
          'error': 'File writes are disabled for this agent role.',
        };
      }
      final id = stagingId;
      final path = arguments['path'];
      final content = arguments['content'];
      final mode = arguments['mode'] ?? 'create';
      if (id == null || id.isEmpty) {
        return {'ok': false, 'error': 'File staging is unavailable for this task.'};
      }
      if (path is! String || content is! String ||
          (mode != 'create' && mode != 'append')) {
        return {'ok': false, 'error': 'write_file_chunk expects path, text content, and create/append mode.'};
      }
      try {
        final result = await workspace.stageFileChunk(
          id,
          path,
          content,
          append: mode == 'append',
        );
        _stagedPaths.add(path);
        _successfulValidationEvidence.clear();
        return {
          'ok': true,
          'path': path,
          ...result,
          'stagedManifest': stagedPaths,
        };
      } catch (error) {
        return {'ok': false, 'error': error.toString()};
      }
    }

    if (toolName == 'run_command') {
      // Every command attempt invalidates earlier evidence, including rejected commands.
      _successfulValidationEvidence.clear();
      final executor = commandExecutor;
      if (executor == null) {
        return {'ok': false, 'error': 'Ubuntu/PRoot command execution is unavailable.'};
      }
      const allowed = {
        'pwd', 'ls', 'find', 'grep', 'rg', 'cat', 'sed', 'awk', 'wc',
        'head', 'tail', 'stat', 'git', 'gh', 'curl', 'python3', 'python', 'pip3',
        'node', 'npm', 'npx', 'java', 'javac', 'gradle', 'mvn', 'pytest',
        'cmake', 'make', 'gcc', 'g++', 'cargo', 'rustc', 'dart', 'flutter',
        'apt-get', 'bash', 'sh', 'tar', 'unzip', 'zip',
      };
      final command = arguments['command'];
      final rawArgs = arguments['args'] ?? const [];
      final cwd = arguments['workingDirectory'] ?? '.';
      if (command is! String || !allowed.contains(command)) {
        return {'ok': false, 'error': 'Command is not on the isolated Ubuntu allowlist.'};
      }
      if (rawArgs is! List ||
          rawArgs.length > 64 ||
          rawArgs.any((value) => value is! String)) {
        return {'ok': false, 'error': 'Invalid command arguments (maximum 64 text arguments).'};
      }
      final args = List<String>.from(rawArgs);
      if (args.fold<int>(0, (sum, item) => sum + item.length) > 32768 ||
          args.any((item) => item.contains('\u0000'))) {
        return {'ok': false, 'error': 'Command arguments exceed the safe size limit.'};
      }
      if (cwd is! String || cwd.trim().isEmpty) {
        return {'ok': false, 'error': 'Invalid working directory.'};
      }
      if (command == 'git' && args.isNotEmpty && const {
        'push', 'commit', 'reset', 'clean', 'checkout', 'switch', 'rebase',
        'merge', 'cherry-pick', 'config', 'submodule',
      }.contains(args.first)) {
        return {'ok': false, 'error': 'Git write/remote operations require a separate explicit approval and are not available to autonomous tasks.'};
      }
      if (command == 'gh' && args.isNotEmpty && !const {
        'repo', 'pr', 'issue', 'run', 'auth',
      }.contains(args.first)) {
        return {'ok': false, 'error': 'GitHub write operation is not permitted in autonomous execution.'};
      }
      if (command == 'apt-get' && args.isNotEmpty &&
          !const {'update', 'install', 'download', 'show', 'list'}.contains(args.first)) {
        return {'ok': false, 'error': 'Only package-index refresh and package installation/inspection are allowed inside the guest.'};
      }
      if ((command == 'bash' || command == 'sh') &&
          (args.isEmpty || args.first.startsWith('-'))) {
        return {'ok': false, 'error': 'Shell command strings are forbidden. Run a workspace script by path; do not use -c or -lc.'};
      }
      try {
        final result = await executor.run(
          workspacePath: workspace.rootPath,
          command: command,
          arguments: args,
          workingDirectory: cwd,
        );
        final safeResult = Map<String, dynamic>.from(result);
        final originalOutput = safeResult['output'];
        var runtimeTruncated = false;
        if (originalOutput is String && originalOutput.length > 12000) {
          safeResult['output'] =
              '${originalOutput.substring(0, 4000)}\n[output truncated by agent runtime]';
          safeResult['outputTruncated'] = true;
          runtimeTruncated = true;
        }

        final exitCode = result['exit_code'];
        final timedOut = result['timed_out'];
        final isRealSuccess = result['ok'] == true &&
            exitCode is int &&
            exitCode == 0 &&
            timedOut == false;
        if (isRealSuccess && _isValidationCommand(command, args)) {
          final output = safeResult['output'];
          final outputText = output is String ? output : '';
          _successfulValidationEvidence.add({
            'command': command,
            'args': List<String>.unmodifiable(args),
            'exit_code': exitCode,
            'timed_out': timedOut,
            'truncated': result['truncated'] == true || runtimeTruncated,
            'output': outputText.length > 4000
                ? outputText.substring(0, 4000)
                : outputText,
          });
        }
        return safeResult;
      } catch (error) {
        return {'ok': false, 'error': error.toString()};
      }
    }

    if (toolName != 'read_file') {
      return {'ok': false, 'error': 'Unknown tool: $toolName'};
    }

    final path = arguments['path'];
    if (path is! String || path.trim().isEmpty) {
      return {'ok': false, 'error': 'A non-empty path is required.'};
    }

    try {
      final content = await workspace.readTextFile(path);
      const limit = 8000;
      return {
        'ok': true,
        'path': path,
        'content': content.length > limit
            ? content.substring(0, limit)
            : content,
        'truncated': content.length > limit,
      };
    } catch (error) {
      return {'ok': false, 'error': error.toString()};
    }
  }

  bool _isValidationCommand(String command, List<String> args) {
    final tokens = args.map((item) => item.toLowerCase()).toList();

    if (command == 'flutter') {
      return tokens.isNotEmpty &&
          const {'test', 'analyze', 'build'}.contains(tokens.first);
    }
    if (command == 'dart') {
      return tokens.isNotEmpty &&
          const {'test', 'analyze', 'compile'}.contains(tokens.first);
    }
    if (command == 'npm') {
      if (tokens.isEmpty) return false;
      if (tokens.first == 'test') return true;
      return tokens.length >= 2 &&
          tokens[0] == 'run' &&
          const {'test', 'build', 'lint', 'check'}.contains(tokens[1]);
    }
    if (command == 'pytest') return true;
    if (command == 'python' || command == 'python3') {
      return tokens.length >= 2 &&
          tokens[0] == '-m' &&
          const {'pytest', 'unittest', 'compileall'}.contains(tokens[1]);
    }
    if (command == 'gradle') {
      return _containsValidationTask(
        args,
        const {'test', 'check', 'build', 'assemble', 'verify'},
        const {
          '-p', '--project-dir', '-b', '--build-file', '-c',
          '--settings-file', '--init-script', '-I',
        },
      );
    }
    if (command == 'mvn') {
      return _containsValidationTask(
        args,
        const {
          'test', 'check', 'package', 'verify',
          'install', 'integration-test',
        },
        const {'-f', '-s', '-gs', '-pl', '-rf', '-l', '-t', '-gt', '-D'},
      );
    }
    if (command == 'make') {
      return _containsValidationTask(
        args,
        const {'test', 'check', 'verify'},
        const {
          '-C', '--directory', '-f', '--file', '-I', '--include-dir',
        },
      );
    }
    // Shell scripts are deliberately never accepted as validation evidence.
    return false;
  }

  bool _containsValidationTask(
    List<String> args,
    Set<String> validationTasks,
    Set<String> optionsWithValues,
  ) {
    for (var index = 0; index < args.length; index++) {
      final token = args[index];
      if (token.startsWith('-')) {
        if (!token.contains('=') && optionsWithValues.contains(token)) {
          index++;
        }
        continue;
      }
      if (validationTasks.contains(token.toLowerCase())) return true;
    }
    return false;
  }
}
