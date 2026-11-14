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

  var success = false;
  String? errorMessage;

  try {
    if (args.isEmpty || args.first.trim().isEmpty) {
      throw StateError('معرف المشروع غير متوفر.');
    }

    final projectId = args.first.trim();
    final coordinator = ProjectCoordinator();

    try {
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

      final result = await coordinator.execute(project);
      success = result.tasks.isNotEmpty &&
          result.tasks.every((task) => task.status == TaskStatus.completed);

      if (!success) {
        final incomplete = result.tasks
            .where((task) => task.status != TaskStatus.completed)
            .map((task) => '${task.title}: ${task.status.name}')
            .join(' | ');
        errorMessage = incomplete.isEmpty
            ? 'لم تكتمل مهام المشروع.'
            : incomplete;
      }
    } finally {
      coordinator.gateway.dispose();
    }
  } catch (error) {
    errorMessage = error.toString();
  }

  try {
    await _projectExecutionServiceChannel.invokeMethod<void>(
      'complete',
      <String, Object?>{
        'projectId': args.isEmpty ? '' : args.first,
        'success': success,
        'error': errorMessage,
      },
    );
  } catch (_) {
    // The Android service owns recovery if the completion channel is lost.
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
