import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termiai_nexus/core/nexus_feature_suite.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nexus-feature-suite-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('project analyzer identifies source files and ignores sensitive folders', () async {
    await Directory('${root.path}/lib').create(recursive: true);
    await Directory('${root.path}/secrets').create();
    await File('${root.path}/lib/main.dart').writeAsString('void main() {}');
    await File('${root.path}/secrets/private.dart').writeAsString('hidden');

    final analysis = await NexusProjectAnalyzer.analyze(root.path);

    expect(analysis.sourceFileCount, 1);
    expect(analysis.languages['Dart'], 1);
    expect(analysis.entryPoints, contains('lib/main.dart'));
    expect(analysis.entryPoints, isNot(contains('secrets/private.dart')));
  });

  test('dependency audit reads Flutter and Gradle dependency declarations', () async {
    await File('${root.path}/pubspec.yaml').writeAsString('''
name: sample
dependencies:
  http: ^1.0.0
  flutter:
    sdk: flutter
dev_dependencies:
  flutter_test:
    sdk: flutter
''');
    await Directory('${root.path}/android/app').create(recursive: true);
    await File('${root.path}/android/app/build.gradle.kts').writeAsString('''
dependencies {
  implementation("com.example:library:1.2.3")
}
''');

    final dependencies = await NexusDependencyManager.audit(root.path);

    expect(dependencies.any((item) => item.name == 'http'), isTrue);
    expect(dependencies.any((item) => item.name == 'com.example:library:1.2.3'), isTrue);
  });

  test('documentation generator writes a bounded factual project guide', () async {
    await Directory('${root.path}/lib').create(recursive: true);
    await File('${root.path}/lib/main.dart').writeAsString('void main() {}');

    final file = await NexusDocumentationGenerator.generate(
      root.path,
      projectName: 'Sample Project',
    );

    expect(await file.exists(), isTrue);
    final contents = await file.readAsString();
    expect(contents, contains('# دليل المشروع: Sample Project'));
    expect(contents, contains('lib/main.dart'));
    expect(contents, contains('لم يتم تشغيل الاختبارات'));
  });
}
