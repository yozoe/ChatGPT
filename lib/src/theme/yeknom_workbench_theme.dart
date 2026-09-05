import 'package:flutter/material.dart';

import 'yeknom_workbench.dart';

abstract final class YeknomWorkbenchTheme {
  static ThemeData light({
    YeknomPalette? palette,
    YeknomColorPreset preset = YeknomColorPreset.midnight,
  }) => _build(Brightness.light, palette: palette, preset: preset);

  static ThemeData dark({
    YeknomPalette? palette,
    YeknomColorPreset preset = YeknomColorPreset.midnight,
  }) => _build(Brightness.dark, palette: palette, preset: preset);

  static ThemeData _build(
    Brightness brightness, {
    YeknomPalette? palette,
    required YeknomColorPreset preset,
  }) {
    final colors = palette ?? YeknomPalette.fromPreset(preset, brightness);
    final dark = brightness == Brightness.dark;
    final base = ThemeData(useMaterial3: true, brightness: brightness);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: colors.active,
          brightness: brightness,
        ).copyWith(
          primary: colors.active,
          onPrimary:
              ThemeData.estimateBrightnessForColor(colors.active) ==
                  Brightness.dark
              ? Colors.white
              : const Color(0xFF121212),
          primaryContainer: colors.selected,
          onPrimaryContainer: colors.trace,
          secondary: colors.signal,
          onSecondary: colors.onSignal,
          secondaryContainer: colors.signalSelected,
          onSecondaryContainer: colors.trace,
          surface: colors.module,
          onSurface: colors.trace,
          surfaceContainerLowest: colors.bench,
          surfaceContainerLow: colors.bench,
          surfaceContainer: colors.module,
          surfaceContainerHigh: colors.field,
          surfaceContainerHighest: colors.raised,
          outline: colors.controlBorder,
          outlineVariant: colors.border,
          error: colors.fault,
          onError: Colors.white,
        );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.controlBorder),
    );
    final compactShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[colors],
      colorScheme: scheme,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      scaffoldBackgroundColor: colors.bench,
      canvasColor: colors.module,
      dividerColor: colors.border,
      textTheme: base.textTheme
          .apply(bodyColor: colors.trace, displayColor: colors.trace)
          .copyWith(
            bodyLarge: base.textTheme.bodyLarge?.copyWith(
              color: colors.trace,
              fontSize: 14,
              height: 1.45,
            ),
            bodyMedium: base.textTheme.bodyMedium?.copyWith(
              color: colors.trace,
              fontSize: 13,
              height: 1.4,
            ),
            bodySmall: base.textTheme.bodySmall?.copyWith(
              color: colors.muted,
              fontSize: 12,
              height: 1.35,
            ),
            labelLarge: base.textTheme.labelLarge?.copyWith(
              color: colors.trace,
              fontSize: 12,
              height: 1.2,
            ),
            labelMedium: base.textTheme.labelMedium?.copyWith(
              color: colors.muted,
              fontSize: 11,
              height: 1.2,
            ),
            labelSmall: base.textTheme.labelSmall?.copyWith(
              color: colors.muted,
              fontSize: 10,
              height: 1.2,
            ),
            titleLarge: base.textTheme.titleLarge?.copyWith(
              color: colors.trace,
              fontSize: 16,
              height: 1.25,
            ),
            titleMedium: base.textTheme.titleMedium?.copyWith(
              color: colors.trace,
              fontSize: 14,
              height: 1.3,
            ),
            titleSmall: base.textTheme.titleSmall?.copyWith(
              color: colors.trace,
              fontSize: 13,
              height: 1.25,
            ),
          ),
      iconTheme: base.iconTheme.copyWith(color: colors.muted, size: 16),
      cardTheme: CardThemeData(
        color: colors.module,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.module,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.field,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        hintStyle: TextStyle(color: colors.muted, fontSize: 13),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: colors.active, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          shape: compactShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: colors.controlBorder),
          shape: compactShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: compactShape),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: colors.muted),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: colors.field,
        selectedColor: colors.selected,
        side: BorderSide(color: colors.border),
        labelStyle: TextStyle(color: colors.trace, fontSize: 11.5),
        shape: compactShape,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.muted,
        textColor: colors.trace,
        selectedColor: colors.active,
        selectedTileColor: colors.selected,
        dense: true,
        shape: compactShape,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.module,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: colors.border),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF3A3A3A) : const Color(0xFF252525),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 11),
        waitDuration: const Duration(milliseconds: 450),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearTrackColor: colors.field,
        circularTrackColor: colors.field,
      ),
      scrollbarTheme: base.scrollbarTheme.copyWith(
        thumbColor: WidgetStatePropertyAll(colors.controlBorder),
        radius: const Radius.circular(999),
        thickness: const WidgetStatePropertyAll(5),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.active,
        selectionColor: colors.active.withValues(alpha: 0.22),
        selectionHandleColor: colors.active,
      ),
    );
  }
}
