import 'package:flutter/material.dart';

const appGreen = Color(0xff286149);
const appBackground = Color(0xfff5f6f2);
const appSurface = Color(0xffffffff);
const appInk = Color(0xff20271f);
const appMuted = Color(0xff787878);
const appLine = Color(0xffe5e8e1);

Color appAccent(BuildContext context) => Theme.of(context).colorScheme.primary;

ThemeData buildAppTheme(bool dark) {
  final scheme = ColorScheme.fromSeed(
    seedColor: dark ? const Color(0xffbdbdbd) : appGreen,
    brightness: dark ? Brightness.dark : Brightness.light,
    surface: dark ? const Color(0xff242424) : appSurface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xff141414) : appBackground,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xff1c1c1c) : appSurface,
      foregroundColor: dark ? const Color(0xfff2f2f2) : appInk,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: dark ? const Color(0xfff2f2f2) : appInk,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xff242424) : appSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: dark ? const Color(0xff3b3b3b) : appLine),
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    dividerColor: dark ? const Color(0xff3b3b3b) : appLine,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xff1a1a1a) : appBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: dark ? const Color(0xff3b3b3b) : appLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: dark ? const Color(0xff3b3b3b) : appLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
  );
}
