import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

abstract final class NexusPalette {
  static const background = Color(0xFF090A10);
  static const page = Color(0xFF10111A);
  static const card = Color(0xFF151621);
  static const elevated = Color(0xFF1D1D2B);
  static const glass = Color(0xB31B1A29);
  static const primary = Color(0xFF8B5CF6);
  static const primaryLight = Color(0xFFB69AFF);
  static const primaryDeep = Color(0xFF6D42D8);
  static const text = Color(0xFFF5F2FA);
  static const muted = Color(0xFFA49CAF);
  static const subtle = Color(0xFF777184);
  static const border = Color(0xFF292735);
  static const success = Color(0xFF53CDA1);
  static const warning = Color(0xFFFFC46B);
  static const danger = Color(0xFFFF7B8B);
  static const terminal = Color(0xFFB8E7D0);
}

abstract final class NexusTheme {
  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: NexusPalette.primary,
      brightness: Brightness.dark,
      surface: NexusPalette.page,
    ).copyWith(
      primary: NexusPalette.primary,
      onPrimary: Colors.white,
      secondary: NexusPalette.primaryLight,
      onSecondary: NexusPalette.background,
      surface: NexusPalette.page,
      onSurface: NexusPalette.text,
      onSurfaceVariant: NexusPalette.muted,
      outline: NexusPalette.border,
      error: NexusPalette.danger,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: NexusPalette.background,
      canvasColor: NexusPalette.page,
      dividerColor: NexusPalette.border,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: const AppBarTheme(
        backgroundColor: NexusPalette.background,
        foregroundColor: NexusPalette.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 72,
        titleSpacing: 18,
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
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w800),
        headlineLarge: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w800),
        headlineMedium: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w800),
        titleLarge: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w800),
        titleMedium: TextStyle(color: NexusPalette.text, fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(color: NexusPalette.text, height: 1.45),
        bodyMedium: TextStyle(color: NexusPalette.muted, height: 1.45),
        bodySmall: TextStyle(color: NexusPalette.muted, height: 1.4),
        labelLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.1),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NexusPalette.elevated.withValues(alpha: 0.82),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: const TextStyle(color: NexusPalette.subtle, fontSize: 13),
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
          borderSide: const BorderSide(color: NexusPalette.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: NexusPalette.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: NexusPalette.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: NexusPalette.elevated,
          disabledForegroundColor: NexusPalette.subtle,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NexusPalette.primaryLight,
          side: const BorderSide(color: NexusPalette.border),
          minimumSize: const Size(44, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: NexusPalette.primaryLight,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: NexusPalette.muted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: NexusPalette.page.withValues(alpha: 0.98),
        indicatorColor: NexusPalette.primary.withValues(alpha: 0.18),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? NexusPalette.primaryLight : NexusPalette.muted,
            fontSize: 10,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) =>
            IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? NexusPalette.primaryLight
                  : NexusPalette.muted,
              size: 21,
            )),
      ),
      navigationDrawerTheme: const NavigationDrawerThemeData(
        backgroundColor: NexusPalette.page,
        indicatorColor: Color(0x338B5CF6),
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
        backgroundColor: NexusPalette.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: const TextStyle(color: NexusPalette.text, fontSize: 18, fontWeight: FontWeight.w800),
        contentTextStyle: const TextStyle(color: NexusPalette.muted, height: 1.45),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: NexusPalette.elevated,
        contentTextStyle: const TextStyle(color: NexusPalette.text, fontSize: 12),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: const DividerThemeData(color: NexusPalette.border, thickness: 1, space: 22),
      listTileTheme: const ListTileThemeData(
        iconColor: NexusPalette.muted,
        textColor: NexusPalette.text,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: NexusPalette.primaryLight,
        linearTrackColor: NexusPalette.border,
        circularTrackColor: NexusPalette.border,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? Colors.white : NexusPalette.muted),
        trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? NexusPalette.primary : NexusPalette.elevated),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: NexusPalette.primaryLight,
        selectionColor: Color(0x668B5CF6),
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
    this.blur = 12,
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
              border: Border.all(color: borderColor ?? NexusPalette.border.withValues(alpha: 0.9)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  (tint ?? NexusPalette.glass).withValues(alpha: 0.96),
                  NexusPalette.card.withValues(alpha: 0.78),
                ],
              ),
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
    this.kicker = 'TERMI AI NEXUS',
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
                  Text(kicker, style: const TextStyle(color: NexusPalette.primaryLight, fontSize: 9, letterSpacing: 1.8, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(title, style: const TextStyle(color: NexusPalette.text, fontSize: 20, fontWeight: FontWeight.w900, height: 1.15)),
                  const SizedBox(height: 5),
                  Text(subtitle, style: const TextStyle(color: NexusPalette.muted, fontSize: 11, height: 1.45)),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
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
                  Text(title, style: const TextStyle(color: NexusPalette.text, fontSize: 14, fontWeight: FontWeight.w800)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle!, style: const TextStyle(color: NexusPalette.muted, fontSize: 10)),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

class NexusStatusPill extends StatelessWidget {
  const NexusStatusPill(this.label, {super.key, this.color = NexusPalette.primaryLight, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 6)],
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
        ]),
      );
}

class NexusIconTile extends StatelessWidget {
  const NexusIconTile(this.icon, {super.key, this.color = NexusPalette.primaryLight, this.size = 44});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, color: color, size: size * 0.48),
      );
}
