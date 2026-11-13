import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// AETHERIUM visual tokens. The names are kept compatible with the existing
/// screens so this redesign does not require changing their business logic.
abstract final class NexusPalette {
  static const background = Color(0xFF050811);
  static const page = Color(0xFF080D1A);
  static const card = Color(0xC60A0F1C);
  static const elevated = Color(0xFF0D1525);
  static const glass = Color(0xC60A0F1C);

  static const primary = Color(0xFF00F0FF);
  static const primaryLight = Color(0xFF00F0FF);
  static const primaryDeep = Color(0xFFA855F7);
  static const purple = Color(0xFFA855F7);
  static const emerald = Color(0xFF10B981);
  static const amber = Color(0xFFF59E0B);
  static const crimson = Color(0xFFF43F5E);

  static const text = Color(0xFFF8FAFC);
  static const muted = Color(0xFF94A3B8);
  static const subtle = Color(0xFF64748B);
  static const border = Color(0x26FFFFFF);
  static const success = emerald;
  static const warning = amber;
  static const danger = crimson;
  static const terminal = Color(0xFFA7F3D0);
}

abstract final class NexusTheme {
  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: NexusPalette.primary,
      brightness: Brightness.dark,
      surface: NexusPalette.page,
    ).copyWith(
      primary: NexusPalette.primary,
      onPrimary: NexusPalette.background,
      secondary: NexusPalette.purple,
      onSecondary: Colors.white,
      tertiary: NexusPalette.emerald,
      surface: NexusPalette.page,
      onSurface: NexusPalette.text,
      onSurfaceVariant: NexusPalette.muted,
      outline: NexusPalette.border,
      error: NexusPalette.danger,
      onError: Colors.white,
    );

    final typography = const TextTheme(
      displayLarge: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w900),
      headlineLarge: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w900),
      headlineMedium: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w900),
      headlineSmall: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w800),
      titleLarge: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w900),
      titleMedium: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w800),
      titleSmall: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(color: NexusPalette.text, height: 1.5),
      bodyMedium: TextStyle(color: NexusPalette.muted, height: 1.5),
      bodySmall: TextStyle(color: NexusPalette.muted, height: 1.45),
      labelLarge: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w800, letterSpacing: 0.1),
      labelMedium: TextStyle(color: NexusPalette.muted, fontWeight: FontWeight.w700),
    ).apply(fontFamily: 'Cairo');
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: NexusPalette.background,
      canvasColor: NexusPalette.page,
      dividerColor: NexusPalette.border,
      fontFamily: 'Cairo',
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: NexusPalette.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 76,
        titleSpacing: 16,
      ),
      cardTheme: CardThemeData(
        color: NexusPalette.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: NexusPalette.border),
        ),
      ),
      textTheme: typography,
      primaryTextTheme: ThemeData(brightness: Brightness.dark).primaryTextTheme.apply(fontFamily: 'Cairo'),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF04060D),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: const TextStyle(color: NexusPalette.subtle, fontSize: 12),
        labelStyle: const TextStyle(color: NexusPalette.muted),
        prefixIconColor: NexusPalette.muted,
        suffixIconColor: NexusPalette.muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: NexusPalette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: NexusPalette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: NexusPalette.primary, width: 1.35),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: NexusPalette.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: NexusPalette.primary,
          foregroundColor: NexusPalette.background,
          disabledBackgroundColor: NexusPalette.elevated,
          disabledForegroundColor: NexusPalette.subtle,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NexusPalette.primary,
          side: BorderSide(color: NexusPalette.primary.withValues(alpha: 0.32)),
          minimumSize: const Size(44, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: NexusPalette.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: NexusPalette.muted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: Colors.transparent,
        indicatorColor: NexusPalette.primary.withValues(alpha: 0.16),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? NexusPalette.primary : NexusPalette.muted,
            fontSize: 10,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) =>
            IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? NexusPalette.primary
                  : NexusPalette.muted,
              size: 21,
            )),
      ),
      navigationDrawerTheme: const NavigationDrawerThemeData(
        backgroundColor: Color(0xFF080D1A),
        indicatorColor: Color(0x2600F0FF),
        elevation: 0,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: NexusPalette.page,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: NexusPalette.page,
        showDragHandle: true,
        dragHandleColor: NexusPalette.subtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF0A0F1C),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: NexusPalette.border)),
        titleTextStyle: const TextStyle(color: NexusPalette.text, fontSize: 17, fontWeight: FontWeight.w900),
        contentTextStyle: const TextStyle(color: NexusPalette.muted, height: 1.5, fontSize: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xF0090E1C),
        contentTextStyle: const TextStyle(color: NexusPalette.text, fontSize: 12),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: NexusPalette.primary.withValues(alpha: 0.25))),
      ),
      dividerTheme: const DividerThemeData(color: NexusPalette.border, thickness: 1, space: 22),
      listTileTheme: const ListTileThemeData(
        iconColor: NexusPalette.muted,
        textColor: NexusPalette.text,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: NexusPalette.primary,
        linearTrackColor: Color(0x1FFFFFFF),
        circularTrackColor: Color(0x1FFFFFFF),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? NexusPalette.background : NexusPalette.muted),
        trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? NexusPalette.primary : NexusPalette.elevated),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: NexusPalette.primary,
        selectionColor: Color(0x6600F0FF),
        selectionHandleColor: NexusPalette.primary,
      ),
    );
  }
}

class NexusGlassPanel extends StatelessWidget {
  const NexusGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.blur = 18,
    this.tint,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final Color? tint;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tint ?? NexusPalette.glass,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: borderColor ?? NexusPalette.border),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  (tint ?? const Color(0xC60A0F1C)).withValues(alpha: 0.92),
                  const Color(0xE6050811),
                ],
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x99000000), blurRadius: 30, offset: Offset(0, 16)),
                BoxShadow(color: Color(0x1200F0FF), blurRadius: 20, spreadRadius: -5),
              ],
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
}

class NexusPageHeader extends StatelessWidget {
  const NexusPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.kicker = 'AETHERIUM 3D  /  NEXUS CORE',
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 14),
  });

  final String title;
  final String subtitle;
  final String kicker;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kicker, style: const TextStyle(color: NexusPalette.primary, fontSize: 9, letterSpacing: 1.55, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(title, style: const TextStyle(color: NexusPalette.text, fontSize: 19, fontWeight: FontWeight.w900, height: 1.18)),
                  const SizedBox(height: 5),
                  Text(subtitle, style: const TextStyle(color: NexusPalette.muted, fontSize: 10, height: 1.5)),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
      );
}

class NexusSectionHeader extends StatelessWidget {
  const NexusSectionHeader(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: NexusPalette.text, fontSize: 13, fontWeight: FontWeight.w900)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle!, style: const TextStyle(color: NexusPalette.muted, fontSize: 10)),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      );
}

class NexusStatusPill extends StatelessWidget {
  const NexusStatusPill(this.label, {super.key, this.color = NexusPalette.primary, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 6)],
          Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
        ]),
      );
}

class NexusIconTile extends StatelessWidget {
  const NexusIconTile(this.icon, {super.key, this.color = NexusPalette.primary, this.size = 44});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withValues(alpha: 0.32)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 18, spreadRadius: -3)],
        ),
        child: Icon(icon, color: color, size: size * 0.48),
      );
}
