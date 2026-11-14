import 'package:flutter/services.dart';

abstract interface class AgentCommandExecutor {
  Future<Map<String, dynamic>> run({
    required String workspacePath,
    required String command,
    required List<String> arguments,
    required String workingDirectory,
  });
}

class PlatformAgentCommandExecutor implements AgentCommandExecutor {
  const PlatformAgentCommandExecutor();

  static const MethodChannel _channel =
      MethodChannel('termai/agent-command');

  @override
  Future<Map<String, dynamic>> run({
    required String workspacePath,
    required String command,
    required List<String> arguments,
    required String workingDirectory,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'run',
      {
        'workspacePath': workspacePath,
        'command': command,
        'args': arguments,
        'workingDirectory': workingDirectory,
      },
    );
    if (result == null) {
      throw StateError('Native command runner returned no result.');
    }
    return result;
  }
}
