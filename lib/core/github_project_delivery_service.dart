// TERMAI_GITHUB_AUTOMATION_UPDATE_20261116_V1
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/domain.dart';
import 'project_coordinator.dart';
import 'secure_vault.dart';

class GitHubDeliveryException implements Exception {
  const GitHubDeliveryException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Owns the trusted GitHub deployment lifecycle. Tokens never enter agent prompts,
/// workspace files, argv, commit messages, or visible progress events.
class GitHubProjectDeliveryService {
  GitHubProjectDeliveryService({
    required this.coordinator,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const String _api = 'https://api.github.com';
  static const MethodChannel _linux = MethodChannel('termai/linux');
  static const EventChannel _deploymentEvents =
      EventChannel('termai/linux/deployment-events');

  final ProjectCoordinator coordinator;
  final http.Client _client;
  final SecureVault _vault = SecureVault.instance;

  Future<String> _token() async {
    final value = (await _vault.read('github.token')).trim();
    if (value.length < 20 || value.contains(RegExp(r'\s'))) {
      throw const GitHubDeliveryException(
        'اربط حساب GitHub من شاشة GitHub أولاً، ثم أعد تنفيذ الطلب.',
      );
    }
    return value;
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    String? token,
    Duration timeout = const Duration(seconds: 35),
  }) async {
    final secret = token ?? await _token();
    final uri = Uri.parse('$_api$path');
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Authorization': 'Bearer $secret',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'Content-Type': 'application/json',
        'User-Agent': 'TermiAI-Nexus',
      });
    if (body != null) request.body = jsonEncode(body);
    http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(timeout);
    } on TimeoutException {
      throw const GitHubDeliveryException('انتهت مهلة الاتصال بخدمة GitHub.');
    } on SocketException catch (error) {
      throw GitHubDeliveryException('تعذر الاتصال بالإنترنت: ${error.message}');
    } catch (error) {
      if (error is GitHubDeliveryException) rethrow;
      throw GitHubDeliveryException('فشل الاتصال بـ GitHub: $error');
    }
    final response = await http.Response.fromStream(streamed);
    dynamic decoded;
    if (response.bodyBytes.isNotEmpty) {
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        decoded = null;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map ? decoded['message']?.toString() : null;
      final safeMessage = (message ?? 'HTTP ${response.statusCode}')
          .replaceAll(secret, '[TOKEN REDACTED]');
      throw GitHubDeliveryException(
        'رفض GitHub الطلب (${response.statusCode}): $safeMessage',
      );
    }
    return decoded;
  }

  /// Validates the stored token and returns a non-secret account summary.
  Future<Map<String, String>> validateConnection() async {
    final data = await _request('GET', '/user');
    if (data is! Map || data['login'] is! String) {
      throw const GitHubDeliveryException('أعاد GitHub بيانات حساب غير متوقعة.');
    }
    return {
      'login': data['login'].toString(),
      'name': data['name']?.toString() ?? '',
      'avatar_url': data['avatar_url']?.toString() ?? '',
      'html_url': data['html_url']?.toString() ?? '',
    };
  }

  String _repositorySlug(ProjectRecord project) {
    final slug = project.name.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'^[.\-_]+|[.\-_]+$'), '')
        .replaceAll(RegExp(r'-{2,}'), '-');
    final safeId = project.id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (safeId.length < 8) {
      throw const GitHubDeliveryException('معرف المشروع غير صالح لإنشاء اسم مستودع آمن.');
    }
    final suffix = safeId.substring(0, 8).toLowerCase();
    final base = slug.isEmpty ? 'termai-app' : slug.substring(0, slug.length.clamp(0, 42).toInt());
    return '$base-$suffix';
  }

  /// Creates a new private repository before Linux agents begin implementation.
  Future<Map<String, String>> createProjectRepository(
    ProjectRecord project, {
    bool privateRepository = true,
  }) async {
    if (project.githubRepository?.isNotEmpty == true) {
      return {
        'full_name': project.githubRepository!,
        'html_url': project.githubRepositoryUrl ??
            'https://github.com/${project.githubRepository}',
      };
    }
    final user = await validateConnection();
    final name = _repositorySlug(project);
    final data = await _request('POST', '/user/repos', body: {
      'name': name,
      'description': 'Generated by TermiAI-Nexus: ${project.name}'.substring(
        0, 'Generated by TermiAI-Nexus: ${project.name}'.length.clamp(0, 300).toInt(),
      ),
      'private': privateRepository,
      'auto_init': false,
      'has_issues': true,
      'has_projects': false,
      'has_wiki': false,
    });
    if (data is! Map || data['full_name'] is! String || data['html_url'] is! String) {
      throw const GitHubDeliveryException('لم يُرجع GitHub بيانات المستودع الجديد.');
    }
    final fullName = data['full_name'].toString();
    if (!fullName.startsWith('${user['login']}/')) {
      throw const GitHubDeliveryException('المستودع الناتج لا يتبع الحساب المتصل؛ أُوقف النشر.');
    }
    project.githubRepository = fullName;
    project.githubRepositoryUrl = data['html_url'].toString();
    project.deploymentStatus = 'queued';
    project.deploymentMessage = 'أُنشئ المستودع؛ بانتظار بدء تنفيذ Linux.';
    project.deploymentProgress = 0;
    await coordinator.save(project);
    return {'full_name': fullName, 'html_url': project.githubRepositoryUrl!};
  }

  Future<String> _createWorkflow(ProjectRecord project) async {
    final workspace = Directory(project.workspacePath);
    if (!await workspace.exists()) {
      throw const GitHubDeliveryException('مساحة عمل المشروع غير موجودة في مساحة التطبيق.');
    }
    final flutterProject = await File('${project.workspacePath}/pubspec.yaml').exists();
    final androidGradle =
        (await File('${project.workspacePath}/gradlew').exists() ||
         await File('${project.workspacePath}/android/gradlew').exists()) &&
        (await File('${project.workspacePath}/app/build.gradle').exists() ||
         await File('${project.workspacePath}/app/build.gradle.kts').exists() ||
         await File('${project.workspacePath}/android/app/build.gradle').exists() ||
         await File('${project.workspacePath}/android/app/build.gradle.kts').exists());

    String workflow;
    if (flutterProject) {
      workflow = r'''name: Android APK
on:
  push:
    branches: [main]
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: android-apk-${{ github.ref }}
  cancel-in-progress: false
jobs:
  build-android:
    runs-on: ubuntu-latest
    timeout-minutes: 45
    steps:
      - name: Checkout source
        uses: actions/checkout@v4
      - name: Install Java 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - name: Install Flutter stable
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - name: Resolve dependencies
        run: flutter pub get
      - name: Analyze Dart source
        run: flutter analyze
      - name: Run Flutter tests
        run: flutter test
      - name: Build Android APK
        run: flutter build apk --release
      - name: Verify APK output
        shell: bash
        run: |
          set -euo pipefail
          APK="build/app/outputs/flutter-apk/app-release.apk"
          test -s "$APK"
          sha256sum "$APK" | tee apk-sha256.txt
          file "$APK"
      - name: Upload installable APK
        uses: actions/upload-artifact@v4
        with:
          name: TermiAI-APK
          path: |
            build/app/outputs/flutter-apk/app-release.apk
            apk-sha256.txt
          if-no-files-found: error
          retention-days: 30
''';
    } else if (androidGradle) {
      workflow = r'''name: Android APK
on:
  push:
    branches: [main]
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: android-apk-${{ github.ref }}
  cancel-in-progress: false
jobs:
  build-android:
    runs-on: ubuntu-latest
    timeout-minutes: 45
    steps:
      - name: Checkout source
        uses: actions/checkout@v4
      - name: Install Java 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
          cache: gradle
      - name: Verify Gradle Wrapper
        shell: bash
        run: |
          set -euo pipefail
          if [[ -f ./gradlew ]]; then
            WRAPPER_DIR="."
          elif [[ -f ./android/gradlew ]]; then
            WRAPPER_DIR="android"
          else
            echo "Gradle wrapper was not found" >&2
            exit 1
          fi
          test -s "$WRAPPER_DIR/gradlew"
          test -s "$WRAPPER_DIR/gradle/wrapper/gradle-wrapper.jar"
          test -s "$WRAPPER_DIR/gradle/wrapper/gradle-wrapper.properties"
          chmod +x "$WRAPPER_DIR/gradlew"
          echo "GRADLE_WRAPPER_DIR=$WRAPPER_DIR" >> "$GITHUB_ENV"
      - name: Run Android unit tests
        shell: bash
        run: cd "$GRADLE_WRAPPER_DIR" && ./gradlew test --stacktrace
      - name: Build Android debug APK
        shell: bash
        run: cd "$GRADLE_WRAPPER_DIR" && ./gradlew assembleDebug --stacktrace
      - name: Verify APK output
        shell: bash
        run: |
          set -euo pipefail
          mapfile -t APKS < <(find . -type f -path '*/build/outputs/apk/*/*.apk' -size +0c)
          test "${#APKS[@]}" -gt 0
          mkdir -p delivery
          cp "${APKS[0]}" delivery/app-debug.apk
          sha256sum delivery/app-debug.apk | tee delivery/apk-sha256.txt
          file delivery/app-debug.apk
      - name: Upload installable APK
        uses: actions/upload-artifact@v4
        with:
          name: TermiAI-APK
          path: delivery/*
          if-no-files-found: error
          retention-days: 30
''';
    else:
      raise GitHubDeliveryException(
        'لم أتعرف على بنية Android قابلة للبناء. يلزم pubspec.yaml لمشروع Flutter، أو Gradle Wrapper وملفات app/build.gradle لمشروع Android.',
      );
    final workflowPath = Directory('${project.workspacePath}/.github/workflows');
    await workflowPath.create(recursive: true);
    await File('${workflowPath.path}/android-apk.yml').writeAsString(workflow, flush: true);
    return flutterProject ? 'flutter' : 'android-gradle';
  }

  Future<void> _publish(ProjectRecord project,
      void Function(String, String, double)? onProgress) async {
    final repo = project.githubRepository;
    if (repo == null || !RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repo)) {
      throw const GitHubDeliveryException('اسم مستودع GitHub المحفوظ غير صالح.');
    }
    final token = await _token();
    final workflowType = await _createWorkflow(project);
    await _update(project, 'uploading', 'يتحقق Linux من ملفات المصدر ويجهز Git.', 72, onProgress);
    StreamSubscription<dynamic>? subscription;
    try {
      subscription = _deploymentEvents.receiveBroadcastStream().listen((event) {
        if (event is! Map) return;
        if (event['projectId']?.toString() != project.id) return;
        final stage = event['stage']?.toString() ?? 'uploading';
        final message = event['message']?.toString() ?? 'جارٍ نشر المصدر عبر Linux.';
        final percent = (event['percent'] as num?)?.toDouble() ?? 75;
        unawaited(_update(project, stage, message, percent, null).catchError((Object _) {}));
        onProgress?.call(stage, message, percent);
      }, onError: (Object _) {
        onProgress?.call('uploading', 'تعذر بث تفاصيل Git من Linux؛ تستمر نتيجة عملية النشر المباشرة.', 76);
      });
    } catch (_) {
      // The native method result remains authoritative if event streaming is unavailable.
    }
    try {
      final result = await _linux.invokeMapMethod<String, dynamic>(
        'publishWorkspace',
        <String, Object?>{
          'projectId': project.id,
          'workspacePath': project.workspacePath,
          'repository': repo,
          'token': token,
          'commitMessage': 'Build ${project.name} with TermiAI-Nexus',
        },
      );
      if (result == null || result['ok'] != true || result['commit'] is! String) {
        final message = result?['error']?.toString() ?? 'لم يؤكد Linux نجاح git push.';
        throw GitHubDeliveryException(message.replaceAll(token, '[TOKEN REDACTED]'));
      }
      project.githubCommitSha = result['commit'].toString();
      project.deploymentMessage = 'رُفع المصدر إلى GitHub؛ يجري انتظار Actions.';
      project.deploymentStatus = 'building';
      project.deploymentProgress = 82;
      await coordinator.save(project);
      onProgress?.call('building', project.deploymentMessage!, 82);
    } on PlatformException catch (error) {
      throw GitHubDeliveryException(
        (error.message ?? 'فشل نشر المصدر من Linux.').replaceAll(token, '[TOKEN REDACTED]'),
      );
    } finally {
      await subscription?.cancel();
    }
    // Keep the local delivery workflow type as persisted diagnostic context.
    project.deploymentMessage = 'تم رفع مصدر مشروع $workflowType؛ ينتظر النظام نتيجة GitHub Actions.';
    await coordinator.save(project);
  }

  Future<void> _update(ProjectRecord project, String status, String message,
      double percent, void Function(String, String, double)? callback) async {
    project.deploymentStatus = status;
    project.deploymentMessage = message;
    project.deploymentProgress = percent.clamp(0, 100).toDouble();
    project.executionLog.add('${DateTime.now().toIso8601String()} • $message');
    if (project.executionLog.length > 120) {
      project.executionLog.removeRange(0, project.executionLog.length - 120);
    }
    await coordinator.save(project);
    callback?.call(status, message, project.deploymentProgress);
  }

  Future<Map<String, dynamic>> _findRun(ProjectRecord project) async {
    final repo = project.githubRepository!;
    final sha = project.githubCommitSha!;
    final data = await _request(
      'GET',
      '/repos/$repo/actions/runs?head_sha=$sha&per_page=20',
    );
    if (data is! Map || data['workflow_runs'] is! List) {
      throw const GitHubDeliveryException('تعذر قراءة قائمة تشغيلات Actions.');
    }
    for (final item in data['workflow_runs'] as List) {
      if (item is Map && item['head_sha'] == sha) {
        return Map<String, dynamic>.from(item);
      }
    }
    return <String, dynamic>{};
  }

  Future<String> _failureDetails(String repo, int runId) async {
    try {
      final data = await _request('GET', '/repos/$repo/actions/runs/$runId/jobs?per_page=100');
      final jobs = data is Map ? data['jobs'] : null;
      if (jobs is! List) return 'GitHub Actions لم يقدم تفاصيل الخطوات.';
      final failures = <String>[];
      for (final job in jobs.whereType<Map>()) {
        final steps = job['steps'];
        if (steps is! List) continue;
        for (final step in steps.whereType<Map>()) {
          if (step['conclusion'] == 'failure' || step['conclusion'] == 'cancelled') {
            failures.add('${job['name'] ?? 'Job'} → ${step['name'] ?? 'Step'} (${step['conclusion']})');
          }
        }
      }
      return failures.isEmpty
          ? 'سبب الفشل المعلن من GitHub: run conclusion=${(await _findRunById(repo, runId))['conclusion'] ?? 'unknown'}.'
          : 'خطوات الفشل التي سجلها GitHub:\n${failures.join('\n')}\nافتح صفحة Actions لقراءة سجل الخطأ الكامل.';
    } catch (error) {
      return 'تعذر جلب تفاصيل الخطوات: $error';
    }
  }

  Future<Map<String, dynamic>> _findRunById(String repo, int runId) async {
    final data = await _request('GET', '/repos/$repo/actions/runs/$runId');
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _findArtifact(String repo, int runId) async {
    final data = await _request('GET', '/repos/$repo/actions/runs/$runId/artifacts?per_page=100');
    final items = data is Map ? data['artifacts'] : null;
    if (items is List) {
      for (final item in items.whereType<Map>()) {
        final size = (item['size_in_bytes'] as num?)?.toInt() ?? 0;
        if (item['name'] == 'TermiAI-APK' && item['expired'] != true &&
            size > 0 && item['archive_download_url'] is String) {
          return Map<String, dynamic>.from(item);
        }
      }
    }
    return <String, dynamic>{};
  }

  Future<void> publishAndMonitor(
    ProjectRecord project, {
    void Function(String stage, String message, double percent)? onProgress,
    Duration timeout = const Duration(minutes: 50),
  }) async {
    if (project.githubRepository == null) {
      throw const GitHubDeliveryException('لم يُنشأ مستودع GitHub قبل بدء تنفيذ الوكلاء.');
    }
    final started = DateTime.now();
    await _update(project, 'preparing', 'اكتملت مهام الوكلاء؛ يجري إعداد Workflow أندرويد.', 70, onProgress);
    try {
      await _publish(project, onProgress);
      Map<String, dynamic> run = <String, dynamic>{};
      while (DateTime.now().difference(started) < timeout) {
        run = await _findRun(project);
        if (run.isNotEmpty) break;
        await _update(project, 'waiting_for_actions', 'تم رفع commit؛ ينتظر النظام بدء GitHub Actions.', 84, onProgress);
        await Future<void>.delayed(const Duration(seconds: 12));
      }
      if (run.isEmpty) {
        throw const GitHubDeliveryException('لم يظهر تشغيل Actions للـ commit المرفوع خلال المهلة المحددة. تحقق من تفعيل GitHub Actions وصلاحيات المستودع.');
      }
      final runId = (run['id'] as num?)?.toInt();
      if (runId == null) throw const GitHubDeliveryException('أعاد GitHub تشغيل Actions بلا run ID.');
      final runUrl = run['html_url']?.toString();
      if (runUrl == null || !runUrl.startsWith('https://github.com/')) {
        throw const GitHubDeliveryException('أعاد GitHub معرف تشغيل دون رابط Actions صالح.');
      }
      project.githubRunId = runId;
      project.githubRunUrl = runUrl;
      project.deploymentMessage = 'بدأ GitHub Actions؛ يجري البناء والاختبار في GitHub.';
      await coordinator.save(project);
      onProgress?.call('building', project.deploymentMessage!, 85);

      while (DateTime.now().difference(started) < timeout) {
        run = await _findRunById(project.githubRepository!, runId);
        final status = run['status']?.toString();
        if (status == 'completed') break;
        final elapsed = DateTime.now().difference(started).inSeconds;
        final pct = (85 + (elapsed / timeout.inSeconds) * 10).clamp(85, 95).toDouble();
        await _update(project, 'building', 'GitHub Actions قيد التنفيذ؛ الحالة: ${status ?? 'unknown'}.', pct, onProgress);
        await Future<void>.delayed(const Duration(seconds: 15));
      }
      if (run['status'] != 'completed') {
        throw const GitHubDeliveryException('انتهت مهلة انتظار GitHub Actions قبل اكتمال البناء.');
      }
      if (run['conclusion'] != 'success') {
        final details = await _failureDetails(project.githubRepository!, runId);
        throw GitHubDeliveryException('فشل GitHub Actions (conclusion=${run['conclusion'] ?? 'unknown'}).\n$details');
      }
      Map<String, dynamic> artifact = <String, dynamic>{};
      for (var attempt = 0; attempt < 4; attempt++) {
        artifact = await _findArtifact(project.githubRepository!, runId);
        if (artifact.isNotEmpty) break;
        if (attempt < 3) {
          await _update(project, 'verifying_artifact', 'اكتمل Actions؛ يجري انتظار ظهور APK artifact والتحقق من حجمه.', 98, onProgress);
          await Future<void>.delayed(const Duration(seconds: 5));
        }
      }
      if (artifact.isEmpty || artifact['archive_download_url'] is! String) {
        throw const GitHubDeliveryException('نجح تشغيل Actions لكنه لم ينتج artifact صالحاً باسم TermiAI-APK أو كان حجمه صفراً؛ لم أعتبر البناء قابلاً للتنزيل.');
      }
      project.githubArtifactUrl = artifact['archive_download_url'].toString();
      project.deploymentStatus = 'succeeded';
      project.deploymentProgress = 100;
      project.deploymentMessage = 'نجح GitHub Actions وتم التحقق من وجود APK artifact. يمكنك تنزيله من صفحة التشغيل.';
      project.executionLog.add('${DateTime.now().toIso8601String()} • ${project.deploymentMessage}');
      await coordinator.save(project);
      onProgress?.call('succeeded', project.deploymentMessage!, 100);
    } catch (error) {
      final message = error.toString();
      project.deploymentStatus = 'failed';
      project.deploymentMessage = message;
      project.executionLog.add('${DateTime.now().toIso8601String()} • فشل التسليم: $message');
      await coordinator.save(project);
      onProgress?.call('failed', message, project.deploymentProgress);
      rethrow;
    }
  }
}
