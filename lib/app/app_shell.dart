// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../core/services/project_store.dart';
import '../features/agents/agents_page.dart';
import '../features/home/home_page.dart';
import '../features/monitor/monitor_page.dart';
import '../features/projects/projects_page.dart';
import '../features/settings/settings_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.projectStore, super.key});

  final ProjectStore projectStore;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  void _goTo(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      HomePage(projectStore: widget.projectStore, onOpenProjects: () => _goTo(1)),
      ProjectsPage(projectStore: widget.projectStore),
      const AgentsPage(),
      const MonitorPage(),
      const SettingsPage(),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _selectedIndex, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _goTo,
        height: 70,
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.folder_open_outlined), selectedIcon: Icon(Icons.folder_rounded), label: 'المشاريع'),
          NavigationDestination(icon: Icon(Icons.hub_outlined), selectedIcon: Icon(Icons.hub_rounded), label: 'الوكلاء'),
          NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), selectedIcon: Icon(Icons.monitor_heart_rounded), label: 'المراقبة'),
          NavigationDestination(icon: Icon(Icons.tune_rounded), selectedIcon: Icon(Icons.tune_rounded), label: 'الإعدادات'),
        ],
      ),
    );
  }
}
