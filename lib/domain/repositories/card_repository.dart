import 'package:flashcards2/domain/entities/card.dart';
import 'package:flashcards2/domain/entities/card_search.dart';
import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/entities/theme.dart';
import 'package:flashcards2/domain/scheduling/due_queue.dart';

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

  /// Every card of a non-archived course with its theme and course context.
  ///
  /// The candidate set for the global card search: matching happens on top of
  /// this list, so scoping, archived-course exclusion and the deterministic
  /// course/theme/card ordering are guaranteed here.
  Future<List<ScopedCard>> findCardsWithContext({int? courseId, int? themeId});

  Future<Card> createCard(Card card);

  Future<void> updateCard(Card card);

  Future<void> deleteCard(int id);

  Future<CardImage> addImage(CardImage image);

  Future<List<CardImage>> findImagesByCard(int cardId);

  Future<void> deleteImage(int id);

  /// The scheduler's state row for a card, if it has one yet.
  Future<ScheduleState?> findScheduleState(int cardId);

  Future<void> upsertScheduleState(ScheduleState state);

  /// Cards due at or before [dueBefore], across one course, one theme, or all.
  ///
  /// Only cards that have been reviewed at least once have a schedule row, so
  /// this is the review queue — not the new-card queue. See [findNewEntries].
  Future<List<DueEntry>> findDueEntries({
    required DateTime dueBefore,
    int? courseId,
    int? themeId,
    int? limit,
  });

  /// Cards that have never been reviewed, in one course, one theme, or all.
  ///
  /// The complement of [findDueEntries]. A session needs both: without this a
  /// new course would never surface a single card.
  Future<List<DueEntry>> findNewEntries({
    int? courseId,
    int? themeId,
    int? limit,
  });
}
