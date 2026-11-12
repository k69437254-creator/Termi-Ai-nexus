import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'app_shell.dart';
import '../core/services/project_store.dart';

class TermiaiApp extends StatelessWidget {
  const TermiaiApp({required this.projectStore, super.key});

  final ProjectStore projectStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TermiAI-Nexus',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: AppShell(projectStore: projectStore),
      ),
    );
  }
}
