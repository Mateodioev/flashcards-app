import 'package:flashcards2/domain/entities/card.dart';
import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/entities/theme.dart';

/// Persistence boundary for themes and their cards.
///
/// One interface for the nested authoring hierarchy because a theme has no
/// meaningful existence without its course, and a card none without its theme.
abstract interface class CardRepository {
  Future<Theme?> findThemeById(int id);

  Future<List<Theme>> findThemesByCourse(int courseId);

  Future<Theme> createTheme(Theme theme);

  Future<void> updateTheme(Theme theme);

  Future<void> deleteTheme(int id);

  Future<Card?> findCardById(int id);

  Future<List<Card>> findCardsByTheme(int themeId);

  Future<Card> createCard(Card card);

  Future<void> updateCard(Card card);

  Future<void> deleteCard(int id);

  Future<CardImage> addImage(CardImage image);

  Future<List<CardImage>> findImagesByCard(int cardId);

  Future<void> deleteImage(int id);

  /// The scheduler's state row for a card, if it has one yet.
  Future<ScheduleState?> findScheduleState(int cardId);

  Future<void> upsertScheduleState(ScheduleState state);
}
