import 'dart:io';
import 'package:flutter/material.dart';

ThemeData _applyDesktopInteractionTheme(ThemeData theme) {
  final clickCursor = WidgetStateProperty.resolveWith<MouseCursor?>(
    (states) => states.contains(WidgetState.disabled)
        ? SystemMouseCursors.basic
        : SystemMouseCursors.click,
  );

  return theme.copyWith(
    filledButtonTheme: FilledButtonThemeData(
      style:
          theme.filledButtonTheme.style?.copyWith(mouseCursor: clickCursor) ??
          ButtonStyle(mouseCursor: clickCursor),
    ),
    textButtonTheme: TextButtonThemeData(
      style:
          theme.textButtonTheme.style?.copyWith(mouseCursor: clickCursor) ??
          ButtonStyle(mouseCursor: clickCursor),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style:
          theme.elevatedButtonTheme.style?.copyWith(mouseCursor: clickCursor) ??
          ButtonStyle(mouseCursor: clickCursor),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          theme.outlinedButtonTheme.style?.copyWith(mouseCursor: clickCursor) ??
          ButtonStyle(mouseCursor: clickCursor),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style:
          theme.segmentedButtonTheme.style?.copyWith(
            mouseCursor: clickCursor,
          ) ??
          ButtonStyle(mouseCursor: clickCursor),
    ),
    iconButtonTheme: IconButtonThemeData(
      style:
          theme.iconButtonTheme.style?.copyWith(mouseCursor: clickCursor) ??
          ButtonStyle(mouseCursor: clickCursor),
    ),
    floatingActionButtonTheme: theme.floatingActionButtonTheme.copyWith(
      mouseCursor: clickCursor,
    ),
    switchTheme: theme.switchTheme.copyWith(mouseCursor: clickCursor),
    checkboxTheme: theme.checkboxTheme.copyWith(mouseCursor: clickCursor),
    radioTheme: theme.radioTheme.copyWith(mouseCursor: clickCursor),
    popupMenuTheme: theme.popupMenuTheme.copyWith(mouseCursor: clickCursor),
  );
}

ThemeData _buildTheme({
  required Brightness brightness,
  required Color seedColor,
  required Color scaffoldBackgroundColor,
}) {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    ),
    scaffoldBackgroundColor: scaffoldBackgroundColor,
    fontFamily: Platform.isMacOS ? 'SF Pro Text' : 'Microsoft YaHei',
    useMaterial3: true,
  );
  final scheme = base.colorScheme;

  return _applyDesktopInteractionTheme(
    base.copyWith(
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(
          scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        menuPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
  );
}

ThemeData buildLightTheme() {
  return _buildTheme(
    brightness: Brightness.light,
    seedColor: const Color(0xFF2E7D32),
    scaffoldBackgroundColor: const Color(0xFFF5F6F2),
  );
}

ThemeData buildDarkTheme() {
  return _buildTheme(
    brightness: Brightness.dark,
    seedColor: const Color(0xFF81C784),
    scaffoldBackgroundColor: const Color(0xFF111311),
  );
}
