import 'agent_command_executor.dart';
import 'project_workspace.dart';

class AgentToolRuntime {
  AgentToolRuntime(this.workspace, {this.commandExecutor});

  final ProjectWorkspace workspace;
  final AgentCommandExecutor? commandExecutor;

  Future<Map<String, dynamic>> execute(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
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

    if (toolName == 'run_command') {
      final executor = commandExecutor;
      if (executor == null) {
        return {'ok': false, 'error': 'Command execution is unavailable.'};
      }
      const allowed = {
        'pwd', 'ls', 'grep', 'wc', 'head',
        'tail', 'stat', 'uname', 'id',
      };
      final command = arguments['command'];
      final rawArgs = arguments['args'] ?? const [];
      final cwd = arguments['workingDirectory'] ?? '.';
      if (command is! String || !allowed.contains(command)) {
        return {'ok': false, 'error': 'Command is not allowed.'};
      }
      if (rawArgs is! List ||
          rawArgs.length > 2 ||
          rawArgs.any((value) => value is! String)) {
        return {'ok': false, 'error': 'Invalid command arguments.'};
      }
      if (cwd is! String || cwd.trim().isEmpty) {
        return {'ok': false, 'error': 'Invalid working directory.'};
      }
      try {
        return await executor.run(
          workspacePath: workspace.rootPath,
          command: command,
          arguments: List<String>.from(rawArgs),
          workingDirectory: cwd,
        );
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
      const limit = 16000;
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
}
