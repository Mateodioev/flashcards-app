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
  /// Requires two hops: schedule -> card -> theme. Filtering to scheduled rows
  /// only is intentional: a card that has never been reviewed has no row here
  /// and is not "due" in the review sense. New-card intake is a separate
  /// concern with its own daily cap.
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
}
