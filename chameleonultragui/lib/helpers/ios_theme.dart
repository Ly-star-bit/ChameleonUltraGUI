import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Builds an iOS-flavoured Material theme: iOS system greys for the grouped
/// background, flat white (or near-black) cards, iOS-green switches, rounded
/// dialogs and the user's chosen [accent] as the tint. Keeps Material widgets
/// so the app still feels right on Android and desktop, while reading as iOS.
ThemeData buildIosTheme(Brightness brightness, Color accent) {
  final isDark = brightness == Brightness.dark;

  // iOS system colours.
  const groupedBgLight = Color(0xFFF2F2F7);
  const groupedBgDark = Color(0xFF000000);
  const cardLight = Color(0xFFFFFFFF);
  const cardDark = Color(0xFF1C1C1E);
  const separatorLight = Color(0x5C3C3C43); // ~0.36 opacity
  const separatorDark = Color(0x99545458);
  const iosGreen = Color(0xFF34C759);
  const trackOffLight = Color(0xFFE9E9EA);
  const trackOffDark = Color(0xFF39393D);

  final scaffoldBg = isDark ? groupedBgDark : groupedBgLight;
  final cardBg = isDark ? cardDark : cardLight;
  final separator = isDark ? separatorDark : separatorLight;
  final onSurface = isDark ? Colors.white : Colors.black;

  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
  ).copyWith(
    surface: cardBg,
    // Keep the accent as the primary so the user's colour choice still applies.
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffoldBg,
    dividerColor: separator,
    dividerTheme: DividerThemeData(
      color: separator,
      thickness: 0.5,
      space: 0.5,
    ),
    cardTheme: CardThemeData(
      color: cardBg,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scaffoldBg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: onSurface,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: scaffoldBg,
        statusBarBrightness: brightness,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cardBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cardBg,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? iosGreen
              : (isDark ? trackOffDark : trackOffLight)),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cardBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: accent.withValues(alpha: 0.16),
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      dense: false,
      minVerticalPadding: 10,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: accent),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: cardBg,
        foregroundColor: accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      filled: true,
      fillColor: cardBg,
    ),
    splashFactory: NoSplash.splashFactory, // iOS has no ripple
    highlightColor: Colors.transparent,
  );
}
