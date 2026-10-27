import 'package:flutter/material.dart';

const Color paper = Color(0xFFE6E7E1);
const Color ink = Color(0xFF17181A);
const Color cobalt = Color(0xFF2246E8);
const Color butter = Color(0xFFF6D64A);
const Color vermilion = Color(0xFFF4511E);
const Color aluminium = Color(0xFFB6BAB4);
const Color chalk = Color(0xFFFBFAF5);
const Color muted = Color(0xFF5C5E58);
const Color hairline = Color(0xFFC9CBC3);

const Color night = Color(0xFF0F1012);
const Color nightSurface = Color(0xFF1B1D20);
const Color nightSurfaceVariant = Color(0xFF26282B);
const Color nightOnSurface = Color(0xFFECEDE8);
const Color nightMuted = Color(0xFFA9ABA3);
const Color cobaltLight = Color(0xFF93A8FF);
const Color nightHairline = Color(0xFF3A3C3F);

const Color connectedGreen = Color(0xFF1E8E3E);

const String displayFont = 'SmileySans';

const ColorScheme lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: cobalt,
  onPrimary: chalk,
  primaryContainer: Color(0xFFD9E0FF),
  onPrimaryContainer: Color(0xFF0B1230),
  secondary: butter,
  onSecondary: ink,
  secondaryContainer: Color(0xFFFBE9A6),
  onSecondaryContainer: ink,
  tertiary: vermilion,
  onTertiary: chalk,
  error: Color(0xFFB3261E),
  onError: chalk,
  surface: chalk,
  onSurface: ink,
  surfaceContainerHighest: Color(0xFFDCDDD5),
  onSurfaceVariant: muted,
  outline: Color(0xFF8B8E86),
  outlineVariant: hairline,
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: ink,
  onInverseSurface: chalk,
  inversePrimary: cobaltLight,
);

const ColorScheme darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: cobaltLight,
  onPrimary: Color(0xFF0B1230),
  primaryContainer: Color(0xFF1B2A66),
  onPrimaryContainer: Color(0xFFD9E0FF),
  secondary: butter,
  onSecondary: ink,
  secondaryContainer: Color(0xFF4A4320),
  onSecondaryContainer: Color(0xFFFFE9A3),
  tertiary: Color(0xFFFF8A65),
  onTertiary: ink,
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  surface: nightSurface,
  onSurface: nightOnSurface,
  surfaceContainerHighest: nightSurfaceVariant,
  onSurfaceVariant: nightMuted,
  outline: nightHairline,
  outlineVariant: Color(0xFF2E3033),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: nightOnSurface,
  onInverseSurface: ink,
  inversePrimary: cobalt,
);

const TextTheme bajiTextTheme = TextTheme(
  displayLarge: TextStyle(
    fontFamily: displayFont,
    fontSize: 46,
    height: 50 / 46,
    letterSpacing: 0,
  ),
  displayMedium: TextStyle(
    fontFamily: displayFont,
    fontSize: 36,
    height: 40 / 36,
    letterSpacing: 0,
  ),
  displaySmall: TextStyle(
    fontFamily: displayFont,
    fontSize: 28,
    height: 32 / 28,
    letterSpacing: 0,
  ),
  headlineLarge: TextStyle(fontFamily: displayFont, fontSize: 26, height: 30 / 26),
  headlineMedium: TextStyle(fontFamily: displayFont, fontSize: 22, height: 26 / 22),
  headlineSmall: TextStyle(fontFamily: displayFont, fontSize: 20, height: 24 / 20),
  titleLarge: TextStyle(fontFamily: displayFont, fontSize: 19, height: 24 / 19),
  titleMedium: TextStyle(fontFamily: displayFont, fontSize: 16, height: 22 / 16),
  titleSmall: TextStyle(fontFamily: displayFont, fontSize: 14, height: 20 / 14),
  bodyLarge: TextStyle(fontSize: 16, height: 24 / 16),
  bodyMedium: TextStyle(fontSize: 14, height: 21 / 14),
  bodySmall: TextStyle(fontSize: 12, height: 18 / 12),
  labelLarge: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500),
  labelMedium: TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500),
  labelSmall: TextStyle(fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w500),
);

ThemeData bajiTheme(Brightness brightness) {
  final scheme = brightness == Brightness.dark ? darkScheme : lightScheme;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: bajiTextTheme,
    scaffoldBackgroundColor:
        brightness == Brightness.dark ? night : paper,
    canvasColor: scheme.surface,
    splashFactory: InkRipple.splashFactory,
    dividerTheme: DividerThemeData(
      thickness: 1,
      color: scheme.outlineVariant,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 4,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 9),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 18),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
  );
}

