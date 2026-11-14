import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app_shell.dart';
import 'core/nexus_theme.dart';
import 'core/project_coordinator.dart';
import 'models/domain.dart';

const MethodChannel _projectExecutionServiceChannel =
    MethodChannel('termai/project-execution-service');

@pragma('vm:entry-point')
Future<void> projectExecutionEntrypoint(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final projectId = args.isEmpty ? '' : args.first.trim();
  final coordinator = ProjectCoordinator();
  final control = ProjectExecutionControl();

  var success = false;
  String? errorMessage;

  _projectExecutionServiceChannel.setMethodCallHandler((call) async {
    if (call.method != 'cancel') {
      throw MissingPluginException(
        'Unsupported project service method: ${call.method}',
      );
    }

    final data = call.arguments;
    final requestedId = data is Map ? data['projectId']?.toString() : null;
    if (projectId.isEmpty || requestedId != projectId) return false;

    control.cancelRequested = true;

    final requestId = control.requestId;
    if (requestId != null && requestId.isNotEmpty) {
      try {
        await coordinator.cancelGeneration(requestId);
      } catch (_) {
        // The coordinator still observes the cancellation flag and rolls back.
      }
    }

    return true;
  });

  try {
    if (projectId.isEmpty) {
      throw StateError('معرف المشروع غير متوفر.');
    }

    final projects = await coordinator.listProjects();
    ProjectRecord? project;

    for (final item in projects) {
      if (item.id == projectId) {
        project = item;
        break;
      }
    }

    if (project == null) {
      throw StateError('لم يتم العثور على المشروع المطلوب.');
    }

    final result = await coordinator.execute(
      project,
      control: control,
    );

    success = !control.cancelRequested &&
        result.tasks.isNotEmpty &&
        result.tasks.every((task) => task.status == TaskStatus.completed);

    if (!success) {
      final incomplete = result.tasks
          .where((task) => task.status != TaskStatus.completed)
          .map((task) => '${task.title}: ${task.status.name}')
          .join(' | ');
      errorMessage = control.cancelRequested
          ? 'أُلغي التنفيذ بناءً على طلب المستخدم.'
          : incomplete.isEmpty
              ? 'لم تكتمل مهام المشروع.'
              : incomplete;
    }
  } catch (error) {
    errorMessage = error.toString();
  } finally {
    _projectExecutionServiceChannel.setMethodCallHandler(null);
    coordinator.gateway.dispose();
  }

  try {
    await _projectExecutionServiceChannel.invokeMethod<void>(
      'complete',
      <String, Object?>{
        'projectId': projectId,
        'success': success,
        'error': errorMessage,
      },
    );
  } catch (_) {
    // Android service owns completion handling.
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TermiAiNexusApp());
}

class TermiAiNexusApp extends StatelessWidget {
  const TermiAiNexusApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'TermiAI-Nexus',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        theme: NexusTheme.dark,
        darkTheme: NexusTheme.dark,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const AppShell(),
      );
}
