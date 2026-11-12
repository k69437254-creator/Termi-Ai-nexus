import 'package:material_ui/material_ui.dart';
import 'core/project_coordinator.dart';
import 'screens/assistant_screen.dart';
import 'screens/control_screen.dart';
import 'screens/github_screen.dart';
import 'screens/office_screen.dart';
import 'screens/projects_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/terminal_screen.dart';
import 'screens/agents_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final ProjectCoordinator _coordinator = ProjectCoordinator();
  int _selected = 0;

  Widget _page() => switch (_selected) {
    0 => OfficeScreen(onOpenAssistant: () => setState(() => _selected = 1)),
    1 => AssistantScreen(coordinator: _coordinator),
    2 => ProjectsScreen(coordinator: _coordinator),
    3 => ControlScreen(),
    4 => const TerminalScreen(),
    5 => const GitHubScreen(),
    6 => const AgentsScreen(),
    7 => const SettingsScreen(),
    _ => OfficeScreen(onOpenAssistant: () => setState(() => _selected = 1)),
  };

  String get _title => const ['مقر الوكلاء', 'المساعد الذكي', 'مركز المشاريع', 'مركز التحكم', 'طرفية Android', 'GitHub', 'فريق الوكلاء', 'الإعدادات'][_selected];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)), const Text('TERMI AI NEXUS', style: TextStyle(fontSize: 9, letterSpacing: 2.2, color: Color(0xFF70BBD3)))]), actions: [IconButton(tooltip: 'الإعدادات', icon: const Icon(Icons.tune_rounded), onPressed: () => setState(() => _selected = 7))]),
    drawer: NavigationDrawer(
      selectedIndex: _selected,
      onDestinationSelected: (value) { Navigator.pop(context); setState(() => _selected = value); },
      children: const [
        Padding(padding: EdgeInsets.fromLTRB(24, 24, 24, 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('TERMI AI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)), SizedBox(height: 4), Text('NEXUS WORKSPACE', style: TextStyle(color: Color(0xFF70BBD3), fontSize: 10, letterSpacing: 2))])),
        NavigationDrawerDestination(icon: Icon(Icons.hub_outlined), selectedIcon: Icon(Icons.hub), label: Text('مقر الوكلاء')),
        NavigationDrawerDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: Text('المساعد الذكي')),
        NavigationDrawerDestination(icon: Icon(Icons.folder_open_outlined), selectedIcon: Icon(Icons.folder), label: Text('المشاريع')),
        NavigationDrawerDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard), label: Text('مركز التحكم')),
        Divider(),
        NavigationDrawerDestination(icon: Icon(Icons.terminal), selectedIcon: Icon(Icons.terminal), label: Text('طرفية Android / PTY')),
        NavigationDrawerDestination(icon: Icon(Icons.code), selectedIcon: Icon(Icons.code), label: Text('GitHub')),
        NavigationDrawerDestination(icon: Icon(Icons.groups_2_outlined), selectedIcon: Icon(Icons.groups_2), label: Text('الوكلاء والذاكرة')),
        NavigationDrawerDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('الإعدادات')),
      ],
    ),
    body: SafeArea(child: AnimatedSwitcher(duration: const Duration(milliseconds: 180), child: KeyedSubtree(key: ValueKey(_selected), child: _page()))),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _selected <= 3 ? _selected : 0,
      onDestinationSelected: (value) => setState(() => _selected = value),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.hub_outlined), selectedIcon: Icon(Icons.hub), label: 'المقر'),
        NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'المساعد'),
        NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'المشاريع'),
        NavigationDestination(icon: Icon(Icons.tune), selectedIcon: Icon(Icons.tune), label: 'التحكم'),
      ],
    ),
  );
}
