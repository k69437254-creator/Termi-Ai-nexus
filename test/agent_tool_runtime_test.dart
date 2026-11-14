import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termiai_nexus/core/agent_command_executor.dart';
import 'package:termiai_nexus/core/agent_tool_runtime.dart';
import 'package:termiai_nexus/core/project_workspace.dart';

void main() {
  late Directory root;
  late AgentToolRuntime runtime;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('termai-tools-');
    final workspace = ProjectWorkspace(root.path);
    await workspace.initialize();
    runtime = AgentToolRuntime(workspace);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('reads a real workspace file', () async {
    await File('${root.path}/README.md').writeAsString('real content');
    final result = await runtime.execute('read_file', {'path': 'README.md'});
    expect(result['ok'], isTrue);
    expect(result['content'], 'real content');
  });

  test('rejects paths outside the workspace', () async {
    final result = await runtime.execute('read_file', {'path': '../outside.txt'});
    expect(result['ok'], isFalse);
  });

  test('rejects unknown tools', () async {
    final result = await runtime.execute('delete_file', {'path': 'README.md'});
    expect(result['ok'], isFalse);
  });

  test('rejects missing path arguments', () async {
    final result = await runtime.execute('read_file', {});
    expect(result['ok'], isFalse);
  });

  test('blocks reading sensitive environment files', () async {
    await File('${root.path}/.env').writeAsString('API_KEY=private-value');
    final result = await runtime.execute('read_file', {'path': '.env'});
    expect(result['ok'], isFalse);
  });

  test('rejects binary files', () async {
    await File('${root.path}/binary.bin').writeAsBytes([0, 1, 2, 0]);
    final result = await runtime.execute('read_file', {'path': 'binary.bin'});
    expect(result['ok'], isFalse);
  });

  test('truncates large tool responses', () async {
    await File('${root.path}/large.txt').writeAsString('x' * 17000);
    final result = await runtime.execute('read_file', {'path': 'large.txt'});
    expect(result['ok'], isTrue);
    expect(result['truncated'], isTrue);
    expect((result['content'] as String).length, 16000);
  });


  test('lists real files and directories in the workspace', () async {
    await File('${root.path}/README.md').writeAsString('content');
    await Directory('${root.path}/lib').create();
    final result = await runtime.execute('list_files', {});
    expect(result['ok'], isTrue);
    final entries = result['entries'] as List;
    expect(entries.any((e) => e['name'] == 'README.md' && e['type'] == 'file'), isTrue);
    expect(entries.any((e) => e['name'] == 'lib' && e['type'] == 'directory'), isTrue);
    expect(entries.any((e) => e['name'] == '.termai'), isFalse);
  });

  test('rejects directory traversal in list_files', () async {
    final result = await runtime.execute('list_files', {'path': '../'});
    expect(result['ok'], isFalse);
  });

  test('rejects non-text list_files paths', () async {
    final result = await runtime.execute('list_files', {'path': 42});
    expect(result['ok'], isFalse);
  });

  test('searches project files and returns matching line numbers', () async {
    await Directory('${root.path}/lib').create();
    await File('${root.path}/lib/sample.dart')
        .writeAsString('first line\nTargetNeedle appears here\nthird line');
    final result = await runtime.execute(
      'search_files',
      {'query': 'targetneedle', 'path': 'lib'},
    );
    expect(result['ok'], isTrue);
    final matches = result['results'] as List;
    expect(
      matches.any((e) =>
          e['path'] == 'lib/sample.dart' &&
          e['line'] == 2 &&
          (e['snippet'] as String).contains('TargetNeedle')),
      isTrue,
    );
  });

  test('does not expose secret assignment lines in search results', () async {
    await File('${root.path}/config.txt').writeAsString(
      'API_KEY=super-secret-value\nordinary matching text',
    );
    final result = await runtime.execute(
      'search_files',
      {'query': 'super-secret-value'},
    );
    expect(result['ok'], isTrue);
    expect(result['results'], isEmpty);
  });

  test('rejects search paths outside the workspace', () async {
    final result = await runtime.execute(
      'search_files',
      {'query': 'needle', 'path': '../'},
    );
    expect(result['ok'], isFalse);
  });

  test('rejects empty or non-text search queries', () async {
    final empty = await runtime.execute('search_files', {'query': ' '});
    final invalid = await runtime.execute('search_files', {'query': 42});
    expect(empty['ok'], isFalse);
    expect(invalid['ok'], isFalse);
  });


  test('passes an allowlisted command to the executor', () async {
    final fake = _FakeAgentCommandExecutor();
    final subject = AgentToolRuntime(
      ProjectWorkspace(root.path),
      commandExecutor: fake,
    );
    final result = await subject.execute('run_command', {
      'command': 'ls',
      'args': ['lib'],
    });
    expect(result['ok'], isTrue);
    expect(fake.calls, 1);
    expect(fake.lastWorkspacePath, root.path);
    expect(fake.lastCommand, 'ls');
    expect(fake.lastArguments, ['lib']);
    expect(fake.lastWorkingDirectory, '.');
  });

  test('rejects disallowed commands before executor call', () async {
    final fake = _FakeAgentCommandExecutor();
    final subject = AgentToolRuntime(
      ProjectWorkspace(root.path),
      commandExecutor: fake,
    );
    final result = await subject.execute('run_command', {
      'command': 'rm',
      'args': ['-rf', '.'],
    });
    expect(result['ok'], isFalse);
    expect(fake.calls, 0);
  });

  test('rejects non-text command arguments before executor call', () async {
    final fake = _FakeAgentCommandExecutor();
    final subject = AgentToolRuntime(
      ProjectWorkspace(root.path),
      commandExecutor: fake,
    );
    final result = await subject.execute('run_command', {
      'command': 'ls',
      'args': ['lib', 42],
    });
    expect(result['ok'], isFalse);
    expect(fake.calls, 0);
  });
}

class _FakeAgentCommandExecutor implements AgentCommandExecutor {
  int calls = 0;
  String? lastWorkspacePath;
  String? lastCommand;
  List<String>? lastArguments;
  String? lastWorkingDirectory;

  @override
  Future<Map<String, dynamic>> run({
    required String workspacePath,
    required String command,
    required List<String> arguments,
    required String workingDirectory,
  }) async {
    calls++;
    lastWorkspacePath = workspacePath;
    lastCommand = command;
    lastArguments = arguments;
    lastWorkingDirectory = workingDirectory;
    return {'ok': true, 'output': 'fake output'};
  }
}
