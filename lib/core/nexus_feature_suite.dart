import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'approval_policy.dart';

class NexusProjectAnalysis {
  const NexusProjectAnalysis({
    required this.rootPath,
    required this.fileCount,
    required this.sourceFileCount,
    required this.languages,
    required this.entryPoints,
  });

  final String rootPath;
  final int fileCount;
  final int sourceFileCount;
  final Map<String, int> languages;
  final List<String> entryPoints;

  String get primaryLanguage => languages.isEmpty
      ? 'غير محدد'
      : languages.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

class NexusProjectAnalyzer {
  static const _ignoredDirectories = {
    '.git', '.termai', '.dart_tool', '.gradle', '.idea', '.vscode',
    'build', 'node_modules', 'vendor', 'coverage', '.next', 'dist',
  };

  static const _extensions = <String, String>{
    '.dart': 'Dart', '.kt': 'Kotlin', '.kts': 'Kotlin DSL',
    '.java': 'Java', '.c': 'C', '.h': 'C/C++', '.cpp': 'C++',
    '.py': 'Python', '.js': 'JavaScript', '.ts': 'TypeScript',
    '.html': 'HTML', '.css': 'CSS', '.xml': 'XML', '.yaml': 'YAML',
    '.yml': 'YAML', '.gradle': 'Gradle', '.md': 'Markdown',
  };

  static Future<NexusProjectAnalysis> analyze(String rootPath) async {
    final root = Directory(rootPath).absolute;
    if (!await root.exists()) throw StateError('مساحة المشروع غير موجودة.');
    final canonicalRoot = await root.resolveSymbolicLinks();
    final counts = <String, int>{};
    final entries = <String>[];
    var total = 0;
    var source = 0;

    final pending = <Directory>[root];
    while (pending.isNotEmpty && total < 5000) {
      final directory = pending.removeLast();
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is Link) continue;
        final relative = p.relative(entity.path, from: rootPath).replaceAll('\\', '/');
        final segments = relative.split('/');
        if (segments.any(ApprovalPolicy.isSensitivePathSegment)) continue;
        if (entity is Directory) {
          if (!_ignoredDirectories.contains(p.basename(entity.path)) && pending.length < 256) {
            pending.add(entity);
          }
          continue;
        }
        if (entity is! File || segments.any(_ignoredDirectories.contains)) continue;
        total++;
        final extension = p.extension(entity.path).toLowerCase();
        final language = _extensions[extension];
        if (language == null) continue;
        counts[language] = (counts[language] ?? 0) + 1;
        if (language != 'Markdown' && language != 'YAML' && language != 'XML') {
          source++;
        }
        if (entries.length < 80 && _isEntryPoint(relative)) entries.add(relative);
        if (total >= 5000) break;
      }
    }

    return NexusProjectAnalysis(
      rootPath: canonicalRoot,
      fileCount: total,
      sourceFileCount: source,
      languages: Map.unmodifiable(counts),
      entryPoints: List.unmodifiable(entries),
    );
  }

  static bool _isEntryPoint(String path) {
    final normalized = path.toLowerCase();
    return normalized == 'lib/main.dart' ||
        normalized == 'main.dart' ||
        normalized == 'src/main.kt' ||
        normalized.endsWith('/mainactivity.kt') ||
        normalized == 'index.html' ||
        normalized == 'src/index.ts' ||
        normalized == 'src/index.js' ||
        normalized == 'package.json' ||
        normalized == 'pubspec.yaml' ||
        normalized == 'readme.md';
  }
}

class NexusDependency {
  const NexusDependency({required this.name, required this.version, required this.source});
  final String name;
  final String version;
  final String source;
}

class NexusDependencyManager {
  static Future<List<NexusDependency>> audit(String rootPath) async {
    final root = Directory(rootPath);
    if (!await root.exists()) throw StateError('مساحة المشروع غير موجودة.');
    final result = <NexusDependency>[];
    final pubspec = File(p.join(rootPath, 'pubspec.yaml'));
    if (await pubspec.exists()) {
      var section = '';
      for (final line in await pubspec.readAsLines()) {
        if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
        if (!line.startsWith(' ') && line.endsWith(':')) {
          section = line.substring(0, line.length - 1).trim();
          continue;
        }
        if (section != 'dependencies' && section != 'dev_dependencies' && section != 'dependency_overrides') continue;
        final match = RegExp(r'^\s{2}([A-Za-z0-9_]+):\s*(.*?)\s*$').firstMatch(line);
        if (match == null) continue;
        final name = match.group(1)!;
        final version = match.group(2) ?? '';
        if (version.startsWith('sdk:')) continue;
        result.add(NexusDependency(name: name, version: version.isEmpty ? 'غير محدد' : version, source: 'pubspec:$section'));
      }
    }

    for (final gradlePath in const ['android/app/build.gradle', 'android/app/build.gradle.kts', 'android/build.gradle', 'android/build.gradle.kts']) {
      final file = File(p.join(rootPath, gradlePath));
      if (!await file.exists()) continue;
      final text = await file.readAsString();
      final pattern = RegExp(r'''(?:implementation|api|compileOnly|runtimeOnly|testImplementation)\s*\(?\s*["']([^"']+)["']''');
      for (final match in pattern.allMatches(text)) {
        final coordinate = match.group(1)!;
        result.add(NexusDependency(name: coordinate, version: 'حسب Gradle', source: gradlePath));
      }
    }

    final seen = <String>{};
    return result.where((item) => seen.add('${item.source}|${item.name}')).toList(growable: false);
  }

