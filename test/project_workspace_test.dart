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

  test('rejects empty, duplicate, outside and internal file patches', () {
    expect(() => workspace.validatePatches([]), throwsFormatException);
    expect(
      () => workspace.validatePatches([
        {'path': 'lib/a.dart', 'content': 'one'},
        {'path': 'lib/a.dart', 'content': 'two'},
      ]),
      throwsFormatException,
    );
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

  test('requires a real file change and verifies complete expected contents', () async {
    final file = File('${temporaryRoot.path}/lib/example.dart');
    await file.parent.create(recursive: true);
    await file.writeAsString('same content');

    final checkpoint = await workspace.checkpoint('real_change');
    await expectLater(
      workspace.applyPatches({'lib/example.dart': 'same content'}, checkpoint: checkpoint),
      throwsStateError,
    );

    final changed = await workspace.applyPatches(
      {'lib/example.dart': 'updated content'},
      checkpoint: checkpoint,
    );
    expect(changed, ['lib/example.dart']);
    expect(await workspace.verifyFiles({'lib/example.dart': 'updated content'}), isTrue);
    expect(await workspace.verifyFiles({'lib/example.dart': 'different expected content'}), isFalse);
  });

  test('rejects writes when a file changed after the task checkpoint', () async {
    final file = File('${temporaryRoot.path}/README.md');
    await file.writeAsString('checkpoint version');
    final checkpoint = await workspace.checkpoint('concurrent_edit');
    await file.writeAsString('user concurrent edit');

    await expectLater(
      workspace.applyPatches(
        {'README.md': 'agent version'},
        checkpoint: checkpoint,
      ),
      throwsStateError,
    );
    expect(await file.readAsString(), 'user concurrent edit');
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


  test('verification rejects symbolic-link parents', () async {
    final outside = await Directory.systemTemp.createTemp('termai-outside-');
    addTearDown(() async {
      if (await outside.exists()) await outside.delete(recursive: true);
    });
    await File('${outside.path}/sentinel.txt').writeAsString('outside');
    final link = Link('${temporaryRoot.path}/linked');
    await link.create(outside.path);

    expect(
      await workspace.verifyFiles({'linked/sentinel.txt': 'outside'}),
      isFalse,
    );
  });

  test('blocks nested sensitive directories from reads, search, listing and patches', () async {
    final secretDirectory = Directory('${temporaryRoot.path}/secrets');
    await secretDirectory.create();
    await File('${secretDirectory.path}/ordinary-name.txt')
        .writeAsString('NEXUS_PRIVATE_SENTINEL');

    expect(
      () => workspace.validatePatches([
        {'path': 'secrets/ordinary-name.txt', 'content': 'overwrite'},
      ]),
      throwsFormatException,
    );
    await expectLater(
      workspace.readTextFile('secrets/ordinary-name.txt'),
      throwsFormatException,
    );

    final context = await workspace.readContextSnapshot();
    expect(context, isNot(contains('NEXUS_PRIVATE_SENTINEL')));

    final listed = await workspace.listDirectory('');
    expect(listed.any((entry) => entry['name'] == 'secrets'), isFalse);

    final searched = await workspace.searchFiles('NEXUS_PRIVATE_SENTINEL');
    expect(searched['results'], isEmpty);
  });

  test('checkpoints exclude VCS metadata and sensitive folders', () async {
    await Directory('${temporaryRoot.path}/.git').create();
    await File('${temporaryRoot.path}/.git/config')
        .writeAsString('GIT_PRIVATE_SENTINEL');
    await Directory('${temporaryRoot.path}/credentials').create();
    await File('${temporaryRoot.path}/credentials/ordinary.txt')
        .writeAsString('CREDENTIAL_PRIVATE_SENTINEL');

    final checkpoint = await workspace.checkpoint('sensitive_exclusion');
    expect(
      await File('${checkpoint.directory.path}/.git/config').exists(),
      isFalse,
    );
    expect(
      await File('${checkpoint.directory.path}/credentials/ordinary.txt').exists(),
      isFalse,
    );
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
    await workspace.applyPatches(patches, checkpoint: checkpoint);
    await original.writeAsString('user edit after agent');
    final rollback = await workspace.rollbackPatches(checkpoint, patches);

    expect(rollback.isComplete, isTrue);
    expect(rollback.preservedPaths, contains('lib/example.dart'));
    expect(rollback.restoredPaths, contains('lib/new.dart'));
    expect(await original.readAsString(), 'user edit after agent');
    expect(await File('${temporaryRoot.path}/lib/new.dart').exists(), isFalse);
  });
}
