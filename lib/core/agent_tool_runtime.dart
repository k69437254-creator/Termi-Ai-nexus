import 'project_workspace.dart';

class AgentToolRuntime {
  AgentToolRuntime(this.workspace);

  final ProjectWorkspace workspace;

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
