import 'package:flutter/material.dart';
import 'app_shell.dart';

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
    darkTheme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4DB7D5), brightness: Brightness.dark, surface: const Color(0xFF111B2B)),
      scaffoldBackgroundColor: const Color(0xFF0A1220),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0A1220), foregroundColor: Color(0xFFEAF3FF), centerTitle: false),
      cardTheme: CardThemeData(color: const Color(0xFF121F31), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0x223D6387)))),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: const Color(0xFF14243A), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none), hintStyle: const TextStyle(color: Color(0xFF8499B3))),
    ),
    builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox.shrink()),
    home: const AppShell(),
  );
}
