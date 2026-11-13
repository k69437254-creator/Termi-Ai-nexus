import 'package:material_ui/material_ui.dart';

import 'core/nexus_theme.dart';
import 'core/project_coordinator.dart';
import 'core/project_execution_manager.dart';
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
  late final ProjectExecutionManager _executionManager =
      ProjectExecutionManager(coordinator: _coordinator);
  int _selected = 0;

  Widget _page() => switch (_selected) {
        0 => OfficeScreen(onOpenAssistant: _openAssistant),
        1 => AssistantScreen(coordinator: _coordinator, executionManager: _executionManager, onBack: () => setState(() => _selected = 0)),
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
        'المقر الرقمي',
        'المساعد الذكي',
        'مركز المشاريع',
        'مركز التحكم',
        'طرفية Android',
        'GitHub Workspace',
        'فريق الوكلاء',
        'الإعدادات',
        'محرك Aram AI',
      ][_selected];

  Widget _buildHeader(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
        child: NexusGlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          radius: 21,
          blur: 18,
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  color: NexusPalette.primary.withValues(alpha: 0.10),
                  border: Border.all(color: NexusPalette.primary.withValues(alpha: 0.38)),
                  boxShadow: const [BoxShadow(color: Color(0x3300F0FF), blurRadius: 20)],
                ),
                child: const Icon(Icons.hub_rounded, color: NexusPalette.primary, size: 22),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      const Text('TERMIAI NEXUS', style: TextStyle(color: NexusPalette.text, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.9)),
                      const SizedBox(width: 8),
                      const Text('WORKSPACE', style: TextStyle(color: NexusPalette.muted, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
                    ]),
                    const SizedBox(height: 3),
                    Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NexusPalette.muted, fontSize: 10, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'مركز محرك Aram AI',
                onPressed: () => setState(() => _selected = 8),
                icon: const Icon(Icons.memory_rounded, color: NexusPalette.primary, size: 20),
                style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.04)),
              ),
              Builder(builder: (drawerContext) => IconButton(
                tooltip: 'القائمة الرئيسية',
                onPressed: () => Scaffold.of(drawerContext).openDrawer(),
                icon: const Icon(Icons.menu_rounded, color: NexusPalette.text, size: 21),
                style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.04)),
              )),
            ],
          ),
        ),
      );

  Widget _buildNeuralStrip() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: NexusGlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          radius: 15,
          blur: 14,
          child: Row(
            children: [
              const Text('NEXUS BUS', style: TextStyle(color: NexusPalette.primary, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
              const SizedBox(width: 9),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _BusNode(label: '3D_WORLD', color: NexusPalette.primary),
                    const _BusLink(),
                    _BusNode(label: 'AI_AGENTS', color: NexusPalette.purple),
                    const _BusLink(),
                    _BusNode(label: 'ANDROID_PTY', color: NexusPalette.emerald),
                    const _BusLink(),
                    _BusNode(label: 'GITHUB_CI', color: NexusPalette.amber),
                  ]),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildDock() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 5, 18, 8),
          child: NexusGlassPanel(
            padding: const EdgeInsets.all(5),
            radius: 30,
            blur: 22,
            tint: const Color(0xE6060A14),
            borderColor: const Color(0x30FFFFFF),
            child: Row(children: [
              _DockItem(icon: Icons.hub_outlined, selectedIcon: Icons.hub_rounded, label: 'المقر', selected: _selected == 0, onTap: () => setState(() => _selected = 0)),
              _DockItem(icon: Icons.auto_awesome_outlined, selectedIcon: Icons.auto_awesome, label: 'المساعد', selected: _selected == 1, onTap: _openAssistant),
              _DockItem(icon: Icons.folder_open_outlined, selectedIcon: Icons.folder_rounded, label: 'المشاريع', selected: _selected == 2, onTap: () => setState(() => _selected = 2)),
              _DockItem(icon: Icons.space_dashboard_outlined, selectedIcon: Icons.space_dashboard_rounded, label: 'التحكم', selected: _selected == 3, onTap: () => setState(() => _selected = 3)),
            ]),
          ),
        ),
      );

  Widget _buildDrawer() => NavigationDrawer(
        selectedIndex: _selected,
        onDestinationSelected: (value) {
          Navigator.pop(context);
          setState(() => _selected = value);
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
            child: NexusGlassPanel(
              padding: const EdgeInsets.all(16),
              radius: 21,
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [NexusIconTile(Icons.hub_rounded, size: 42), SizedBox(width: 11), Expanded(child: Text('TERMIAI NEXUS', style: TextStyle(fontSize: 14, letterSpacing: 0.8, fontWeight: FontWeight.w900, color: NexusPalette.text)))]),
                SizedBox(height: 12),
                Text('مركز قيادة موحّد للوكلاء والمشاريع والمحرك.', style: TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.55)),
                SizedBox(height: 10),
                NexusStatusPill('NEURAL COMMAND INTERFACE', icon: Icons.auto_awesome),
              ]),
            ),
          ),
          const Padding(padding: EdgeInsetsDirectional.fromSTEB(25, 0, 25, 8), child: Text('WORKSPACE', style: TextStyle(color: NexusPalette.subtle, fontSize: 9, letterSpacing: 1.6, fontWeight: FontWeight.w900))),
          const NavigationDrawerDestination(icon: Icon(Icons.hub_outlined), selectedIcon: Icon(Icons.hub_rounded), label: Text('المقر الرقمي')),
          const NavigationDrawerDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: Text('المساعد الذكي')),
          const NavigationDrawerDestination(icon: Icon(Icons.folder_open_outlined), selectedIcon: Icon(Icons.folder_rounded), label: Text('مركز المشاريع')),
          const NavigationDrawerDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard_rounded), label: Text('مركز التحكم')),
          const Padding(padding: EdgeInsetsDirectional.fromSTEB(25, 15, 25, 8), child: Text('TOOLS & SYSTEM', style: TextStyle(color: NexusPalette.subtle, fontSize: 9, letterSpacing: 1.6, fontWeight: FontWeight.w900))),
          const NavigationDrawerDestination(icon: Icon(Icons.terminal_rounded), selectedIcon: Icon(Icons.terminal_rounded), label: Text('طرفية Android / PTY')),
          const NavigationDrawerDestination(icon: Icon(Icons.code_rounded), selectedIcon: Icon(Icons.code_rounded), label: Text('GitHub Workspace')),
          const NavigationDrawerDestination(icon: Icon(Icons.groups_2_outlined), selectedIcon: Icon(Icons.groups_2_rounded), label: Text('فريق الوكلاء والذاكرة')),
          const NavigationDrawerDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: Text('الإعدادات')),
          const NavigationDrawerDestination(icon: Icon(Icons.memory_outlined), selectedIcon: Icon(Icons.memory_rounded), label: Text('محرك Aram AI')),
          const SizedBox(height: 18),
        ],
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: NexusPalette.background,
        drawer: _selected == 1 ? null : _buildDrawer(),
        appBar: _selected == 1
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(72),
                child: SafeArea(bottom: false, child: _buildHeader(context)),
              ),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: AlignmentDirectional.topEnd,
              radius: 1.18,
              colors: [Color(0xFF10202D), NexusPalette.background, Color(0xFF090819)],
              stops: [0.0, 0.58, 1.0],
            ),
          ),
          child: SafeArea(
            top: _selected == 1,
            bottom: _selected == 1,
            child: Column(children: [
              if (_selected != 1) _buildNeuralStrip(),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
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
            ]),
          ),
        ),
        bottomNavigationBar: _selected == 1 ? null : _buildDock(),
      );
}

class _DockItem extends StatelessWidget {
  const _DockItem({required this.icon, required this.selectedIcon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected ? NexusPalette.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(25),
            boxShadow: selected ? const [BoxShadow(color: Color(0x4400F0FF), blurRadius: 18, offset: Offset(0, 4))] : const [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(25),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 3),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(selected ? selectedIcon : icon, size: 19, color: selected ? NexusPalette.background : NexusPalette.muted),
                  const SizedBox(height: 3),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: selected ? NexusPalette.background : NexusPalette.muted, fontSize: 9, fontWeight: selected ? FontWeight.w900 : FontWeight.w700)),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _BusNode extends StatelessWidget {
  const _BusNode({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.10), border: Border.all(color: color.withValues(alpha: 0.30)), borderRadius: BorderRadius.circular(7)),
        child: Text(label, style: TextStyle(fontFamily: 'JetBrainsMono', color: color, fontSize: 8, fontWeight: FontWeight.w800)),
      );
}

class _BusLink extends StatelessWidget {
  const _BusLink();
  @override
  Widget build(BuildContext context) => const Padding(padding: EdgeInsets.symmetric(horizontal: 5), child: Icon(Icons.swap_horiz_rounded, color: NexusPalette.subtle, size: 13));
}
