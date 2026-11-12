import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termiai_nexus/core/project_workspace.dart';

void main() {
  late Directory temporaryRoot;
  late ProjectWorkspace workspace;

  setUp(() async {
    temporaryRoot = await Directory.systemTemp.createTemp('termai-workspace-test-');
    workspace = ProjectWorkspace(temporaryRoot.path);
    await workspace.initialize();
  });

  tearDown(() async {
    if (await temporaryRoot.exists()) {
      await temporaryRoot.delete(recursive: true);
    }
  });

  test('rejects paths outside the workspace and internal metadata paths', () {
    expect(
      () => workspace.validatePatches([
        {'path': '../outside.txt', 'content': 'no'},
      ]),
      throwsFormatException,
    );
    expect(
      () => workspace.validatePatches([
        {'path': '.termai/notes.txt', 'content': 'no'},
      ]),
      throwsFormatException,
    );
  });

  test('creates a bounded context snapshot while skipping common secrets', () async {
    await File('${temporaryRoot.path}/README.md').writeAsString('# Project');
    await File('${temporaryRoot.path}/.env').writeAsString('SECRET=hidden');
    await File('${temporaryRoot.path}/credentials.json').writeAsString('{"token":"hidden"}');
    await Directory('${temporaryRoot.path}/.git').create();
    await File('${temporaryRoot.path}/.git/config').writeAsString('private');

    final context = await workspace.readContextSnapshot();
    expect(context, contains('README.md'));
    expect(context, isNot(contains('SECRET=hidden')));
    expect(context, isNot(contains('credentials.json')));
    expect(context, isNot(contains('.git/config')));
  });

  test('rolls back only agent-written files and preserves later user edits', () async {
    final original = File('${temporaryRoot.path}/lib/example.dart');
    await original.parent.create(recursive: true);
    await original.writeAsString('original');
    final checkpoint = await workspace.checkpoint('unit_test');

    final patches = workspace.validatePatches([
      {'path': 'lib/example.dart', 'content': 'agent version'},
      {'path': 'lib/new.dart', 'content': 'agent created'},
    ]);
    await workspace.applyPatches(patches);
    await original.writeAsString('user edit after agent');
    await workspace.rollbackPatches(checkpoint, patches);

    expect(await original.readAsString(), 'user edit after agent');
    expect(await File('${temporaryRoot.path}/lib/new.dart').exists(), isFalse);
  });
}
