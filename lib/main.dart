import 'package:material_ui/material_ui.dart';

import 'app_shell.dart';
import 'core/nexus_theme.dart';

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