  static Future<File> writeAuditReport(String rootPath) async {
    final dependencies = await audit(rootPath);
    final lockExists = await File(p.join(rootPath, 'pubspec.lock')).exists();
    final report = StringBuffer('# تقرير الاعتماديات\n\n')
      ..writeln('تم إنشاء التقرير: ${DateTime.now().toUtc().toIso8601String()}')
      ..writeln('\nعدد الإدخالات المكتشفة: ${dependencies.length}')
      ..writeln('ملف pubspec.lock: ${lockExists ? 'موجود' : 'غير موجود'}')
      ..writeln('\n| المصدر | الاعتمادية | الإصدار/القيد |')
      ..writeln('|---|---|---|');
    for (final item in dependencies) {
      report.writeln('| ${_escape(item.source)} | ${_escape(item.name)} | ${_escape(item.version)} |');
    }
    if (!lockExists && await File(p.join(rootPath, 'pubspec.yaml')).exists()) {
      report.writeln('\n> تنبيه: لا يوجد pubspec.lock؛ لم يتم تنفيذ pub get أو تغيير أي إصدار.');
    }
    final output = File(p.join(rootPath, 'docs', 'DEPENDENCY_AUDIT.md'));
    await output.parent.create(recursive: true);
    await output.writeAsString(report.toString(), flush: true);
    return output;
  }

  static String _escape(String value) => value.replaceAll('|', '\\|').replaceAll('\n', ' ');
}

class NexusDocumentationGenerator {
  static Future<File> generate(String rootPath, {String projectName = 'Project'}) async {
    final analysis = await NexusProjectAnalyzer.analyze(rootPath);
    final dependencies = await NexusDependencyManager.audit(rootPath);
    final report = StringBuffer()
      ..writeln('# دليل المشروع: $projectName')
      ..writeln('\n> أُنشئ تلقائياً من ملفات مساحة العمل. راجع الدليل بعد التغييرات المعمارية الكبيرة.')
      ..writeln('\n## نظرة عامة')
      ..writeln('- المسار: `${analysis.rootPath}`')
      ..writeln('- الملفات المفحوصة: ${analysis.fileCount}')
      ..writeln('- ملفات المصدر المعروفة: ${analysis.sourceFileCount}')
      ..writeln('- اللغة الأبرز: ${analysis.primaryLanguage}')
      ..writeln('\n## توزيع الملفات');
    for (final entry in analysis.languages.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
      report.writeln('- ${entry.key}: ${entry.value}');
    }
    report.writeln('\n## نقاط الدخول المكتشفة');
    if (analysis.entryPoints.isEmpty) {
      report.writeln('- لم يتم التعرف على نقطة دخول شائعة.');
    } else {
      for (final path in analysis.entryPoints) {
        report.writeln('- `$path`');
      }
    }
    report.writeln('\n## الاعتماديات');
    if (dependencies.isEmpty) {
      report.writeln('- لم يتم العثور على تعريفات اعتماديات مدعومة.');
    } else {
      for (final dependency in dependencies) {
        report.writeln('- `${dependency.name}` — ${dependency.version} (${dependency.source})');
      }
    }
    report
      ..writeln('\n## حدود هذا التقرير')
      ..writeln('- هذا فهرس ساكن للملفات والتعريفات، وليس تحليلاً دلالياً كاملاً للكود.')
      ..writeln('- لا يعني وجود الاعتمادية أنها مثبتة أو متوافقة أو محدثة.')
      ..writeln('- لم يتم تشغيل الاختبارات أو البناء بواسطة مولّد التوثيق.');

    final output = File(p.join(rootPath, 'docs', 'NEXUS_PROJECT_GUIDE.md'));
    await output.parent.create(recursive: true);
    await output.writeAsString(report.toString(), flush: true);
    return output;
  }
}

class NexusImagePayload {
  const NexusImagePayload({required this.base64, required this.mimeType, required this.sizeBytes});
  final String base64;
  final String mimeType;
  final int sizeBytes;
}

class NexusDeviceServices {
  static const MethodChannel _channel = MethodChannel('termai/nexus-device');

  static Future<Map<String, dynamic>> metrics() async {
    final value = await _channel.invokeMapMethod<String, dynamic>('metrics');
    if (value == null) throw StateError('لم تُرجع خدمة Android بيانات الأداء.');
    return value;
  }

  static Future<String?> recognizeSpeech() async {
    final text = await _channel.invokeMethod<String>('recognizeSpeech');
    final value = text?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static Future<NexusImagePayload?> pickImage() async {
    final value = await _channel.invokeMapMethod<String, dynamic>('pickImage');
    if (value == null) return null;
    final base64 = value['base64'];
    final mimeType = value['mimeType'];
    final sizeBytes = value['sizeBytes'];
    if (base64 is! String || mimeType is! String || sizeBytes is! num) {
      throw const FormatException('بيانات الصورة المستلمة من Android غير صالحة.');
    }
    return NexusImagePayload(base64: base64, mimeType: mimeType, sizeBytes: sizeBytes.toInt());
  }

  static Future<void> openHtmlPreview(String absolutePath) async {
    await _channel.invokeMethod<void>('openHtmlPreview', {'path': absolutePath});
  }
}
