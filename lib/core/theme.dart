import 'package:flutter/material.dart';

/// Material 3 theme definitions.
///
/// Light and dark are derived from a single seed so both modes stay visually
/// consistent. LaTeX on a dark background is the known contrast risk, so any
/// change here must be re-checked against the golden tests (T7.3, T9.4).
abstract final class AppTheme {
  static const Color _seed = Color(0xFF3F51B5);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
      ),
      useMaterial3: true,
    );
  }
}
