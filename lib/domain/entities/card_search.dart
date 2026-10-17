import 'package:flashcards2/domain/entities/card.dart';
import 'package:flashcards2/domain/entities/theme.dart';

/// A card together with the theme and course it belongs to.
///
/// Search results need the full context trail because a bare card tells the
/// learner nothing about where it lives: three courses may each carry the
/// same card text. The repository resolves the names in one join instead of
/// letting the caller walk theme by theme.
class ScopedCard {
  const new({
    required this.card,
    required this.theme,
    required this.courseName,
  });

  final Card card;
  final Theme theme;

  /// The name of the course that owns [theme].
  final String courseName;
}
