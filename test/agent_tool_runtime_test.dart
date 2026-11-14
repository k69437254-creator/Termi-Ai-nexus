import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

}
