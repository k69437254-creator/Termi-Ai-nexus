import 'package:material_ui/material_ui.dart';

import 'core/nexus_theme.dart';
import 'core/project_coordinator.dart';
import 'screens/agents_screen.dart';
import 'screens/assistant_screen.dart';
import 'screens/control_screen.dart';
import 'screens/engine_center_screen.dart';
import 'screens/github_screen.dart';
import 'screens/office_screen.dart';
import 'screens/projects_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/terminal_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final ProjectCoordinator _coordinator = ProjectCoordinator();
  int _selected = 0;

  Widget _page() => switch (_selected) {
        0 => OfficeScreen(onOpenAssistant: () => _openAssistant()),
        1 => AssistantScreen(
            coordinator: _coordinator,
            onBack: () => setState(() => _selected = 0),
          ),
        2 => ProjectsScreen(coordinator: _coordinator),
        3 => const ControlScreen(),
        4 => const TerminalScreen(),
        5 => const GitHubScreen(),
        6 => const AgentsScreen(),
        7 => const SettingsScreen(),
        8 => const EngineCenterScreen(),
        _ => OfficeScreen(onOpenAssistant: _openAssistant),
      };

  void _openAssistant() => setState(() => _selected = 1);

  String get _title => const [
        'مقر الوكلاء',
        'المساعد الذكي',
        'مركز المشاريع',
        'مركز التحكم',
        'طرفية Android',
        'GitHub Workspace',
        'فريق الوكلاء',
        'الإعدادات',
        'محرك Aram AI',
      ][_selected];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: _selected == 1
            ? null
            : AppBar(
                title: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [NexusPalette.primaryLight, NexusPalette.primaryDeep],
                        ),
                        boxShadow: const [
                          BoxShadow(color: Color(0x338B5CF6), blurRadius: 18, offset: Offset(0, 5)),
                        ],
                      ),
                      child: const Icon(Icons.hub_rounded, color: Colors.white, size: 21),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 3),
                          const Text(
                            'OBSIDIAN  /  NEXUS WORKSPACE',
                            style: TextStyle(fontSize: 8, letterSpacing: 1.45, color: NexusPalette.primaryLight, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: 'مركز محرك Aram AI',
                    onPressed: () => setState(() => _selected = 8),
                    icon: const Icon(Icons.memory_rounded),
                  ),
                  IconButton(
                    tooltip: 'الإعدادات',
                    onPressed: () => setState(() => _selected = 7),
                    icon: const Icon(Icons.tune_rounded),
                  ),
                  const SizedBox(width: 5),
                ],
              ),
        drawer: _selected == 1
            ? null
            : NavigationDrawer(
                selectedIndex: _selected,
                onDestinationSelected: (value) {
                  Navigator.pop(context);
                  setState(() => _selected = value);
                },
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                    child: NexusGlassPanel(
                      padding: const EdgeInsets.all(17),
                      radius: 20,
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            NexusIconTile(Icons.hub_rounded, size: 40),
                            SizedBox(width: 11),
                            Expanded(child: Text('TERMI AI NEXUS', style: TextStyle(fontSize: 14, letterSpacing: 1.2, fontWeight: FontWeight.w900))),
                          ]),
                          SizedBox(height: 12),
                          Text('مقر واحد، وفريق من الوكلاء المتخصصين.', style: TextStyle(color: NexusPalette.muted, fontSize: 11, height: 1.5)),
                          SizedBox(height: 9),
                          NexusStatusPill('OBSIDIAN INTERFACE', icon: Icons.auto_awesome),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(25, 0, 25, 8),
                    child: Text('WORKSPACE', style: TextStyle(color: NexusPalette.subtle, fontSize: 9, letterSpacing: 1.6, fontWeight: FontWeight.w900)),
                  ),
                  const NavigationDrawerDestination(icon: Icon(Icons.hub_outlined), selectedIcon: Icon(Icons.hub_rounded), label: Text('مقر الوكلاء')),
                  const NavigationDrawerDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: Text('المساعد الذكي')),
                  const NavigationDrawerDestination(icon: Icon(Icons.folder_open_outlined), selectedIcon: Icon(Icons.folder_rounded), label: Text('مركز المشاريع')),
                  const NavigationDrawerDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard_rounded), label: Text('مركز التحكم')),
                  const Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(25, 15, 25, 8),
                    child: Text('TOOLS & SYSTEM', style: TextStyle(color: NexusPalette.subtle, fontSize: 9, letterSpacing: 1.6, fontWeight: FontWeight.w900)),
                  ),
                  const NavigationDrawerDestination(icon: Icon(Icons.terminal_rounded), selectedIcon: Icon(Icons.terminal_rounded), label: Text('طرفية Android / PTY')),
                  const NavigationDrawerDestination(icon: Icon(Icons.code_rounded), selectedIcon: Icon(Icons.code_rounded), label: Text('GitHub')),
                  const NavigationDrawerDestination(icon: Icon(Icons.groups_2_outlined), selectedIcon: Icon(Icons.groups_2_rounded), label: Text('فريق الوكلاء والذاكرة')),
                  const NavigationDrawerDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: Text('الإعدادات')),
                  const NavigationDrawerDestination(icon: Icon(Icons.memory_outlined), selectedIcon: Icon(Icons.memory_rounded), label: Text('محرك Aram AI')),
                  const SizedBox(height: 18),
                ],
              ),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: AlignmentDirectional.topEnd,
              radius: 1.35,
              colors: [Color(0xFF171126), NexusPalette.background],
            ),
          ),
          child: SafeArea(
            top: _selected == 1,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.018), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(key: ValueKey(_selected), child: _page()),
            ),
          ),
        ),
        bottomNavigationBar: _selected == 1
            ? null
            : NavigationBar(
                selectedIndex: _selected <= 3 ? _selected : 0,
                onDestinationSelected: (value) => setState(() => _selected = value),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.hub_outlined), selectedIcon: Icon(Icons.hub_rounded), label: 'المقر'),
                  NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'المساعد'),
                  NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder_rounded), label: 'المشاريع'),
                  NavigationDestination(icon: Icon(Icons.tune_rounded), selectedIcon: Icon(Icons.tune_rounded), label: 'التحكم'),
                ],
              ),
      );
}
