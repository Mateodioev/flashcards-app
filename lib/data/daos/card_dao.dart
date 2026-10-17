import 'package:drift/drift.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/tables/tables.dart';

part 'card_dao.g.dart';

/// A due card with the theme and course it belongs to.
///
/// A data-layer shape, deliberately not the domain `DueEntry`: the DAO must not
/// depend on `domain/`, so the repository maps between them.
class DueScheduleRow {
  const new({
    required this.cardId,
    required this.themeId,
    required this.courseId,
    required this.due,
  });

  final int cardId;
  final int themeId;
  final int courseId;
  final DateTime due;
}

/// A card joined with the theme and course it belongs to.
///
/// A data-layer shape, like [DueScheduleRow]: the DAO stays free of `domain/`
/// and the repository maps row types into entities.
class ScopedCardRow {
  const new({
    required this.card,
    required this.theme,
    required this.course,
  });

  final CardRow card;
  final ThemeRow theme;
  final CourseRow course;
}

/// Create/read/update/delete for the course -> theme -> card -> image
/// hierarchy, plus the card's schedule state.
@DriftAccessor(tables: [Themes, Cards, CardImages, ScheduleStates])
class CardDao extends DatabaseAccessor<AppDatabase> with _$CardDaoMixin {
  new(super.attachedDatabase);

  // --- Themes -------------------------------------------------------------

  Future<List<ThemeRow>> themesByCourse(int courseId) {
    return (select(themes)..where((t) => t.courseId.equals(courseId))).get();
  }

  Future<ThemeRow?> themeById(int id) {
    return (select(themes)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<ThemeRow> createTheme(ThemesCompanion theme) {
    return into(themes).insertReturning(theme);
  }

  Future<bool> updateTheme(ThemeRow theme) => update(themes).replace(theme);

  Future<int> deleteTheme(int id) {
    return (delete(themes)..where((t) => t.id.equals(id))).go();
  }

  // --- Cards --------------------------------------------------------------

  Future<List<CardRow>> cardsByTheme(int themeId) {
    return (select(cards)..where((t) => t.themeId.equals(themeId))).get();
  }

  /// Every card of a non-archived course, joined with its theme and course.
  ///
  /// Feeds the global card search: the search screen matches and presents,
  /// this query scopes and orders. Ordered by course, theme and card id so a
  /// re-run of the same query is byte-stable rather than dependent on
  /// SQLite's row order.
  Future<List<ScopedCardRow>> cardsInScope({int? courseId, int? themeId}) {
    final query =
        select(cards).join([
            innerJoin(themes, themes.id.equalsExp(cards.themeId)),
            innerJoin(courses, courses.id.equalsExp(themes.courseId)),
          ])
          ..where(courses.archived.equals(false))
          ..orderBy([
            OrderingTerm.asc(courses.id),
            OrderingTerm.asc(themes.id),
            OrderingTerm.asc(cards.id),
          ]);

    if (courseId != null) {
      query.where(courses.id.equals(courseId));
    }
    if (themeId != null) {
      query.where(themes.id.equals(themeId));
    }

    return query.get().then(
      (rows) => rows.map((row) {
        return ScopedCardRow(
          card: row.readTable(cards),
          theme: row.readTable(themes),
          course: row.readTable(courses),
        );
      }).toList(),
    );
  }

  Future<CardRow?> cardById(int id) {
    return (select(cards)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<CardRow> createCard(CardsCompanion card) {
    return into(cards).insertReturning(card);
  }

  Future<bool> updateCard(CardRow card) => update(cards).replace(card);

  Future<int> deleteCard(int id) {
    return (delete(cards)..where((t) => t.id.equals(id))).go();
  }

  // --- Images -------------------------------------------------------------

  Future<List<CardImageRow>> imagesByCard(int cardId) {
    return (select(cardImages)
          ..where((t) => t.cardId.equals(cardId))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
  }

  Future<CardImageRow> addImage(CardImagesCompanion image) {
    return into(cardImages).insertReturning(image);
  }

  Future<int> deleteImage(int id) {
    return (delete(cardImages)..where((t) => t.id.equals(id))).go();
  }

  // --- Schedule state -----------------------------------------------------

  Future<ScheduleStateRow?> scheduleState(int cardId) {
    return (select(
      scheduleStates,
    )..where((t) => t.cardId.equals(cardId))).getSingleOrNull();
  }

  Future<void> upsertScheduleState(ScheduleStatesCompanion state) {
    return into(scheduleStates).insertOnConflictUpdate(state);
  }

  /// Cards due at or before [dueBefore], joined to their theme and course.
  ///
  /// Requires two hops: schedule -> card -> theme. The inner join means only
  /// cards that have a schedule row appear; a card is given one on its first
  /// review, so this is the **review** queue. New cards come from
  /// [newCardsForCourse], which is the other half of a session.
  ///
  /// Joining once here rather than per card keeps session building at a single
  /// query instead of an N+1 walk.
  Future<List<DueScheduleRow>> dueCards({
    required DateTime dueBefore,
    int? courseId,
    int? themeId,
    int? limit,
  }) {
    final query =
        select(scheduleStates).join([
            innerJoin(cards, cards.id.equalsExp(scheduleStates.cardId)),
            innerJoin(themes, themes.id.equalsExp(cards.themeId)),
          ])
          ..where(scheduleStates.due.isSmallerOrEqualValue(dueBefore))
          ..orderBy([OrderingTerm.asc(scheduleStates.due)]);

    if (courseId != null) {
      query.where(themes.courseId.equals(courseId));
    }
    if (themeId != null) {
      query.where(themes.id.equals(themeId));
    }
    if (limit != null) {
      query.limit(limit);
    }

    return query.get().then(
      (rows) => rows.map((row) {
        final schedule = row.readTable(scheduleStates);
        final theme = row.readTable(themes);
        return DueScheduleRow(
          cardId: schedule.cardId,
          themeId: theme.id,
          courseId: theme.courseId,
          due: schedule.due,
        );
      }).toList(),
    );
  }

  /// Cards that have never been reviewed, in one course or theme.
  ///
  /// The complement of [dueCards]: an anti-join against `schedule_states`,
  /// because a card gets a schedule row only on its first review. Without this
  /// a brand-new course would never surface a single card to study.
  ///
  /// Ordered by card id so intake is stable and reproducible rather than
  /// dependent on SQLite's row order.
  Future<List<DueScheduleRow>> newCardsForCourse({
    int? courseId,
    int? themeId,
    int? limit,
  }) {
    final scheduled = selectOnly(scheduleStates)
      ..addColumns([scheduleStates.cardId]);

    final query =
        select(cards)
            .join([innerJoin(themes, themes.id.equalsExp(cards.themeId))])
          ..where(cards.id.isNotInQuery(scheduled))
          ..orderBy([OrderingTerm.asc(cards.id)]);

    if (courseId != null) {
      query.where(themes.courseId.equals(courseId));
    }
    if (themeId != null) {
      query.where(themes.id.equals(themeId));
    }
    if (limit != null) {
      query.limit(limit);
    }

    return query.get().then(
      (rows) => rows.map((row) {
        final card = row.readTable(cards);
        final theme = row.readTable(themes);
        return DueScheduleRow(
          cardId: card.id,
          themeId: theme.id,
          courseId: theme.courseId,
          // Never scheduled, so it is due immediately by definition.
          due: DateTime.fromMillisecondsSinceEpoch(0),
        );
      }).toList(),
    );
  }
}
